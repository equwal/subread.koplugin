local Cues = require("subread.cues")
local Srt = require("subread.srt")

local function build(triples)
    local list = {}
    for _, t in ipairs(triples) do
        list[#list + 1] = {
            start = t[1], stop = t[2], text = t[3],
            norm = t[3], no_place = false,
        }
    end
    return Cues.new(list)
end

local SIMPLE = {
    { 0, 2, "alpha one" },
    { 2, 4, "beta two" },
    { 4, 6, "gamma three" },
    { 8, 10, "delta four" }, -- a gap from 6 to 8
}

describe("SubRead cues", function()
    it("counts the cues", function()
        assert.equals(4, build(SIMPLE):count())
        assert.equals(0, Cues.new({}):count())
    end)

    it("finds the last cue that started", function()
        local index = build(SIMPLE)
        assert.equals(0, index:lastStartedAt(-1))
        assert.equals(1, index:lastStartedAt(0))
        assert.equals(1, index:lastStartedAt(1.9))
        assert.equals(3, index:lastStartedAt(7))
        assert.equals(4, index:lastStartedAt(100))
    end)

    it("finds the cue that is on", function()
        local index = build(SIMPLE)
        assert.equals(1, index:findByTime(0))
        assert.equals(1, index:findByTime(1.99))
        assert.equals(2, index:findByTime(2))
        assert.equals(4, index:findByTime(9))
    end)

    it("returns nil in a gap and outside the file", function()
        local index = build(SIMPLE)
        assert.is_nil(index:findByTime(7))
        assert.is_nil(index:findByTime(-1))
        assert.is_nil(index:findByTime(11))
    end)

    it("agrees with a slow reference for every time", function()
        local index = build(SIMPLE)
        local function reference(t)
            local best
            for i, cue in ipairs(index.list) do
                if cue.start <= t and t < cue.stop then best = i end
            end
            return best
        end
        for step = -20, 240 do
            local t = step / 20
            assert.equals(reference(t), index:findByTime(t))
        end
    end)

    it("lets the latest overlapping cue win", function()
        local index = build({
            { 0, 100, "long background cue" },
            { 10, 12, "short cue on top" },
        })
        assert.equals(1, index:findByTime(5))
        assert.equals(2, index:findByTime(11))
        -- After the short cue ends the long one is still on.
        assert.equals(1, index:findByTime(20))
    end)

    it("finds the next cue start", function()
        local index = build(SIMPLE)
        assert.equals(1, index:nextAfter(-5))
        assert.equals(2, index:nextAfter(0))
        assert.equals(4, index:nextAfter(6))
        assert.is_nil(index:nextAfter(8))
    end)

    it("steps over cues that share a start time", function()
        local index = build({ { 0, 1, "a" }, { 5, 6, "b" }, { 5, 7, "c" }, { 9, 10, "d" } })
        assert.equals(4, index:nextAfter(5))
    end)

    it("finds the nearest cue for a start time", function()
        local index = build(SIMPLE)
        assert.equals(1, index:findNearest(-3))
        assert.equals(3, index:findNearest(6.5)) -- gap, nearer the cue before
        assert.equals(4, index:findNearest(7.9)) -- gap, nearer the cue after
        assert.equals(4, index:findNearest(50))
        assert.is_nil(Cues.new({}):findNearest(1))
    end)

    it("finds the cue that holds a piece of text", function()
        local index = build(SIMPLE)
        assert.equals(2, index:findIndexContaining("beta"))
        assert.is_nil(index:findIndexContaining("missing"))
        assert.is_nil(index:findIndexContaining(""))
    end)

    it("starts the text search at the given index", function()
        local index = build({ { 0, 1, "same words" }, { 1, 2, "same words" } })
        assert.equals(1, index:findIndexContaining("same"))
        assert.equals(2, index:findIndexContaining("same", 2))
    end)

    it("treats the needle as plain text, not a pattern", function()
        local index = build({ { 0, 1, "cost is 5 % of it" } })
        assert.equals(1, index:findIndexContaining("5 %"))
    end)

    it("finds the cue for a page of book text", function()
        local index = build(SIMPLE)
        -- Book text with other white space than the cue text.
        assert.equals(2, index:findIndexForText("beta\n   two and more words"))
        assert.is_nil(index:findIndexForText("nothing here at all matches"))
        assert.is_nil(index:findIndexForText(""))
    end)

    it("skips over page text that no cue holds", function()
        local index = build({ { 0, 1, "the real sentence of the book" } })
        -- The page starts with a running head that is not in any cue.
        local page = "CHAPTER ONE 12 the real sentence of the book"
        assert.equals(1, index:findIndexForText(page))
    end)

    it("builds from a parsed file", function()
        local data = "1\n00:00:00,000 --> 00:00:01,000\nhello there friend\n"
        local index = Cues.new(Srt.parse(data))
        assert.equals(1, index:count())
        assert.equals(1, index:findByTime(0.5))
        assert.equals("hello there friend", index:get(1).norm)
    end)
end)
