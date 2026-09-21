--[[--
SubRead read-along.

A SubRead subtitle file (.srt) holds the text of the book as cue text, and the
time when the narrator reads each line as cue times. This plugin runs a clock
with the audio player and keeps the place of the narration on the screen.

Only crengine documents (EPUB, FB2, TXT, HTML) are supported. PDF and DjVu
have no xpointer, so the place cannot be followed.

@module koplugin.SubRead
--]]--

local ButtonDialog = require("ui/widget/buttondialog")
local DateTimeWidget = require("ui/widget/datetimewidget")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

local Clock = require("subread.clock")
local Cues = require("subread.cues")
local Srt = require("subread.srt")
local Text = require("subread.text")

-- Search flags of the crengine full text search. The list is in
-- frontend/apps/reader/modules/readersearch.lua:33-41.
-- 0x00FF is every flag except IGNORE_DIACRITICS, the same value that
-- KOReader itself uses by default (readersearch.lua:50). The plugin needs
-- MATCH_ACROSS_TEXT_NODES (0x0001), because a cue often runs over an inline
-- tag, and FOLD_SPACES (0x0020), because the white space of the cue text and
-- of the book text is not the same.
local SEARCH_FLAGS = 0x00FF
-- Stop the search after this many hits. A small number keeps a search that
-- hits early cheap. See readersearch.lua:61.
local SEARCH_MAX_HITS = 20
-- findText origin: -1 whole book, 0 from the current page, 1 after the
-- current page. See ReaderSearch:searchFromStart and searchFromCurrent,
-- readersearch.lua:708-724.
local SEARCH_WHOLE_BOOK = -1
local SEARCH_FROM_CURRENT_PAGE = 0
-- findText direction: 0 forward, 1 backward. See readersearch.lua:29.
local SEARCH_FORWARD = 0

-- The tick never sleeps longer than this, so a change of speed or a device
-- suspend cannot make the follow late for long.
local MAX_SLEEP = 30
local MIN_SLEEP = 0.05
-- After a cue is not found, the plugin waits this many cues before it
-- searches again. The wait doubles with each miss. A failed search reads the
-- book to its end, so this limits the cost when the book misses a stretch.
local MISS_BACKOFF_MAX = 16

-- Characters of cue text shown in a dialog title.
local TITLE_CHARS = 60
-- Characters kept from a selection when the user syncs by selecting text.
-- A long selection can hold the text of more than one cue.
local SYNC_NEEDLE_CHARS = 24

-- Per book settings, kept in the book's sidecar file.
local SETTING_FILE = "subread_srt_file"
local SETTING_POSITION = "subread_position"
local SETTING_SPEED = "subread_speed"
local SETTING_OFFSET = "subread_offset"

local SubRead = WidgetContainer:extend{
    name = "subread",
    is_doc_only = true,
}

function SubRead:init()
    self.clock = Clock.new()
    self.cues = nil            -- Cues index, built when the file is read
    self.srt_path = nil
    self.current_index = nil   -- cue shown now
    self.located = {}          -- cue index -> { start xpointer, end xpointer }
    self.last_xpointer = nil   -- place of the last found cue
    self.miss_streak = 0
    self.retry_from_index = 0
    self.manual_seek = false
    self.scheduled = false
    self.tick_task = function() self:_tick() end

    self.ui.menu:registerToMainMenu(self)
    if self:isSupported() then
        self:registerDispatcherActions()
        self:addToHighlightDialog()
    end
end

function SubRead:isSupported()
    -- self.ui.rolling exists only for crengine documents (readerui.lua:382).
    return self.ui.rolling ~= nil
end

function SubRead:registerDispatcherActions()
    Dispatcher:registerAction("subread_controls",
        { category = "none", event = "SubReadShowControls",
          title = _("SubRead: controls"), rolling = true })
    Dispatcher:registerAction("subread_toggle",
        { category = "none", event = "SubReadToggle",
          title = _("SubRead: start or pause"), rolling = true })
    Dispatcher:registerAction("subread_sync_page",
        { category = "none", event = "SubReadSyncToPage",
          title = _("SubRead: sync to this page"), rolling = true, separator = true })
end

--[[-- Settings ]]--

function SubRead:onReadSettings(config)
    self.srt_path = config:readSetting(SETTING_FILE)
    self.clock = Clock.new{
        position = config:readSetting(SETTING_POSITION) or 0,
        speed = config:readSetting(SETTING_SPEED) or 1.0,
        offset = config:readSetting(SETTING_OFFSET) or 0,
    }
end

function SubRead:onReaderReady()
    if not self:isSupported() then return end
    if self.srt_path and not util.fileExists(self.srt_path) then
        logger.info("SubRead: saved subtitle file is gone:", self.srt_path)
        self.srt_path = nil
    end
    if not self.srt_path then
        self.srt_path = self:findSubtitleBeside(self.ui.document.file)
    end
end

function SubRead:onSaveSettings()
    self:saveState()
end

function SubRead:saveState()
    local settings = self.ui.doc_settings
    if not settings then return end
    if not self.srt_path then
        -- Leave no keys in the sidecar file of a book that does not use the
        -- plugin, and clear them when the user forgets the subtitle file.
        settings:delSetting(SETTING_FILE)
        settings:delSetting(SETTING_POSITION)
        settings:delSetting(SETTING_SPEED)
        settings:delSetting(SETTING_OFFSET)
        return
    end
    settings:saveSetting(SETTING_FILE, self.srt_path)
    settings:saveSetting(SETTING_POSITION, self.clock:getPosition(self:_now()))
    settings:saveSetting(SETTING_SPEED, self.clock.speed)
    settings:saveSetting(SETTING_OFFSET, self.clock.offset)
end

function SubRead:onCloseDocument()
    self:stop()
end

function SubRead:onCloseWidget()
    self:_unschedule()
    self.tick_task = nil
end

--- Looks for <book>.srt or <book>.<lang>.srt beside the book file.
function SubRead:findSubtitleBeside(book_path)
    if not book_path then return nil end
    local directory, file_name = util.splitFilePathName(book_path)
    local base = util.splitFileNameSuffix(file_name)
    if base == "" then return nil end
    local candidate = directory .. base .. ".srt"
    if util.fileExists(candidate) then return candidate end
    -- <book>.<lang>.srt, for example "Dracula.en.srt". The language part is
    -- any name without a dot, so the loop does not need a list of languages.
    local lfs = require("libs/libkoreader-lfs")
    local ok, iterator = pcall(lfs.dir, directory == "" and "." or directory)
    if not ok or type(iterator) ~= "function" then return nil end
    local prefix = base .. "."
    for entry in iterator do
        if entry:sub(1, #prefix) == prefix and entry:sub(-4):lower() == ".srt" then
            local middle = entry:sub(#prefix + 1, -5)
            if middle ~= "" and not middle:find(".", 1, true) then
                return directory .. entry
            end
        end
    end
    return nil
end

--[[-- Subtitle file ]]--

--- Reads the subtitle file. Returns true when the index is ready.
function SubRead:loadSubtitles()
    if self.cues then return true end
    if not self.srt_path then
        self:showMessage(_("No SubRead subtitle file is loaded for this book."))
        return false
    end
    local list, err = Srt.parseFile(self.srt_path)
    if not list then
        self:showMessage(T(_("Could not read the subtitle file:\n%1"), tostring(err)))
        return false
    end
    if #list == 0 then
        self:showMessage(_("The subtitle file holds no cues."))
        return false
    end
    self.cues = Cues.new(list)
    self.located = {}
    logger.info("SubRead: loaded", #list, "cues from", self.srt_path)
    return true
end

function SubRead:setSubtitleFile(path)
    self:stop()
    self.srt_path = path
    self.cues = nil
    self.located = {}
    self.current_index = nil
    self.last_xpointer = nil
    self:saveState()
end

function SubRead:chooseSubtitleFile(touchmenu_instance)
    local PathChooser = require("ui/widget/pathchooser")
    local directory = util.splitFilePathName(self.ui.document.file)
    UIManager:show(PathChooser:new{
        title = _("Select a SubRead subtitle file"),
        path = directory,
        select_directory = false,
        -- With a file_filter set, FileChooser shows only the files that pass
        -- it, even if they are not a book (filechooser.lua:92).
        file_filter = function(file_name)
            return file_name:sub(-4):lower() == ".srt"
        end,
        onConfirm = function(file_path)
            self:setSubtitleFile(file_path)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

--[[-- The clock ]]--

--- Returns a monotonic time in seconds.
-- getElapsedTimeSinceBoot adds the time in standby and in suspend
-- (uimanager.lua:1133), so the follow stays right when the device sleeps
-- while the audio player runs on.
function SubRead:_now()
    return time.to_number(UIManager:getElapsedTimeSinceBoot())
end

function SubRead:start()
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    local now = self:_now()
    if self.clock:getPosition(now) <= 0 then
        local index = self:cueIndexForCurrentPage()
        if index then
            self.clock:seekCueTime(self.cues:get(index).start, now)
        end
    end
    self.clock:start(now)
    -- The reader may have moved the view since the last pause, so drop the
    -- lower limit and let the search start at the page that is shown.
    self.last_xpointer = nil
    self.miss_streak = 0
    self.retry_from_index = 0
    self.current_index = nil -- force a redraw of the cue that is on
    self:_tick()
end

function SubRead:pause()
    self.clock:pause(self:_now())
    self:_unschedule()
    self:saveState()
end

function SubRead:stop()
    if self.clock:isRunning() then
        self.clock:pause(self:_now())
    end
    self:_unschedule()
    if self:isSupported() and self.ui.document then
        self.ui.document:clearSelection()
    end
    self:saveState()
end

function SubRead:toggle()
    if self.clock:isRunning() then
        self:pause()
    else
        self:start()
    end
end

--- Prepares for a jump that the user asked for.
-- The user can jump backward, but the normal search only runs forward from
-- the current page. After a manual jump the next search reads the whole book
-- and uses the place of the nearest cue found before as its lower limit.
function SubRead:_manualSeek()
    self.manual_seek = true
    self.miss_streak = 0
    self.retry_from_index = 0
    self.current_index = nil
end

--- Moves the clock and shows the new place at once.
function SubRead:seekAndShow(position)
    local now = self:_now()
    self.clock:seek(position, now)
    self:_manualSeek()
    self:_tick()
end

function SubRead:skipCues(count)
    if not self:loadSubtitles() then return end
    local now = self:_now()
    local index = self.cues:findNearest(self.clock:getCueTime(now))
    if not index then return end
    index = index + count
    if index < 1 then index = 1 end
    if index > self.cues:count() then index = self.cues:count() end
    self.clock:seekCueTime(self.cues:get(index).start, now)
    self:_manualSeek()
    self:_tick()
end

--[[-- The follow loop ]]--

function SubRead:_unschedule()
    if self.scheduled then
        UIManager:unschedule(self.tick_task)
        self.scheduled = false
    end
end

--- One step of the follow loop.
-- The screen is only touched when the cue changes, never on a bare timer tick.
function SubRead:_tick()
    self.scheduled = false
    if not self.cues then return end
    local now = self:_now()
    local cue_time = self.clock:getCueTime(now)
    local index = self.cues:findByTime(cue_time)
    if index and index ~= self.current_index then
        self.current_index = index
        self:showCue(index)
    end
    self:_schedule(now, cue_time)
end

--- Sleeps until the next cue starts, or MAX_SLEEP, whichever is first.
function SubRead:_schedule(now, cue_time)
    self:_unschedule()
    if not self.clock:isRunning() then return end
    local delay = MAX_SLEEP
    local next_index = self.cues:nextAfter(cue_time)
    if next_index then
        local wait = self.clock:realSecondsUntilCueTime(self.cues:get(next_index).start, now)
        if wait and wait < delay then delay = wait end
    end
    if delay < MIN_SLEEP then delay = MIN_SLEEP end
    UIManager:scheduleIn(delay, self.tick_task)
    self.scheduled = true
end

--- True when the xpointer is at or after the lower limit.
function SubRead:_isAtOrAfter(floor_xpointer, xpointer)
    if not floor_xpointer then return true end
    -- compareXPointers returns 1 when xp2 is after xp1, 0 when they are the
    -- same, -1 when not, nil when one of them is not valid
    -- (credocument.lua:750-754).
    local order = self.ui.document:compareXPointers(floor_xpointer, xpointer)
    return order == nil or order >= 0
end

-- How many cues back to look for a place that is already known.
local FLOOR_LOOKBACK = 50

--- Returns the place of the nearest cue before index that is already found.
function SubRead:_floorFor(index)
    local first = index - FLOOR_LOOKBACK
    if first < 1 then first = 1 end
    for at = index - 1, first, -1 do
        local found = self.located[at]
        if found then return found[1] end
    end
    return nil
end

--- Finds the place of a cue in the book.
-- The search starts at the current page and runs forward, so the plugin never
-- reads the whole book for every cue. Hits before the last found place are
-- dropped, so a word that comes again on the same page cannot pull the
-- follow backward.
-- @return start xpointer, end xpointer, or nil
function SubRead:_locate(index)
    local cached = self.located[index]
    if cached then
        self.manual_seek = false
        return cached[1], cached[2]
    end
    local cue = self.cues:get(index)
    if not cue or cue.no_place then return nil end

    local origin, floor = SEARCH_FROM_CURRENT_PAGE, self.last_xpointer
    if self.manual_seek then
        self.manual_seek = false
        origin, floor = SEARCH_WHOLE_BOOK, self:_floorFor(index)
    end

    local document = self.ui.document
    for _, anchor in ipairs(Text.anchors(cue.norm)) do
        -- findText(pattern, origin, direction, case_insensitive, page, regex,
        -- max_hits, search_flags) (credocument.lua:1442). Each hit holds the
        -- xpointers "start" and "end" (readersearch.lua:446-447).
        local hits = document:findText(anchor, origin, SEARCH_FORWARD,
            true, self.view.state.page, false, SEARCH_MAX_HITS, SEARCH_FLAGS)
        if hits then
            for _, hit in ipairs(hits) do
                if hit.start and self:_isAtOrAfter(floor, hit.start) then
                    self.located[index] = { hit.start, hit["end"] }
                    return hit.start, hit["end"]
                end
            end
        end
    end
    return nil
end

--- Brings the cue on screen and marks it.
function SubRead:showCue(index)
    local cue = self.cues:get(index)
    if not cue or cue.no_place then return end
    -- After a miss, do not search again for the next few cues.
    if index < self.retry_from_index then return end

    local pos0, pos1 = self:_locate(index)
    if not pos0 then
        self.miss_streak = self.miss_streak + 1
        local step = math.floor(2 ^ (self.miss_streak - 1))
        if step > MISS_BACKOFF_MAX then step = MISS_BACKOFF_MAX end
        self.retry_from_index = index + step
        logger.dbg("SubRead: cue", index, "not found, next try at", self.retry_from_index)
        return
    end
    self.miss_streak = 0
    self.retry_from_index = 0
    self.last_xpointer = pos0
    self:drawCue(pos0, pos1)
end

--- Turns the page if needed and draws the mark.
-- The mark is the crengine selection, the same one that KOReader draws for a
-- full text search hit (readersearch.lua:946). crengine draws it itself, so
-- it costs no extra widget, it survives a page turn, and it is never written
-- into the book's annotations.
function SubRead:drawCue(pos0, pos1)
    local document = self.ui.document
    local was_visible = document:isXPointerInCurrentPage(pos0)
    if not was_visible then
        self.ui.rolling:onGotoXPointer(pos0)
    end
    if pos1 then
        document:getTextFromXPointers(pos0, pos1, true)
    end
    -- A page turn needs a partial refresh. A mark that moves inside the same
    -- page only needs the light "ui" refresh.
    UIManager:setDirty(self.view.dialog, was_visible and "ui" or "partial")
end

--- Draws the cue that is on again, after something else used the selection.
function SubRead:redrawCurrentCue()
    if not self.current_index then return end
    local pos0, pos1 = self:_locate(self.current_index)
    if pos0 then self:drawCue(pos0, pos1) end
end

--[[-- Page and time ]]--

--- Returns the text of the current page, or nil.
function SubRead:currentPageText()
    local document = self.ui.document
    local page = document:getCurrentPage()
    if not page then return nil end
    -- getPageXPointer gives the xpointer of the first line of a page
    -- (credocument.lua:888).
    local from_xpointer = document:getPageXPointer(page)
    local to_xpointer = document:getPageXPointer(page + 1)
    if not from_xpointer or not to_xpointer then return nil end
    return document:getTextFromXPointers(from_xpointer, to_xpointer, false)
end

--- Returns the index of the first cue on the current page, or nil.
function SubRead:cueIndexForCurrentPage()
    if not self.cues then return nil end
    local page_text = self:currentPageText()
    if not page_text or page_text == "" then return nil end
    local index = self.cues:findIndexForText(page_text)
    -- getTextFromXPointers with draw_selection false can drop the mark, so
    -- put it back.
    if self.clock:isRunning() then self:redrawCurrentCue() end
    return index
end

function SubRead:showPageTime()
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    local index = self:cueIndexForCurrentPage()
    if not index then
        self:showMessage(_("No cue of the subtitle file was found on this page."))
        return
    end
    local cue = self.cues:get(index)
    local player_time = cue.start + self.clock.offset
    self:showMessage(T(_("This page starts at %1 in the audio.\n\n%2"),
        datetime.secondsToClock(player_time, false),
        Text.ellipsize(cue.text, TITLE_CHARS)))
end

function SubRead:syncToPage()
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    local index = self:cueIndexForCurrentPage()
    if not index then
        self:showMessage(_("No cue of the subtitle file was found on this page."))
        return
    end
    self:syncToCue(index)
end

--- Sets the clock to the start of a cue.
function SubRead:syncToCue(index)
    local cue = self.cues:get(index)
    if not cue then return end
    local now = self:_now()
    self.clock:seekCueTime(cue.start, now)
    self:_manualSeek()
    self:_tick()
    self:showNotification(T(_("Synced to %1"),
        datetime.secondsToClock(cue.start + self.clock.offset, false)))
end

--- Sets the clock from a piece of text that the user selected.
function SubRead:syncToSelectedText(selected)
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    local needle = Text.normalize(selected or "")
    if Text.len(needle) < 4 then
        self:showMessage(_("Select a few more words, so the line can be found."))
        return
    end
    -- A long selection can hold text of more than one cue, so cut it down.
    if Text.len(needle) > SYNC_NEEDLE_CHARS then
        needle = Text.sub(needle, 1, SYNC_NEEDLE_CHARS)
    end
    local index = self.cues:findIndexContaining(needle)
    if not index then
        self:showMessage(_("That text was not found in the subtitle file."))
        return
    end
    self:syncToCue(index)
end

function SubRead:addToHighlightDialog()
    -- "13_" sorts after the last button that KOReader itself adds
    -- (readerhighlight.lua:246-261, qrclipboard.koplugin/main.lua:30).
    self.ui.highlight:addToHighlightDialog("13_subread_sync", function(this)
        return {
            text = _("SubRead: sync here"),
            callback = function()
                local selected = this.selected_text and this.selected_text.text
                this:onClose(true)
                self:syncToSelectedText(selected)
            end,
        }
    end)
end

--[[-- Dialogs ]]--

function SubRead:checkSupported()
    if self:isSupported() then return true end
    self:showMessage(_("SubRead read-along needs an EPUB, FB2, TXT or HTML book. PDF and DjVu are not supported."))
    return false
end

function SubRead:showMessage(text)
    UIManager:show(InfoMessage:new{ text = text })
end

function SubRead:showNotification(text)
    UIManager:show(Notification:new{ text = text, timeout = 2 })
end

function SubRead:statusText()
    local now = self:_now()
    local clock_text = datetime.secondsToClock(self.clock:getPosition(now), false)
    local line = self.clock:isRunning() and T(_("Clock: %1, running"), clock_text)
                                         or T(_("Clock: %1, paused"), clock_text)
    if self.cues and self.current_index then
        local cue = self.cues:get(self.current_index)
        if cue then
            line = line .. "\n" .. Text.ellipsize(cue.text, TITLE_CHARS)
        end
    end
    return line
end

function SubRead:closeControls()
    if self.controls_dialog then
        UIManager:close(self.controls_dialog)
        self.controls_dialog = nil
    end
end

--- Shows the read-along controls. The dialog is built again after each
--- button, so the title always shows the clock as it is now.
function SubRead:showControls()
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    self:closeControls()

    local function again(action)
        return function()
            action()
            self:showControls()
        end
    end

    self.controls_dialog = ButtonDialog:new{
        title = self:statusText(),
        title_align = "center",
        buttons = {
            {
                { text = _("Prev. cue"),
                  callback = again(function() self:skipCues(-1) end) },
                { text = _("-10 s"),
                  callback = again(function() self:seekAndShow(self.clock:getPosition(self:_now()) - 10) end) },
                { text = _("+10 s"),
                  callback = again(function() self:seekAndShow(self.clock:getPosition(self:_now()) + 10) end) },
                { text = _("Next cue"),
                  callback = again(function() self:skipCues(1) end) },
            },
            {
                { text = self.clock:isRunning() and _("Pause") or _("Start"),
                  callback = again(function() self:toggle() end) },
                { text = _("Stop"),
                  callback = function()
                      self:stop()
                      self:closeControls()
                  end },
            },
            {
                { text = _("Sync to this page"),
                  callback = again(function() self:syncToPage() end) },
                { text = _("Go to time…"),
                  callback = function()
                      self:closeControls()
                      self:showGoToTime()
                  end },
            },
            {
                { text = T(_("Speed: %1"), string.format("%.2f", self.clock.speed)),
                  callback = function()
                      self:closeControls()
                      self:showSpeed()
                  end },
                { text = T(_("Offset: %1 s"), string.format("%+d", self.clock.offset)),
                  callback = function()
                      self:closeControls()
                      self:showOffset()
                  end },
            },
            {
                { text = _("What time is this page?"),
                  callback = again(function() self:showPageTime() end) },
            },
        },
    }
    UIManager:show(self.controls_dialog)
end

function SubRead:showGoToTime()
    if not self:checkSupported() then return end
    if not self:loadSubtitles() then return end
    local position = self.clock:getPosition(self:_now())
    local hour = math.floor(position / 3600)
    local minute = math.floor(position / 60) % 60
    local second = math.floor(position) % 60
    UIManager:show(DateTimeWidget:new{
        title_text = _("Go to time"),
        info_text = _("Enter the position of the audio player."),
        hour = hour,
        hour_max = 99,
        min = minute,
        sec = second,
        ok_text = _("Go"),
        callback = function(widget)
            -- The widget writes the picked values back into itself before it
            -- calls us (datetimewidget.lua:396-406).
            self:seekAndShow(widget.hour * 3600 + widget.min * 60 + widget.sec)
            self:saveState()
        end,
    })
end

function SubRead:showSpeed()
    UIManager:show(SpinWidget:new{
        title_text = _("Player speed"),
        info_text = _("Set this to the speed of your audio player."),
        value = self.clock.speed,
        value_min = Clock.SPEED_MIN,
        value_max = Clock.SPEED_MAX,
        value_step = 0.05,
        value_hold_step = 0.25,
        precision = "%.2f",
        default_value = 1.0,
        callback = function(widget)
            self.clock:setSpeed(widget.value, self:_now())
            self:saveState()
            self:_tick()
        end,
    })
end

function SubRead:showOffset()
    UIManager:show(SpinWidget:new{
        title_text = _("Audio offset"),
        info_text = _("Seconds to add to the subtitle times. Use a positive value when the audio file starts with an intro."),
        value = self.clock.offset,
        value_min = -600,
        value_max = 600,
        value_step = 1,
        value_hold_step = 10,
        default_value = 0,
        unit = C_("Time", "s"),
        callback = function(widget)
            self.clock:setOffset(widget.value)
            self:saveState()
            self:_tick()
        end,
    })
end

--[[-- Events from a gesture or a key ]]--

function SubRead:onSubReadShowControls()
    self:showControls()
    return true
end

function SubRead:onSubReadToggle()
    if not self:checkSupported() then return true end
    if not self:loadSubtitles() then return true end
    self:toggle()
    self:showNotification(self.clock:isRunning() and _("Read-along running") or _("Read-along paused"))
    return true
end

function SubRead:onSubReadSyncToPage()
    self:syncToPage()
    return true
end

--[[-- Menu ]]--

function SubRead:subtitleMenuText()
    if not self.srt_path then
        return _("Subtitle file: none")
    end
    local _directory, file_name = util.splitFilePathName(self.srt_path)
    return T(_("Subtitle file: %1"), file_name)
end

function SubRead:addToMainMenu(menu_items)
    menu_items.subread = {
        -- The key is not in reader_menu_order.lua, so MenuSorter puts the
        -- entry where the hint says (menusorter.lua:161-182).
        sorting_hint = "tools",
        text = _("SubRead read-along"),
        sub_item_table = {
            {
                text_func = function() return self:subtitleMenuText() end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    if self:checkSupported() then
                        self:chooseSubtitleFile(touchmenu_instance)
                    end
                end,
                hold_callback = function(touchmenu_instance)
                    self:setSubtitleFile(nil)
                    touchmenu_instance:updateItems()
                end,
                separator = true,
            },
            {
                text_func = function()
                    return self.clock:isRunning() and _("Read-along controls")
                                                  or _("Start read-along")
                end,
                callback = function(touchmenu_instance)
                    touchmenu_instance:onClose()
                    if not self:checkSupported() then return end
                    if not self.clock:isRunning() then
                        self:start()
                        if not self.clock:isRunning() then return end
                    end
                    self:showControls()
                end,
            },
            {
                text = _("Go to time…"),
                keep_menu_open = true,
                callback = function() self:showGoToTime() end,
            },
            {
                text = _("What time is this page?"),
                keep_menu_open = true,
                callback = function() self:showPageTime() end,
                separator = true,
            },
            {
                text_func = function()
                    return T(_("Player speed: %1"), string.format("%.2f", self.clock.speed))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:showSpeed()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text_func = function()
                    return T(_("Audio offset: %1 s"), string.format("%+d", self.clock.offset))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:showOffset()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
        },
    }
end

return SubRead
