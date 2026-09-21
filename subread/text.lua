--[[--
Text normalisation for SubRead.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

The cue text of a SubRead subtitle is a slice of the book text, but the
white space is not always the same. This module makes a canonical form of a
string, so cue text and book text can be compared.
--]]--

local Text = {}

-- Byte sequences of the space characters that UTF-8 books use.
-- Lua patterns do not know UTF-8, so the sequences are listed.
local UNICODE_SPACES = {
    "\194\160",      -- U+00A0 no-break space
    "\226\128\128",  -- U+2000 en quad
    "\226\128\129",  -- U+2001 em quad
    "\226\128\130",  -- U+2002 en space
    "\226\128\131",  -- U+2003 em space
    "\226\128\132",  -- U+2004 three-per-em space
    "\226\128\133",  -- U+2005 four-per-em space
    "\226\128\134",  -- U+2006 six-per-em space
    "\226\128\135",  -- U+2007 figure space
    "\226\128\136",  -- U+2008 punctuation space
    "\226\128\137",  -- U+2009 thin space
    "\226\128\138",  -- U+200A hair space
    "\226\128\139",  -- U+200B zero width space
    "\226\128\168",  -- U+2028 line separator
    "\226\128\169",  -- U+2029 paragraph separator
    "\227\128\128",  -- U+3000 ideographic space
    "\239\187\191",  -- U+FEFF byte order mark / zero width no-break space
}

-- Byte sequences that are removed, not replaced by a space.
local REMOVED = {
    "\194\173",      -- U+00AD soft hyphen
    "\226\128\140",  -- U+200C zero width non-joiner
    "\226\128\141",  -- U+200D zero width joiner
}

-- A cue that starts with this character has no place in the book.
Text.NO_PLACE_MARK = "\239\188\138" -- U+FF0A fullwidth asterisk

--- Removes a UTF-8 byte order mark from the start of a string.
function Text.stripBOM(s)
    if s:sub(1, 3) == "\239\187\191" then
        return s:sub(4)
    end
    return s
end

--- Makes the canonical form of a string.
-- All space characters become one ASCII space. The ends are trimmed.
function Text.normalize(s)
    if not s or s == "" then return "" end
    s = Text.stripBOM(s)
    for _, seq in ipairs(REMOVED) do
        s = s:gsub(seq, "")
    end
    for _, seq in ipairs(UNICODE_SPACES) do
        s = s:gsub(seq, " ")
    end
    s = s:gsub("%s+", " ")
    s = s:gsub("^ ", ""):gsub(" $", "")
    return s
end

--- Returns the byte offset of each UTF-8 character, plus the end offset.
-- offsets[i] is the first byte of character i. offsets[#offsets] is #s + 1.
-- The loop does not use a Lua pattern, because an embedded zero byte in a
-- pattern is not safe in Lua 5.1.
function Text.charOffsets(s)
    local offsets = {}
    local i, n = 1, #s
    while i <= n do
        offsets[#offsets + 1] = i
        local b = s:byte(i)
        local size = 1
        if b >= 0xF0 then size = 4
        elseif b >= 0xE0 then size = 3
        elseif b >= 0xC0 then size = 2
        end
        i = i + size
    end
    offsets[#offsets + 1] = n + 1
    return offsets
end

--- Counts the UTF-8 characters in a string.
function Text.len(s)
    return #Text.charOffsets(s) - 1
end

--- Returns characters first..last of a string. Both limits are inclusive.
function Text.sub(s, first, last)
    local offsets = Text.charOffsets(s)
    local count = #offsets - 1
    if first < 1 then first = 1 end
    if last > count then last = count end
    if first > last then return "" end
    return s:sub(offsets[first], offsets[last + 1] - 1)
end

--- True if the cue text has no place in the book.
function Text.hasNoPlace(s)
    local n = Text.normalize(s)
    return n == "" or n:sub(1, #Text.NO_PLACE_MARK) == Text.NO_PLACE_MARK
end

-- Lengths, in characters, of the search anchors.
-- A long anchor is more unique, but a small difference between the cue text
-- and the book text makes it fail. A short anchor almost always matches, and
-- the caller keeps the document order, so a wrong hit is improbable.
-- Two anchors only: each failed search reads the book to its end, so the
-- number of tries controls the worst case cost.
Text.ANCHOR_LENGTHS = { 24, 12 }
Text.ANCHOR_MIN_LENGTH = 6

--- Returns the search anchors for a cue text, longest first.
-- The result never holds the same string two times.
function Text.anchors(s, lengths)
    lengths = lengths or Text.ANCHOR_LENGTHS
    local norm = Text.normalize(s)
    if norm == "" then return {} end
    local count = Text.len(norm)
    if count < Text.ANCHOR_MIN_LENGTH then
        return { norm }
    end
    local out, seen = {}, {}
    for _, want in ipairs(lengths) do
        local take = want
        if take > count then take = count end
        if take >= Text.ANCHOR_MIN_LENGTH then
            local anchor = Text.sub(norm, 1, take)
            if not seen[anchor] then
                seen[anchor] = true
                out[#out + 1] = anchor
            end
        end
    end
    if #out == 0 then out[1] = norm end
    return out
end

--- Cuts a string to a maximum number of characters, for a dialog title.
function Text.ellipsize(s, max_chars)
    local norm = Text.normalize(s)
    if Text.len(norm) <= max_chars then return norm end
    return Text.sub(norm, 1, max_chars) .. "\226\128\166" -- U+2026 ellipsis
end

return Text
