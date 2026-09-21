--[[--
Cue index for SubRead.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

The index holds the cues in start order and answers three questions:
  * which cue is on at time t,
  * which cue starts next after time t,
  * which cue holds a piece of text.
--]]--

local Text = require("subread.text")

local Cues = {}
Cues.__index = Cues

--- Builds an index from a cue array. The array must be sorted by start time.
function Cues.new(list)
    local self = setmetatable({}, Cues)
    self.list = list or {}
    self.max_duration = 0
    for _, cue in ipairs(self.list) do
        local duration = cue.stop - cue.start
        if duration > self.max_duration then
            self.max_duration = duration
        end
    end
    return self
end

function Cues:count()
    return #self.list
end

function Cues:get(index)
    return self.list[index]
end

--- Returns the index of the last cue that starts at or before t.
-- Returns 0 when every cue starts after t.
function Cues:lastStartedAt(t)
    local low, high, answer = 1, #self.list, 0
    while low <= high do
        local mid = math.floor((low + high) / 2)
        if self.list[mid].start <= t then
            answer = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end
    return answer
end

--- Returns the index of the cue that is on at time t, or nil.
-- Cues can overlap. The latest cue that is still on wins.
-- The walk back stops after the longest cue in the file, so the cost is bound.
function Cues:findByTime(t)
    local index = self:lastStartedAt(t)
    while index >= 1 do
        local cue = self.list[index]
        if t - cue.start > self.max_duration then break end
        if cue.stop > t then return index end
        index = index - 1
    end
    return nil
end

--- Returns the index of the first cue that starts after t, or nil.
function Cues:nextAfter(t)
    local index = self:lastStartedAt(t) + 1
    -- Cues with the same start time can follow the one that lastStartedAt
    -- found, so step over every cue that does not start after t.
    while self.list[index] and self.list[index].start <= t do
        index = index + 1
    end
    if self.list[index] then return index end
    return nil
end

--- Returns the index of the cue that is on at t, or of the nearest cue.
-- Use it to choose a start time. Returns nil for an empty index.
function Cues:findNearest(t)
    if #self.list == 0 then return nil end
    local on = self:findByTime(t)
    if on then return on end
    local before = self:lastStartedAt(t)
    local after = before + 1
    if before < 1 then return 1 end
    if not self.list[after] then return before end
    local gap_before = t - self.list[before].stop
    local gap_after = self.list[after].start - t
    if gap_after < gap_before then return after end
    return before
end

--- Returns the index of the first cue whose text holds the needle, or nil.
-- The needle must already be normalised. The search is a plain substring
-- search, not a pattern match.
-- @int from optional first index to look at (default 1)
function Cues:findIndexContaining(needle, from)
    if not needle or needle == "" then return nil end
    for index = from or 1, #self.list do
        if self.list[index].norm:find(needle, 1, true) then
            return index
        end
    end
    return nil
end

-- Lengths, in characters, of the needles cut out of a page of the book.
-- The long needle comes first, because a long match is more sure. The short
-- needle is the fallback for a cue that is shorter than the long needle.
Cues.NEEDLE_LENGTHS = { 12, 6 }
-- Number of needles tried for each length. A needle can fail because the book
-- text holds ruby text or a running head that the cue text does not hold.
Cues.NEEDLE_TRIES = 8
-- Distance, in characters, between two needles.
Cues.NEEDLE_STEP = 8

--- Returns the index of the first cue that holds a piece of the given text.
-- Use it to answer "which cue does this page start with?".
-- @string haystack book text, not yet normalised
function Cues:findIndexForText(haystack)
    local norm = Text.normalize(haystack)
    local count = Text.len(norm)
    if count == 0 then return nil end
    for _, length in ipairs(Cues.NEEDLE_LENGTHS) do
        for try = 0, Cues.NEEDLE_TRIES - 1 do
            local first = 1 + try * Cues.NEEDLE_STEP
            if first > count then break end
            local last = first + length - 1
            if last > count then last = count end
            if last - first + 1 >= length then
                local index = self:findIndexContaining(Text.sub(norm, first, last))
                if index then return index end
            end
        end
    end
    return nil
end

return Cues
