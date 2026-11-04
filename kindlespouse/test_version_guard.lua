require("setupkoenv")
G_defaults = require("luadefaults"):open()
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;./frontend/?.lua;" .. package.path
G_reader_settings = require("luasettings"):open(root .. "/settings.reader.lua")
local Version = require("version")
local Patches = require("patches")
local logger = require("logger")
local UIManager = require("ui/uimanager")
local original_warn = logger.warn
local warnings = {}
logger.warn = function(prefix, message)
    assert(prefix == "KindleSpouse:")
    warnings[#warnings + 1] = message
    original_warn(prefix, message)
end
local original_revision, original_version, original_commit = Version.rev, Version.version, Version.commit
local original_get_revision = Version.getCurrentRevision
local actual = Version:getNormalizedCurrentVersion()
assert(actual == 202607010000, "Test runtime must be the pinned v2026.07.1 AppImage")
local function revision(value)
    Version.rev, Version.version, Version.commit = value, nil, nil
end
local function guard()
    package.loaded.version_guard = nil
    return require("version_guard")
end
local function wrap(original, self, value) return original(self, value + 1) end
local calls = 0
local target = { run = function(_, value) calls = calls + 1; return value, "upstream" end }
local base = target.run
local foreign = { run = function(_, value) return value * 2 end }
Patches.wrap("other-plugin:keep", foreign, "run", wrap)
local foreign_wrapper = foreign.run
local Guard = guard()
assert(#Patches.order == 1, "Requiring the guard must not install UI patches")
assert(Guard.isSupported() and Guard.status().version == actual)
G_reader_settings:saveSetting("kindlespouse_auto_sync", true)
local ok, first, second = Guard.run(function()
    Patches.wrap("home:fixture", target, "run", wrap)
    return 7, "preserved"
end)
assert(ok and first == 7 and second == "preserved")
assert(target:run(2) == 3 and calls == 1 and #warnings == 0)
Patches.revert("home:fixture")
local result_count = select("#", Guard.run(function() return nil, "tail", nil end))
assert(result_count == 4)
local ui = {}
assert(Guard.install(ui, function(received) assert(received == ui) end))
revision("v2026.07.1-1-gabcdef")
assert(Version:getNormalizedCurrentVersion() == 202607010001)
local unsupported = guard()
local entered, sync_calls = false, 0
local success, failure = unsupported.run(function() entered = true end)
assert(not success and failure:find("unsupported", 1, true) and not entered)
local function synchronize() sync_calls = sync_calls + 1 end
synchronize()
assert(sync_calls == 1 and foreign.run == foreign_wrapper and foreign:run(2) == 6)
assert(#warnings == 1 and unsupported.status().disabled)
local scheduled = #UIManager._task_queue
Patches.wrap("home:late-auto-loaded", target, "run", wrap)
assert(not unsupported.run(function() entered = true end))
assert(#warnings == 1 and not entered and #UIManager._task_queue == scheduled)
assert(not Patches.applied["home:late-auto-loaded"])
revision("v2026.07.1")
assert(not unsupported.run(function() entered = true end), "A failed session must not silently re-enable UI")
local missing = guard()
local count_before = calls
success = missing.run(function()
    Patches.wrap("home:partial", target, "run", wrap)
    target:run(3)
    Patches.wrap("reader:missing", target, "absent", wrap)
end)
assert(not success and target.run == base and calls == count_before + 1)
assert(not Patches.applied["home:partial"] and #warnings == 2)
assert(foreign.run == foreign_wrapper and foreign:run(2) == 6)
local throwing = guard()
Patches.wrap("home:previous", target, "run", wrap)
local own = target.run
local external = function(self, value) return own(self, value) * 10 end
target.run = external
success = throwing.run(function()
    Patches.wrap("reader:partial", target, "run", wrap)
    error("Synthetic installer failure")
end)
assert(not success and target.run == external and target:run(4) == 40)
assert(not Patches.applied["home:previous"] and not Patches.applied["reader:partial"])
assert(#warnings == 3 and not throwing.run(function() error("Must not execute again") end) and #warnings == 3)
revision("v2026.07.2")
assert(Version:getNormalizedCurrentVersion() == 202607020000)
local late = guard()
Patches.wrap("home:auto-loaded", target, "run", wrap)
package.preload.kindlespouse_guard_auto_patch_fixture = function()
    entered = true
    Patches.wrap("menu:auto-loaded", target, "run", wrap)
    return {}
end
assert(not late.run(function() require("kindlespouse_guard_auto_patch_fixture") end))
assert(not entered and not package.loaded.kindlespouse_guard_auto_patch_fixture)
assert(not Patches.applied["home:auto-loaded"] and #Patches.order == 1)
assert(target.run == external and target:run(4) == 40)
assert(foreign.run == foreign_wrapper)
revision(nil)
Version.getCurrentRevision = function() return nil end
local unknown = guard()
assert(not unknown.run(function() entered = true end) and not entered)
assert(#warnings == 5)
local normalized_api = Version.getNormalizedCurrentVersion
Version.getNormalizedCurrentVersion = nil
local missing_api = guard()
assert(not missing_api.run(function() entered = true end) and not entered)
assert(#warnings == 6)
Version.getNormalizedCurrentVersion = normalized_api
assert(not G_reader_settings:has("plugins_disabled"))
assert(G_reader_settings:isTrue("kindlespouse_auto_sync"))
Patches.revert("other-plugin:keep")
assert(#Patches.order == 0)
Version.rev, Version.version, Version.commit = original_revision, original_version, original_commit
Version.getCurrentRevision = original_get_revision
logger.warn = original_warn
print("KindleSpouse version guard acceptance passed: real normalized version, exact support, UI-only rollback, once-only warning, sync continuation and require safety")