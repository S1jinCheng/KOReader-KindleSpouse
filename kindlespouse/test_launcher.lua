require("setupkoenv")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX")) .. "/sync's tools/"
local services = os.getenv("KINDLESPOUSE_TEST_SERVICES")
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. (services and services .. "/?.lua;" or "") .. package.path
local util = require("util")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local Status = require("sync_status")
local Launcher = require("launcher")
util.makePath(root .. "proc/4242")
local clock, calls, warnings = 10000, {}, {}
local function write(name, value)
    local stream = assert(io.open(root .. name, "wb"))
    assert(stream:write(value)); assert(stream:close())
end
local function exists(name) return lfs.attributes(root .. name, "mode") ~= nil end
write("config.json", "{}")
local log = { warn = function(...) warnings[#warnings + 1] = { ... } end }
Status.configure { directory = root, now = function() return clock end, proc_directory = root .. "proc/", logger = log }
Launcher.configure { directory = root, status = Status, now = function() return clock end, logger = log,
    execute = function(command) calls[#calls + 1] = command; return 0 end }
assert(Launcher.reserve("books; touch escaped") == nil)
assert(Launcher.launch("unknown", true, {}) == false)
assert(#calls == 0 and not exists("sync.launching"))
local first = assert(Launcher.reserve("books"))
assert(Status.isRunning() and not Status.workerRunning())
assert(Launcher.reserve("full") == nil)
Launcher.release({ owner = "different-owner" })
assert(exists("sync.launching"))
assert(Launcher.launch("books", false, {}))
assert(#calls == 1 and calls[1]:find("'\\''", 1, true))
assert(calls[1]:find(" 'books' < /dev/null > /dev/null 2>&1 &", 1, true))
Launcher.release(first)
assert(not exists("sync.launching"))
assert(Launcher.pause())
for _, name in ipairs({ "pause.requested", "books-pause.requested", "profile-pause.requested", "titles-pause.requested" }) do assert(exists(name)) end
assert(Launcher.manual("profile"))
assert(not exists("profile-pause.requested") and exists("pause.requested") and exists("books-pause.requested") and exists("titles-pause.requested"))
local paused = assert(Launcher.reserve("books"))
assert(Launcher.launch("books", false, {}) == false)
assert(Launcher.launch("books", true, {}) == false)
assert(exists("books-pause.requested"))
Launcher.release(paused)
assert(Launcher.manual("full"))
assert(not exists("pause.requested") and not exists("books-pause.requested") and exists("titles-pause.requested"))
local failure = assert(Launcher.reserve("full"))
assert(Launcher.launch("full", true, { saveReadingState = function() error("Generated save failure") end }) == false)
assert(#warnings > 0 and #calls == 1)
Launcher.release(failure)
local expired = assert(Launcher.reserve("books"))
clock = clock + 20
assert(Launcher.launch("books", false, {}) == false)
Launcher.release(expired)
local stale = { owner = "old", mode = "books", startedAt = clock - 21 }
write("sync.launching", json.encode(stale))
local replacement = assert(Launcher.reserve("books"))
Launcher.release(stale)
assert(Status.readJSON("sync.launching").owner == replacement.owner)
Launcher.release(replacement)
write("proc/4242/cmdline", "kindlespouse-sync\0--config\0generated")
write("sync.lock", "4242\n")
assert(Status.workerRunning())
assert(Launcher.reserve("books") == nil)
os.remove(root .. "sync.lock")
local preserved = os.rename
os.rename = function() return nil, "Generated rename failure" end
assert(Launcher.reserve("books") == nil)
os.rename = preserved
assert(not exists("sync.launching"))
for name in lfs.dir(root) do assert(not name:match("%.partial$")) end
print("KindleSpouse launcher acceptance passed: whitelist, shell quoting, marker ownership, raw lock, pause scope, save failure, expiry, atomic publication")
