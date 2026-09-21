--[[--
State line of the audio player, as SubRead Overlay reports it.

Pure Lua. No KOReader dependency, so it can be unit tested on a PC.

SubRead Overlay is an Android app with notification access. It reads the
media session of the player and gives one line to other apps:

    playing=1;position=96153;speed=1.0;package=de.ph1b.audiobook

The position is in milliseconds, for the moment of the query. A problem is
one line `error=<reason>`.
--]]--

local PlayerState = {}

--- Parses a state line.
-- @return a table { playing, position (seconds), speed, package }, or nil
--   and an error name. A report without a position has position nil.
function PlayerState.parse(line)
    if type(line) ~= "string" or line == "" then return nil, "empty" end
    local fields = {}
    for key, value in line:gmatch("([%w_]+)=([^;]*)") do
        fields[key] = value
    end
    if fields.error then return nil, fields.error end
    if not fields.playing or not fields.position then return nil, "malformed" end
    local position_ms = tonumber(fields.position)
    if not position_ms then return nil, "malformed" end
    local speed = tonumber(fields.speed) or 1.0
    if speed <= 0 then speed = 1.0 end
    return {
        playing = fields.playing == "1",
        position = position_ms >= 0 and position_ms / 1000 or nil,
        speed = speed,
        package = fields.package,
    }
end

--- Converts a position in seconds to the milliseconds string of a seek call.
function PlayerState.seekArgument(seconds)
    if seconds < 0 then seconds = 0 end
    return string.format("%d", math.floor(seconds * 1000 + 0.5))
end

return PlayerState
