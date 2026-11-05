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
local I18n = require("i18n")
local locale_failures = 0
local function override(target, key, value, body)
    local previous = target[key]
    target[key] = value
    local ok, failure = pcall(body)
    target[key] = previous
    assert(ok, failure)
end
for _, locale in ipairs({ "en", "zh_CN" }) do
    G_reader_settings = { readSetting = function() return locale end }
    local busy, paused_mode, occupied = false, false, false
    local status = {
        workerRunning = function() return busy end,
        launchMarker = function() return occupied end,
        readJSON = Status.readJSON,
        paused = function() return paused_mode end,
    }
    local execute = function() return 0 end
    Launcher.configure { directory = root, status = status, now = function() return clock end, logger = log,
        execute = function(command) return execute(command) end }
    for _, name in ipairs({ "pause.requested", "books-pause.requested", "profile-pause.requested", "titles-pause.requested" }) do os.remove(root .. name) end
    local function expect(key, action)
        local accepted, message = action()
        assert(not accepted and message == I18n.T(key), key .. ": " .. tostring(message))
        assert(not message:find("Generated", 1, true))
        locale_failures = locale_failures + 1
    end
    expect("launcher_mode", function() return Launcher.reserve("invalid") end)
    expect("launcher_mode", function() return Launcher.manual("invalid") end)
    expect("launcher_mode", function() return Launcher.launch("invalid") end)
    busy = true
    expect("launcher_running", function() return Launcher.reserve("books") end)
    busy, occupied = false, true
    expect("launcher_reserved", function() return Launcher.reserve("books") end)
    occupied = false
    override(io, "open", function() return nil, "Generated open failure" end, function()
        expect("launcher_reserve_failed", function() return Launcher.reserve("books") end)
        expect("pause_save_failed", Launcher.pause)
    end)
    for _, fail_write in ipairs({ true, false }) do
        override(io, "open", function()
            return {
                write = function() if fail_write then return nil, "Generated write failure" end; return true end,
                close = function() if not fail_write then return nil, "Generated close failure" end; return true end,
            }
        end, function()
            expect("launcher_save_failed", function() return Launcher.reserve("books") end)
            expect("pause_save_failed", Launcher.pause)
        end)
    end
    override(os, "rename", function() return nil, "Generated publish failure" end, function()
        expect("launcher_publish_failed", function() return Launcher.reserve("books") end)
    end)
    override(status, "readJSON", function() return { owner = "different" } end, function()
        expect("launcher_owner_changed", function() return Launcher.reserve("books") end)
    end)
    os.remove(root .. "sync.launching")
    write("books-pause.requested", "paused")
    override(os, "remove", function() return nil, "Generated resume failure" end, function()
        expect("launcher_resume_failed", function() return Launcher.manual("books") end)
    end)
    os.remove(root .. "books-pause.requested")
    expect("launcher_reservation_lost", function() return Launcher.launch("books", true, {}) end)
    local token = assert(Launcher.reserve("books"))
    clock = clock + 20
    expect("launcher_expired", function() return Launcher.launch("books", true, {}) end)
    clock = clock - 20
    busy = true
    expect("launcher_running", function() return Launcher.launch("books", true, {}) end)
    busy, paused_mode = false, true
    expect("launcher_paused", function() return Launcher.launch("books", true, {}) end)
    paused_mode = false
    local attributes = lfs.attributes
    override(lfs, "attributes", function(path, field)
        if path == root .. "config.json" then return nil end
        return attributes(path, field)
    end, function()
        expect("launcher_pair_first", function() return Launcher.launch("books", true, {}) end)
    end)
    execute = function() return 1 end
    expect("launcher_start_failed", function() return Launcher.launch("books", true, {}) end)
    execute = function() error("Generated execute failure") end
    expect("launcher_start_failed", function() return Launcher.launch("books", true, {}) end)
    execute = function() return 0 end
    Launcher.release(token)
    token = assert(Launcher.reserve("full"))
    expect("launcher_reading_failed", function() return Launcher.launch("full", true, {}) end)
    expect("launcher_reading_failed", function() return Launcher.launch("full", true, { saveReadingState = function() return false end }) end)
    expect("launcher_reading_failed", function() return Launcher.launch("full", true, { saveReadingState = function() error("Generated reading failure") end }) end)
    expect("launcher_owner_changed", function()
        return Launcher.launch("full", true, { saveReadingState = function() busy = true; return true end })
    end)
    busy = false
    expect("launcher_expired", function()
        return Launcher.launch("full", true, { saveReadingState = function() clock = clock + 20; return true end })
    end)
    Launcher.release(token)
end
local diagnostic_seen = false
for _, warning in ipairs(warnings) do
    assert(warning[1] == "KindleSpouse:")
    if tostring(warning[2]):find("Generated", 1, true) then diagnostic_seen = true end
end
assert(diagnostic_seen)
print("KindleSpouse localized launcher failures passed: " .. locale_failures .. " visible failures in both locales, prefixed raw diagnostics retained")
print("KindleSpouse launcher acceptance passed: whitelist, shell quoting, marker ownership, raw lock, pause scope, save failure, expiry, atomic publication")
