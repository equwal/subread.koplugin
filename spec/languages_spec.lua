-- The languages SubRead is checked against: English, Portuguese, Spanish,
-- Russian and Japanese. The cue text of each has to survive the pure Lua
-- modules unchanged: the search in the book uses it byte for byte.

local Text = require("subread.text")
local Srt = require("subread.srt")
local Cues = require("subread.cues")

-- One line of a book in each language, with the marks that its books use.
local LINES = {
    en = "It was a dark night; the rain fell on the yellow wallpaper.",
    pt = "— Não me parece bonito — disse ela, à porta do coração.",
    es = "¿Qué es esto? ¡Ñandú, señor Quijote, en la defensa de la dueña!",
    ru = "«Ёлка, — сказал он, — и её огни горят в ожидании заказа».",
    ja = "「女のいない男たち」東京で暮らしている。吾輩は猫である。",
}
-- Characters in each line, counted by hand.
local CHARS = { en = 59, pt = 55, es = 63, ru = 57, ja = 28 }
local ORDER = { "en", "pt", "es", "ru", "ja" }

local function srtOf()
    local blocks = {}
    for i, code in ipairs(ORDER) do
        blocks[#blocks + 1] = string.format("%d\n00:00:%02d,000 --> 00:00:%02d,900\n%s\n",
            i, i, i, LINES[code])
    end
    return table.concat(blocks, "\n")
end

describe("SubRead languages", function()
    it("counts the characters of each script", function()
        for code, line in pairs(LINES) do
            assert.equals(CHARS[code], Text.len(line))
        end
    end)

    it("keeps a normalised line byte for byte", function()
        for _, line in pairs(LINES) do
            assert.equals(line, Text.normalize(line))
            assert.equals(line, Text.sub(line, 1, Text.len(line)))
        end
    end)

    it("turns the ideographic space of Japanese into one space", function()
        assert.equals("a b", Text.normalize("a\227\128\128b"))
        assert.equals("「女のいない男たち」 東京", Text.normalize("「女のいない男たち」　東京"))
    end)

    it("cuts anchors and tails on character boundaries in each script", function()
        for code, line in pairs(LINES) do
            local anchors = Text.anchors(line)
            assert.equals(2, #anchors, code)
            assert.equals(24, Text.len(anchors[1]), code)
            assert.equals(12, Text.len(anchors[2]), code)
            assert.equals(anchors[1], Text.sub(line, 1, 24), code)
            local tail = Text.tail(line)
            assert.equals(12, Text.len(tail), code)
            assert.equals(tail, Text.sub(line, Text.len(line) - 11, Text.len(line)), code)
        end
    end)

    it("reads a subtitle file that mixes the scripts", function()
        local cues = Srt.parse(srtOf())
        assert.equals(#ORDER, #cues)
        for i, code in ipairs(ORDER) do
            assert.equals(LINES[code], cues[i].text)
            assert.equals(LINES[code], cues[i].norm)
            assert.is_false(cues[i].no_place)
            assert.near(i, cues[i].start, 1e-6)
        end
    end)

    it("finds the cue of a page in each script", function()
        local index = Cues.new(Srt.parse(srtOf()))
        for i, code in ipairs(ORDER) do
            -- The page starts a few characters into the line, as a page often does.
            local page = Text.sub(LINES[code], 3, Text.len(LINES[code])) .. " and more text of the page"
            assert.equals(i, index:findIndexForText(page), code)
            -- A selection of a few words in the middle of the line.
            local selected = Text.sub(LINES[code], 8, 19)
            assert.equals(i, index:findIndexContaining(Text.normalize(selected)), code)
        end
    end)

    it("ellipsizes on a character boundary", function()
        for _, line in pairs(LINES) do
            local short = Text.ellipsize(line, 10)
            assert.equals(11, Text.len(short))
            assert.equals(Text.sub(line, 1, 10), Text.sub(short, 1, 10))
        end
    end)
end)
