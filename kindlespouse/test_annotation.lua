require("setupkoenv")
G_defaults = require("luadefaults"):open()
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;./frontend/?.lua;" .. package.path
package.loaded["apps/reader/readerui"] = {}
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local json = require("json")
G_reader_settings = require("luasettings"):open(root .. "/reader.lua")
local DocSettings = require("docsettings")
local Apply = require("annotation_apply")
local directory, mount = root .. "/sync/", root .. "/device"
util.makePath(directory .. "annotation-jobs")
util.makePath(mount .. "/Books")
local function write(filename, value)
    local stream = assert(io.open(filename, "wb"))
    assert(stream:write(value)); assert(stream:close())
end
local function id(number) return string.format("%08d-0000-4000-8000-%012d", number, number) end
local target = mount .. "/Books/Fixture.txt"
write(target, "Generated annotation fixture")
local function item(text, note, number)
    return { text = text, note = note, datetime = "2026-11-04", pos0 = "/p[" .. number .. "]", pos1 = "/p[" .. (number+1) .. "]", page = "/p[" .. number .. "]" }
end
local first, second = item("Edit quote", "Original", 1), item("Delete quote", "Remove", 3)
local settings = DocSettings:open(target)
settings:saveSetting("annotations", { first, second })
settings:saveSetting("annotations_rolling", { item("Edit quote", "Original", 1), item("Delete quote", "Remove", 3) })
assert(settings:flush(nil, true))
local source = "Books/Fixture.sdr/metadata.txt.lua"
local info = assert(lfs.attributes(target))
local function job(number, expected, operation)
    return { jobId = id(number), operation = operation or "edit", note = "Updated", expected = { text = expected.text, note = expected.note, datetime = expected.datetime, pos0 = expected.pos0, pos1 = expected.pos1 }, bookRelative = "Books/Fixture.txt", relative = source, bookSize = info.size, bookModified = info.modification }
end
local function queue(number, value) write(directory .. "annotation-jobs/" .. id(number) .. ".json", value) end
queue(1, "")
queue(2, "not JSON")
queue(3, json.encode({ expected = {} }))
local mismatch = job(4, first); mismatch.jobId = id(99); queue(4, json.encode(mismatch))
queue(10, json.encode(job(10, first)))
queue(11, json.encode(job(11, second, "delete")))
for _ = 1, 4 do
    local ok, error = pcall(Apply.run, directory, mount)
    assert(ok, "poison task blocked queue: " .. tostring(error))
end
for number = 1, 4 do
    local result = assert(io.open(directory .. "annotation-results/" .. id(number) .. ".json", "rb"))
    local value = json.decode(result:read("*a")); result:close()
    assert(value.status == "invalid")
    assert(lfs.attributes(directory .. "annotation-failed/" .. id(number) .. ".json"))
end
settings = DocSettings:open(target)
assert(#settings:readSetting("annotations") == 1)
assert(settings:readSetting("annotations")[1].note == "Updated")
assert(#settings:readSetting("annotations_rolling") == 1)
assert(settings:readSetting("annotations_rolling")[1].note == "Updated")
assert(Apply.apply(settings, job(10, first)) == "applied")
local duplicate = item("Ambiguous", "Same", 8)
settings:saveSetting("annotations", { duplicate, item("Ambiguous", "Same", 8) })
assert(Apply.apply(settings, job(12, duplicate)) == "conflict")
settings:saveSetting("annotations", { item("Old file", "Keep", 12) }); assert(settings:flush(nil, true))
local changed = job(13, item("Old file", "Keep", 12)); changed.bookSize = info.size + 1
queue(13, json.encode(changed)); Apply.run(directory, mount)
local stream = assert(io.open(directory .. "annotation-results/" .. id(13) .. ".json", "rb"))
assert(json.decode(stream:read("*a")).status == "conflict"); stream:close()
local changed_time = job(14, item("Old file", "Keep", 12)); changed_time.bookModified = info.modification + 1
queue(14, json.encode(changed_time)); Apply.run(directory, mount)
stream = assert(io.open(directory .. "annotation-results/" .. id(14) .. ".json", "rb"))
assert(json.decode(stream:read("*a")).status == "conflict"); stream:close()
settings = DocSettings:open(target)
local alternate = item("Alternate", "Keep", 15)
settings:saveSetting("annotations", { alternate })
settings:saveSetting("annotations_paging", { item("Alternate", "Keep", 15), item("Alternate", "Keep", 15) })
local status, skipped = Apply.apply(settings, job(15, alternate))
assert(status == "applied" and skipped == "skipped" and settings:readSetting("annotations_paging")[1].note == "Keep")
settings:saveSetting("annotations", { item("Retry", "Original", 20) }); assert(settings:flush(nil, true))
queue(20, json.encode(job(20, item("Retry", "Original", 20))))
local original_flush = DocSettings.flush
DocSettings.flush = function() return nil end
local consumed, retry = Apply.run(directory, mount)
DocSettings.flush = original_flush
assert(consumed == 0 and retry and lfs.attributes(directory .. "annotation-jobs/" .. id(20) .. ".json"))
Apply.run(directory, mount)
assert(not lfs.attributes(directory .. "annotation-jobs/" .. id(20) .. ".json"))
local Device = require("device")
require("document/canvascontext"):init(Device)
local Companion = dofile(project .. "/plugins/kindlespouse.koplugin/main.lua")
local host = setmetatable({}, { __index = Companion })
package.loaded.spouse_preset = nil
package.preload.spouse_preset = function() error("fixture missing preset") end
G_reader_settings:saveSetting("screensaver_type", "cover")
assert(host:setSleepCover(true) == false)
assert(G_reader_settings:readSetting("screensaver_type") == "cover")
G_reader_settings:saveSetting("kindlespouse_previous_screensaver", "cover")
G_reader_settings:saveSetting("screensaver_type", "customisable_ss")
host:setSleepCover(false)
assert(G_reader_settings:readSetting("screensaver_type") == "cover")
print("KindleSpouse annotation acceptance passed")
