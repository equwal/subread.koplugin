--[[--
SubRip (.srt) parser for SubRead.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

The parser accepts:
  * a UTF-8 byte order mark,
  * CRLF, LF and CR line ends,
  * "," or "." between the seconds and the fraction,
  * a missing or wrong cue number,
  * cue text on more than one line.
Blocks without a time stamp line are skipped.
The result is sorted by start time.
--]]--

local Text = require("subread.text")

local Srt = {}

-- One time stamp: hours, minutes, seconds, fraction.
local STAMP = "(%d+):(%d+):(%d+)[,%.](%d+)"

--- Converts one time stamp to seconds.
-- The fraction keeps its own scale, so "5" means 0.5 s and "500" means 0.5 s.
local function stampToSeconds(h, m, s, frac)
    local value = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    local denominator = 10 ^ #frac
    return value + tonumber(frac) / denominator
end

--- Reads a "start --> stop" line.
-- @return start seconds, stop seconds, or nil when the line is not a time line
function Srt.parseTimeLine(line)
    local h1, m1, s1, f1, h2, m2, s2, f2 =
        line:match(STAMP .. "%s*%-%-+>%s*" .. STAMP)
    if not h1 then return nil end
    return stampToSeconds(h1, m1, s1, f1), stampToSeconds(h2, m2, s2, f2)
end

--- Splits text into lines. CRLF and CR both become a line end.
function Srt.splitLines(s)
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    local from = 1
    while true do
        local at = s:find("\n", from, true)
        if not at then
            lines[#lines + 1] = s:sub(from)
            break
        end
        lines[#lines + 1] = s:sub(from, at - 1)
        from = at + 1
    end
    return lines
end

--- Parses the content of a .srt file.
-- @string data the whole file
-- @return array of cues { start, stop, text, norm, no_place }, sorted by start
function Srt.parse(data)
    local cues = {}
    if not data or data == "" then return cues end
    local lines = Srt.splitLines(Text.stripBOM(data))

    local i, count = 1, #lines
    while i <= count do
        local start, stop = Srt.parseTimeLine(lines[i])
        if start then
            i = i + 1
            local parts = {}
            while i <= count and lines[i]:match("%S") do
                -- A new time line ends the cue as well: it means the file has
                -- no blank line between the blocks.
                if Srt.parseTimeLine(lines[i]) then break end
                parts[#parts + 1] = lines[i]
                i = i + 1
            end
            local text = table.concat(parts, "\n")
            local norm = Text.normalize(text)
            if norm ~= "" then
                cues[#cues + 1] = {
                    start = start,
                    stop = stop,
                    text = text,
                    norm = norm,
                    no_place = Text.hasNoPlace(norm),
                }
            end
        else
            i = i + 1
        end
    end

    -- A stable sort by start time. table.sort is not stable, so the original
    -- order is the second key.
    for index, cue in ipairs(cues) do
        cue.order = index
    end
    table.sort(cues, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.order < b.order
    end)
    for _, cue in ipairs(cues) do
        cue.order = nil
    end
    return cues
end

--- Reads and parses a .srt file.
-- @return array of cues, or nil plus an error message
function Srt.parseFile(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local data = file:read("*a")
    file:close()
    if not data then return nil, "empty file" end
    return Srt.parse(data)
end

return Srt
