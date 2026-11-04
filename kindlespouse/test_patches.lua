require("setupkoenv")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
local Patches = require("patches")
local calls = 0
local base = { run = function(_, value) calls = calls + 1; return value, "second" end }
local target = setmetatable({}, { __index = base })
Patches.wrap("one", target, "run", function(original, self, value) return original(self, value+1) end)
local first, second = target:run(1)
assert(first == 2 and second == "second" and calls == 1)
assert(not pcall(Patches.wrap, "one", target, "run", function() end))
local wrapped = target.run
target.run = function(self, value) return wrapped(self, value) end
Patches.revert("one")
assert(target:run(4) == 4 and calls == 2)
Patches.wrap("two", target, "run", function(original, self, value) return original(self, value+2) end)
assert(target:run(4) == 6 and calls == 3)
Patches.revertAll()
assert(target:run(4) == 4 and calls == 4)
local inherited = setmetatable({}, { __index = base })
Patches.wrap("inherited", inherited, "run", function(original, self, ...) return original(self, ...) end)
Patches.revert("inherited")
assert(rawget(inherited, "run") == nil)
Patches.wrap("throws", target, "run", function(original, self) original(self, 1); error("fixture failure") end)
assert(not pcall(target.run, target) and calls == 5)
Patches.revertAll()
assert(not pcall(Patches.wrap, "missing", target, "absent", function() end))
for _ = 1, 1000 do
    Patches.wrap("reused", inherited, "run", function(original, self, ...) return original(self, ...) end)
    Patches.revert("reused")
end
assert(#Patches.order == 0)
print("KindleSpouse patches acceptance passed")
