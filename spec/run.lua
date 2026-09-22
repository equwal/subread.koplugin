-- Fallback test runner for a plain Lua interpreter.
-- Run it from the plugin folder: lua spec/run.lua
-- It gives the small part of the busted API that the spec files use, so the
-- same files also run under busted.

local here = (arg and arg[0] or "spec/run.lua"):gsub("[^/\\]*$", "")
package.path = table.concat({ here .. "../?.lua", "./?.lua", package.path }, ";")

local failed, passed, path = 0, 0, {}

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function check(ok, message)
    if not ok then error(message or "assertion failed", 3) end
end

local A = { equals = function(a, b) check(a == b, tostring(a) .. " ~= " .. tostring(b)) end,
    same = function(a, b) check(deepEqual(a, b), "tables differ") end,
    is_nil = function(a) check(a == nil, "expected nil, got " .. tostring(a)) end,
    is_not_nil = function(a) check(a ~= nil, "expected a value, got nil") end,
    is_true = function(a) check(a == true, "expected true, got " .. tostring(a)) end,
    is_false = function(a) check(a == false, "expected false, got " .. tostring(a)) end,
    near = function(a, b, tol) check(math.abs(a - b) <= tol, tostring(a) .. " not near " .. tostring(b)) end }
A.are_equal = A.equals
_G.assert = setmetatable(A, { __call = function(_, ok, message) check(ok, message) return ok end })

function _G.describe(name, body) path[#path + 1] = name; body(); path[#path] = nil end
function _G.it(name, body)
    local title = table.concat(path, " / ") .. " / " .. name
    local ok, err = pcall(body)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. title .. ": " .. tostring(err)) end
end
_G.setup, _G.teardown, _G.before_each, _G.after_each = function(f) f() end, function() end, nil, nil

for _, name in ipairs({ "text", "srt", "cues", "clock", "player_state", "languages" }) do
    dofile(here .. name .. "_spec.lua")
end
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
