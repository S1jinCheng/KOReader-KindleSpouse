require("setupkoenv")
G_defaults = require("luadefaults"):open()
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;./frontend/?.lua;" .. package.path
G_reader_settings = require("luasettings"):open(root .. "/reader.lua")
local util = require("util")
local json = require("json")
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup("en")
local UIManager = require("ui/uimanager")
local I18n = require("i18n")
local Status = require("sync_status")
local Menu = require("menu")
local clock = 1793779200
local directory = root .. "/sync/"
local warnings = {}
local log = { warn = function(...) warnings[#warnings + 1] = { ... } end }
util.makePath(directory)
util.makePath(root .. "/proc/123")
local function write(name, value)
    local stream = assert(io.open(directory .. name, "wb"))
    assert(stream:write(type(value) == "table" and json.encode(value) or value))
    assert(stream:close())
end
local function remove(name) os.remove(directory .. name) end
Status.configure { directory = directory, proc_directory = root .. "/proc", now = function() return clock end, logger = log }
G_reader_settings:saveSetting("language", "en")
assert(I18n.T("sync_now") == "Sync now")
assert(I18n.keys["搜索书名或作者"] == "search_title")
assert(I18n.keys["Sync now"] == "sync_now")
assert(I18n.T("sync_complete", 2, 3) == "Sync complete: 2 books received, 3 files backed up.")
assert(I18n.T("sync_elapsed", 1, 2) == " · 1m 02s")
assert(I18n.T("reader.progress", 2, 10, 20) == "2 / 10 · 20%")
assert(I18n.T("reader.remaining", "5m") == "5m left")
G_reader_settings:saveSetting("language", "zh_TW")
assert(I18n.T("sync_now") == "立即同步" and I18n.T("Library") == "书库")
assert(I18n.T("reader.highlight.purple") == "紫色")
assert(I18n.T("sync_complete", 2, 3):find("接收 2 本图书", 1, true))
assert(not pcall(I18n.T, "unknown_key"))
assert(Status.summary { state = "failed", error = "Generated external worker error" } == "同步已停止：Generated external worker error")
G_reader_settings:saveSetting("language", "en")
write("bad.json", "{")
assert(Status.readJSON("bad.json") == nil and Status.readJSON("bad.json") == nil and #warnings == 1)
write("large.json", string.rep(" ", 65537))
assert(Status.readJSON("large.json") == nil and Status.readJSON("large.json") == nil and #warnings == 2)
assert(Status.snapshot().state == "idle" and not Status.isRunning())
write("sync.launching", { schema = 1, owner = "generated-launch", mode = "books", startedAt = clock })
assert(Status.isRunning() and not Status.workerRunning())
local value = Status.snapshot()
assert(value.state == "running" and value.launching and value.booksOnly and not value.runId)
clock = clock + 20
assert(not Status.isRunning())
write("sync.launching", { startedAt = clock + 1 })
assert(not Status.isRunning())
write("sync.launching", tostring(clock))
assert(Status.isRunning())
remove("sync.launching")
write("sync.lock", "123\n")
local process = assert(io.open(root .. "/proc/123/cmdline", "wb"))
process:write("/generated/kindlespouse-sync\0fixture\0"); process:close()
assert(Status.workerRunning() and Status.isRunning())
write("progress.json", { state = "running", stage = "receiving_books", startedAt = clock - 10, booksOnly = true, done = 2, total = 4 })
write("books-pause.requested", "paused")
assert(Status.snapshot().state == "pausing")
remove("sync.lock")
assert(Status.snapshot().state == "paused")
remove("books-pause.requested")
assert(Status.snapshot().state == "failed")
local stamp = os.date("!%Y-%m-%dT%H:%M:%S", clock)
write("progress.json", { state = "completed", startedAt = clock - 5, completedAt = clock, received = 2, files = 3 })
write("last-result.json", { ok = true, completedAt = stamp .. ".000001Z", received = 2, files = 3 })
local first = Status.snapshot()
assert(first.runId == stamp .. ".000001Z" and first.completedAt == clock)
write("last-result.json", { ok = true, completedAt = stamp .. ".000002Z", received = 2, files = 3 })
local second = Status.snapshot()
assert(second.runId ~= first.runId and second.runId == stamp .. ".000002Z")
write("sync.launching", { schema = 1, owner = "next-generated-launch", mode = "full", startedAt = clock })
value = Status.snapshot()
assert(value.launching and value.state == "running" and not value.runId, "Old completion must not identify a newly launching run")
remove("sync.launching")
write("last-result.json", { ok = true, completedAt = os.date("!%Y-%m-%dT%H:%M:%S", clock - 1) .. ".999Z" })
assert(Status.snapshot().runId == nil, "Mismatched final timestamp must not supply invocation identity")
write("last-result.json", { ok = true, completedAt = stamp .. "not-a-timeZ" })
assert(Status.snapshot().runId == nil)
remove("progress.json")
write("last-result.json", { ok = true, booksOnly = true, completedAt = stamp .. ".123Z", received = 7 })
value = Status.snapshot()
assert(value.booksOnly and value.completedAt == clock and value.runId == stamp .. ".123Z")
assert(Status.summary(value) == "Books synced: 7 received.")
G_reader_settings:saveSetting("language", "zh_CN")
assert(Status.summary(value) == "图书同步完成，接收 7 本。")
assert(Status.summary { state = "running", stage = "receiving_books", startedAt = clock - 62, done = 1, total = 2 }:find("1 分 02 秒", 1, true))
G_reader_settings:saveSetting("language", "en")
local calls = {}
local host = { ui = {} }
for _, method in ipairs({ "sync", "pause", "refreshLibrary", "toggleHome", "setSleepCover", "syncProfile", "receiveBooks", "collectTitles", "syncTitles", "applyAnnotations", "openProfile" }) do
    host[method] = function(_, ...) calls[#calls + 1] = { method, ... } end
end
function host:autoSyncEnabled() return G_reader_settings:readSetting("kindlespouse_auto_sync", true) ~= false end
function host:setAutoSyncEnabled(enabled) G_reader_settings:saveSetting("kindlespouse_auto_sync", enabled) end
function host:setAutoReceiveEnabled(enabled) G_reader_settings:saveSetting("kindlespouse_auto_receive", enabled) end
function host:readerMenuItems() return { { text = "Generated reader option" } } end
function host:status() return Status.snapshot() end
function host:summary(progress) return Status.summary(progress) end
local function find(items, id)
    for _, item in ipairs(items) do if item.id == id then return item end end
end
local items = Menu.build(host).sub_item_table
assert(items[1].id == "sync" and items[2].id == "pause" and items[3].id == "status")
assert(not find(items, "last_result") and find(items, "reading_experience"))
assert(not items[2].enabled_func())
find(items, "sync").callback()
assert(calls[#calls][1] == "sync" and calls[#calls][2] == false)
write("pause.requested", "paused")
assert(find(items, "sync").text_func() == "Resume sync")
remove("pause.requested")
find(items, "auto_sync").callback()
assert(not find(items, "auto_sync").checked_func())
find(items, "auto_sync").callback()
assert(find(items, "auto_sync").checked_func())
find(items, "auto_receive").callback()
assert(not find(items, "auto_receive").checked_func())
find(items, "refresh").callback()
assert(calls[#calls][1] == "refreshLibrary")
host.ui.document = {}
assert(not find(items, "home").enabled_func() and not find(items, "refresh").enabled_func())
host.ui.document = nil
for _, item in ipairs(find(items, "advanced").sub_item_table) do item.callback() end
assert(calls[#calls][1] == "applyAnnotations")
local dialog = Menu.showStatus(host)
assert(dialog and host.status_dialog == dialog)
local session = host.kindlespouse_status_session
local function timers(action)
    local count = 0
    for _, task in ipairs(UIManager._task_queue) do if task.action == action then count = count + 1 end end
    return count
end
assert(timers(session.refresh) == 1)
write("last-result.json", { ok = true, booksOnly = true, completedAt = stamp .. ".124Z", received = 8 })
UIManager:unschedule(session.refresh)
session.refresh()
assert(host.status_dialog ~= dialog and host.kindlespouse_status_session == session and timers(session.refresh) == 1)
UIManager:widgetRepaint(host.status_dialog, 0, 0)
Menu.closeStatus(host)
assert(not host.status_dialog and not host.kindlespouse_status_session and timers(session.refresh) == 0)
Menu.showStatus(host)
session = host.kindlespouse_status_session
UIManager:close(host.status_dialog)
assert(not host.status_dialog and timers(session.refresh) == 0)
local successor = { ui = {}, status = host.status, summary = host.summary }
Menu.showStatus(host); Menu.showStatus(successor)
local current = successor.kindlespouse_status_session
Menu.closeStatus(host)
assert(successor.kindlespouse_status_session == current and timers(current.refresh) == 1)
successor.suspended = true
UIManager:unschedule(current.refresh); current.refresh()
assert(not successor.status_dialog and timers(current.refresh) == 0)
print("KindleSpouse services acceptance passed: localization, bounded JSON, worker and launch state, invocation IDs, menus, native dialog replacement and timer ownership")
