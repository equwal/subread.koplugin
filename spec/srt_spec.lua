local Srt = require("subread.srt")

local SAMPLE = table.concat({
    "1",
    "00:00:01,000 --> 00:00:03,500",
    "It was the best of times,",
    "",
    "2",
    "00:00:03,500 --> 00:00:06,000",
    "it was the worst of times,",
    "it was the age of wisdom,",
    "",
    "3",
    "00:00:06,000 --> 00:00:08,000",
    "\239\188\138 chapter announcement",
    "",
}, "\n")

describe("SubRead srt", function()
    it("reads a time line with a comma", function()
        local start, stop = Srt.parseTimeLine("00:01:02,500 --> 00:01:04,250")
        assert.near(62.5, start, 1e-6)
        assert.near(64.25, stop, 1e-6)
    end)

    it("reads a time line with a full stop", function()
        local start, stop = Srt.parseTimeLine("01:00:00.000 --> 01:00:01.000")
        assert.near(3600, start, 1e-6)
        assert.near(3601, stop, 1e-6)
    end)

    it("scales the fraction by its length", function()
        local start = Srt.parseTimeLine("00:00:00,5 --> 00:00:01,0")
        assert.near(0.5, start, 1e-6)
    end)

    it("rejects a line that is not a time line", function()
        assert.is_nil(Srt.parseTimeLine("2"))
        assert.is_nil(Srt.parseTimeLine("some cue text"))
    end)

    it("splits CRLF, CR and LF the same way", function()
        assert.same({ "a", "b", "c" }, Srt.splitLines("a\r\nb\rc"))
    end)

    it("parses a whole file", function()
        local cues = Srt.parse(SAMPLE)
        assert.equals(3, #cues)
        assert.near(1.0, cues[1].start, 1e-6)
        assert.near(3.5, cues[1].stop, 1e-6)
        assert.equals("It was the best of times,", cues[1].text)
    end)

    it("joins the lines of a cue", function()
        local cues = Srt.parse(SAMPLE)
        assert.equals("it was the worst of times,\nit was the age of wisdom,",
            cues[2].text)
        assert.equals("it was the worst of times, it was the age of wisdom,",
            cues[2].norm)
    end)

    it("marks the cue that has no place in the book", function()
        local cues = Srt.parse(SAMPLE)
        assert.is_false(cues[1].no_place)
        assert.is_true(cues[3].no_place)
    end)

    it("accepts a byte order mark and CRLF", function()
        local data = "\239\187\191" .. SAMPLE:gsub("\n", "\r\n")
        assert.equals(3, #Srt.parse(data))
    end)

    it("skips a block that has no time line", function()
        local data = "header junk\n\n99\nnot a time\n\n" .. SAMPLE
        assert.equals(3, #Srt.parse(data))
    end)

    it("accepts a missing cue number", function()
        local data = "00:00:01,000 --> 00:00:02,000\nfirst\n\n" ..
                     "00:00:02,000 --> 00:00:03,000\nsecond\n"
        local cues = Srt.parse(data)
        assert.equals(2, #cues)
        assert.equals("second", cues[2].text)
    end)

    it("ends a cue on the next time line when a blank line is missing", function()
        local data = "00:00:01,000 --> 00:00:02,000\nfirst\n" ..
                     "00:00:02,000 --> 00:00:03,000\nsecond\n"
        local cues = Srt.parse(data)
        assert.equals(2, #cues)
        assert.equals("first", cues[1].text)
    end)

    it("drops a cue with no text", function()
        local data = "00:00:01,000 --> 00:00:02,000\n\n" ..
                     "00:00:02,000 --> 00:00:03,000\nkept\n"
        local cues = Srt.parse(data)
        assert.equals(1, #cues)
        assert.equals("kept", cues[1].text)
    end)

    it("sorts the cues by start time", function()
        local data = "00:00:09,000 --> 00:00:10,000\nlate\n\n" ..
                     "00:00:01,000 --> 00:00:02,000\nearly\n"
        local cues = Srt.parse(data)
        assert.equals("early", cues[1].text)
        assert.equals("late", cues[2].text)
    end)

    it("returns an empty list for empty input", function()
        assert.same({}, Srt.parse(""))
        assert.same({}, Srt.parse(nil))
    end)

    it("keeps the start times in order for any input", function()
        local blocks = {}
        local seed = 7
        for i = 1, 60 do
            seed = (seed * 1103515245 + 12345) % 2147483648
            local start = seed % 1000
            blocks[#blocks + 1] = string.format(
                "%d\n00:00:%02d,%03d --> 00:00:%02d,%03d\ncue %d\n",
                i, start % 60, start % 1000, (start + 2) % 60, start % 1000, i)
        end
        local cues = Srt.parse(table.concat(blocks, "\n"))
        assert.equals(60, #cues)
        for i = 2, #cues do
            assert.is_true(cues[i - 1].start <= cues[i].start)
        end
    end)
end)
