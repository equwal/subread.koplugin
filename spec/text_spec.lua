local Text = require("subread.text")

describe("SubRead text", function()
    it("removes a byte order mark", function()
        assert.equals("abc", Text.stripBOM("\239\187\191abc"))
        assert.equals("abc", Text.stripBOM("abc"))
    end)

    it("collapses every kind of space", function()
        assert.equals("a b", Text.normalize("a \t\n b"))
        assert.equals("a b", Text.normalize("a\194\160b"))         -- no-break space
        assert.equals("a b", Text.normalize("a\227\128\128b"))     -- ideographic space
        assert.equals("ab", Text.normalize("a\194\173b"))          -- soft hyphen removed
    end)

    it("trims the ends", function()
        assert.equals("hello", Text.normalize("   hello \r\n"))
        assert.equals("", Text.normalize("   "))
        assert.equals("", Text.normalize(nil))
    end)

    it("counts UTF-8 characters", function()
        assert.equals(3, Text.len("abc"))
        assert.equals(3, Text.len("\230\188\162\229\173\151a")) -- 漢字a
        assert.equals(0, Text.len(""))
    end)

    it("cuts on character boundaries", function()
        local s = "\230\188\162\229\173\151a" -- 漢字a
        assert.equals("\230\188\162", Text.sub(s, 1, 1))
        assert.equals("\229\173\151a", Text.sub(s, 2, 3))
        assert.equals(s, Text.sub(s, 1, 99))
        assert.equals("", Text.sub(s, 4, 9))
    end)

    it("keeps sub and len consistent for every prefix", function()
        local s = "a\230\188\162b\227\129\130c" -- a漢bあc
        for i = 1, Text.len(s) do
            assert.equals(i, Text.len(Text.sub(s, 1, i)))
        end
    end)

    it("marks a cue that has no place in the book", function()
        assert.is_true(Text.hasNoPlace("\239\188\138 narrator note"))
        assert.is_true(Text.hasNoPlace("  "))
        assert.is_false(Text.hasNoPlace("real book text"))
    end)

    it("makes anchors, longest first, without repeats", function()
        local long = string.rep("x", 40)
        local anchors = Text.anchors(long)
        assert.equals(2, #anchors)
        assert.equals(24, Text.len(anchors[1]))
        assert.equals(12, Text.len(anchors[2]))
    end)

    it("gives one anchor for a short cue", function()
        assert.same({ "yes" }, Text.anchors("yes"))
        assert.same({ "eight ch" }, Text.anchors("  eight   ch "))
    end)

    it("makes anchors that are prefixes of the normalised cue", function()
        local cue = "The quick brown fox jumps over the lazy dog"
        local norm = Text.normalize(cue)
        for _, anchor in ipairs(Text.anchors(cue)) do
            assert.equals(anchor, Text.sub(norm, 1, Text.len(anchor)))
        end
    end)

    it("ellipsizes long text only", function()
        assert.equals("short", Text.ellipsize("short", 10))
        assert.equals("abcde\226\128\166", Text.ellipsize("abcdefgh", 5))
    end)
end)
