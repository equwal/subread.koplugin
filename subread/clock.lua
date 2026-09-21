--[[--
Play clock for SubRead.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

The caller gives the time. `now` is a monotonic time in seconds, from any
source. The clock keeps:
  * position: where the audio player is, in seconds,
  * speed:    how fast the player runs, 1.0 is normal,
  * offset:   how much later the narration is than the subtitle times.
             An audio file with a 20 s intro has offset 20.
The cue time is the position minus the offset.
--]]--

local Clock = {}
Clock.__index = Clock

Clock.SPEED_MIN = 0.5
Clock.SPEED_MAX = 3.0

--- Makes a new clock. It is paused.
function Clock.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Clock)
    self.position = opts.position or 0
    self.speed = opts.speed or 1.0
    self.offset = opts.offset or 0
    self.running = false
    self.started_at = nil
    return self
end

function Clock:isRunning()
    return self.running
end

--- Returns the player position, in seconds.
function Clock:getPosition(now)
    if not self.running then return self.position end
    return self.position + (now - self.started_at) * self.speed
end

--- Returns the time to look up in the cue index, in seconds.
function Clock:getCueTime(now)
    return self:getPosition(now) - self.offset
end

--- Starts the clock at the current position.
function Clock:start(now)
    if self.running then return end
    self.started_at = now
    self.running = true
end

--- Stops the clock and keeps the position.
function Clock:pause(now)
    if not self.running then return end
    self.position = self:getPosition(now)
    self.running = false
    self.started_at = nil
end

--- Starts or stops the clock. Returns the new state.
function Clock:toggle(now)
    if self.running then
        self:pause(now)
    else
        self:start(now)
    end
    return self.running
end

--- Moves the player position to an absolute value.
function Clock:seek(position, now)
    if position < 0 then position = 0 end
    self.position = position
    if self.running then self.started_at = now end
end

--- Moves the player position by a number of seconds.
function Clock:skip(delta, now)
    self:seek(self:getPosition(now) + delta, now)
end

--- Moves the player position to the given cue time.
function Clock:seekCueTime(cue_time, now)
    self:seek(cue_time + self.offset, now)
end

--- Sets the speed. The position is kept.
function Clock:setSpeed(speed, now)
    if speed < Clock.SPEED_MIN then speed = Clock.SPEED_MIN end
    if speed > Clock.SPEED_MAX then speed = Clock.SPEED_MAX end
    self.position = self:getPosition(now)
    if self.running then self.started_at = now end
    self.speed = speed
end

--- Sets the offset. The position is kept, so the cue time moves.
function Clock:setOffset(offset)
    self.offset = offset
end

--- Returns the real seconds until the clock reaches the given cue time.
-- Returns nil when the clock is paused or the time is already past.
function Clock:realSecondsUntilCueTime(cue_time, now)
    if not self.running then return nil end
    local delta = (cue_time + self.offset) - self:getPosition(now)
    if delta <= 0 then return nil end
    return delta / self.speed
end

return Clock
