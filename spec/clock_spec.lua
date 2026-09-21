local Clock = require("subread.clock")

describe("SubRead clock", function()
    it("starts paused at zero", function()
        local c = Clock.new()
        assert.is_false(c:isRunning())
        assert.equals(0, c:getPosition(1000))
    end)

    it("does not move while paused", function()
        local c = Clock.new{ position = 30 }
        assert.equals(30, c:getPosition(1000))
        assert.equals(30, c:getPosition(9999))
    end)

    it("moves with real time when running", function()
        local c = Clock.new()
        c:start(100)
        assert.near(0, c:getPosition(100), 1e-9)
        assert.near(5, c:getPosition(105), 1e-9)
    end)

    it("keeps the position over a pause", function()
        local c = Clock.new()
        c:start(100)
        c:pause(110)
        assert.near(10, c:getPosition(500), 1e-9)
        c:start(500)
        assert.near(12, c:getPosition(502), 1e-9)
    end)

    it("applies the speed", function()
        local c = Clock.new{ speed = 2.0 }
        c:start(0)
        assert.near(20, c:getPosition(10), 1e-9)
    end)

    it("keeps the position when the speed changes", function()
        local c = Clock.new()
        c:start(0)
        c:setSpeed(3.0, 10)
        assert.near(10, c:getPosition(10), 1e-9)
        assert.near(40, c:getPosition(20), 1e-9)
    end)

    it("holds the speed inside its limits", function()
        local c = Clock.new()
        c:setSpeed(0.1, 0)
        assert.equals(Clock.SPEED_MIN, c.speed)
        c:setSpeed(99, 0)
        assert.equals(Clock.SPEED_MAX, c.speed)
    end)

    it("takes the offset off the cue time", function()
        local c = Clock.new{ position = 100, offset = 20 }
        assert.equals(100, c:getPosition(0))
        assert.equals(80, c:getCueTime(0))
        c:setOffset(-5)
        assert.equals(105, c:getCueTime(0))
    end)

    it("seeks to an absolute position", function()
        local c = Clock.new()
        c:start(0)
        c:seek(60, 10)
        assert.near(60, c:getPosition(10), 1e-9)
        assert.near(65, c:getPosition(15), 1e-9)
        assert.is_true(c:isRunning())
    end)

    it("never seeks before zero", function()
        local c = Clock.new{ position = 5 }
        c:seek(-10, 0)
        assert.equals(0, c.position)
    end)

    it("skips forward and back", function()
        local c = Clock.new{ position = 100 }
        c:skip(10, 0)
        assert.equals(110, c:getPosition(0))
        c:skip(-10, 0)
        assert.equals(100, c:getPosition(0))
    end)

    it("seeks by cue time through the offset", function()
        local c = Clock.new{ offset = 20 }
        c:seekCueTime(50, 0)
        assert.equals(70, c:getPosition(0))
        assert.equals(50, c:getCueTime(0))
    end)

    it("toggles between running and paused", function()
        local c = Clock.new()
        assert.is_true(c:toggle(0))
        assert.is_false(c:toggle(5))
        assert.equals(5, c:getPosition(100))
    end)

    it("tells how long until a cue time", function()
        local c = Clock.new{ speed = 2.0, offset = 10 }
        c:start(0)
        -- Cue time 30 is player position 40, which comes after 20 real seconds.
        assert.near(20, c:realSecondsUntilCueTime(30, 0), 1e-9)
        -- Cue time -20 is player position -10, which is already past.
        assert.is_nil(c:realSecondsUntilCueTime(-20, 0))
    end)

    it("gives no wait time while paused", function()
        local c = Clock.new()
        assert.is_nil(c:realSecondsUntilCueTime(100, 0))
    end)

    it("keeps position and cue time in step over any sequence", function()
        local c = Clock.new{ speed = 1.5, offset = 3 }
        local now = 0
        c:start(now)
        for step = 1, 40 do
            now = now + 0.25
            if step % 7 == 0 then c:toggle(now) end
            if step % 11 == 0 then c:skip(-10, now) end
            if step % 13 == 0 then c:setSpeed(0.5 + (step % 5) / 2, now) end
            assert.near(c:getPosition(now) - c.offset, c:getCueTime(now), 1e-9)
            assert.is_true(c:getPosition(now) >= 0)
        end
    end)
end)
