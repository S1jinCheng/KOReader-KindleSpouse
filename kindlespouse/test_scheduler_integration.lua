require("setupkoenv")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX")) .. "/companion/"
local services = os.getenv("KINDLESPOUSE_TEST_SERVICES")
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. (services and services .. "/?.lua;" or "") .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(root .. "settings.reader.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local util = require("util")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
util.makePath(root .. "proc/4242")
local tasks, sequence, clock = {}, 0, os.time()
local base = clock
local real_time, real_execute = os.time, os.execute
os.time = function() return clock end
local function write(name, value)
    local stream = assert(io.open(root .. name, "wb"))
    assert(stream:write(value)); assert(stream:close())
end
local function data(name, value) write(name, json.encode(value)) end
local function exists(name) return lfs.attributes(root .. name, "mode") ~= nil end
UIManager.scheduleIn = function(_, delay, action)
    sequence = sequence + 1
    tasks[#tasks + 1] = { due = clock + delay, action = action, sequence = sequence }
end
UIManager.unschedule = function(_, action)
    for index = #tasks, 1, -1 do if tasks[index].action == action then table.remove(tasks, index) end end
end
local function advance(seconds)
    local ending, count = clock + seconds, 0
    while true do
        local selected
        for index, task in ipairs(tasks) do
            if task.due <= ending and (not selected or task.due < tasks[selected].due or task.due == tasks[selected].due and task.sequence < tasks[selected].sequence) then selected = index end
        end
        if not selected then break end
        local task = table.remove(tasks, selected)
        clock = math.max(clock, task.due)
        task.action()
        count = count + 1
        assert(count < 1000, "Integration timer loop")
    end
    clock = ending
end
local connected = true
NetworkMgr.isConnected = function() return connected end
local homes = 0
package.loaded.home = { install = function() end, uninstall = function() homes = homes + 1 end }
local saved, applied, notices, launches = 0, 0, {}, {}
local reader = { document = {}, saveSettings = function() saved = saved + 1 end }
package.loaded["apps/reader/readerui"] = { instance = reader }
local start_delay, finish_delay = 0, 2
os.execute = function(command)
    local mode = command:match(" '(%w+)' <") or "full"
    launches[#launches + 1] = { mode = mode, command = command, time = clock }
    local started, id = clock, #launches
    local function begin()
        write("proc/4242/cmdline", "kindlespouse-sync\0--config\0generated")
        write("sync.lock", "4242\n")
        data("progress.json", { state = "running", mode = mode, startedAt = started, updatedAt = clock })
        UIManager:scheduleIn(finish_delay, function()
            os.remove(root .. "sync.lock")
            data("progress.json", { state = "completed", mode = mode, startedAt = started, updatedAt = clock, completedAt = clock })
            data("last-result.json", { ok = true, mode = mode, completedAt = os.date("!%Y-%m-%dT%H:%M:%S", clock) .. string.format(".%09dZ", id) })
        end)
    end
    if start_delay == 0 then begin() else UIManager:scheduleIn(start_delay, begin) end
    return 0
end
data("config.json", { version = 1, deviceId = "generated" })
G_reader_settings:saveSetting("kindlespouse_last_sync", clock)
G_reader_settings:saveSetting("kindlespouse_sync_generation", 0)
local Companion = dofile(project .. "/plugins/kindlespouse.koplugin/main.lua")
Companion.directory = root
local function host(document)
    local value = setmetatable({ directory = root, ui = { document = document, menu = { registerToMainMenu = function() end } } }, { __index = Companion })
    value.notify = function(_, message) notices[#notices + 1] = message end
    value.applySleepProfile = function() end
    value.applyAnnotations = function() applied = applied + 1 end
    value:init()
    return value
end
local old = host(nil)
local Status = require("sync_status")
local Scheduler = require("scheduler")
Status.configure { directory = root, proc_directory = root .. "proc/", now = os.time }
for index = 1, 5 do old:onAnnotationsModified(); advance(1) end
local current = host({})
old:onCloseWidget()
assert(homes == 1)
advance(20)
assert(#launches == 1 and launches[1].mode == "full" and saved == 1)
assert(G_reader_settings:readSetting("kindlespouse_sync_dirty") == false)
assert(Scheduler.snapshot().result.state == "completed")
assert(rawget(current, "launch_pending") == nil and rawget(current, "watch_task") == nil and rawget(current, "auto_receive_task") == nil)
assert(current:pause())
assert(current:syncProfile())
assert(not exists("profile-pause.requested") and exists("pause.requested") and exists("books-pause.requested") and exists("titles-pause.requested"))
advance(8)
assert(#launches == 2 and launches[2].mode == "profile")
assert(current:receiveBooks(true) == false and exists("books-pause.requested"))
assert(current:sync(false))
assert(not exists("pause.requested") and not exists("books-pause.requested") and exists("titles-pause.requested"))
advance(8)
assert(#launches == 3 and launches[3].mode == "full")
current:onPageUpdate(1)
start_delay = 3
assert(current:receiveBooks(false))
advance(1)
assert(Scheduler.snapshot().launch_pending and not Scheduler.snapshot().running)
assert(G_reader_settings:readSetting("kindlespouse_reading_dirty") == true)
advance(9)
assert(#launches == 4 and Scheduler.snapshot().result.state == "completed")
assert(G_reader_settings:readSetting("kindlespouse_reading_dirty") == true)
start_delay, finish_delay = 0, 0
assert(current:sync(false))
advance(1)
assert(#launches == 5 and Scheduler.snapshot().result.state == "completed")
assert(G_reader_settings:readSetting("kindlespouse_reading_dirty") == false)
connected = false
current:onNetworkDisconnected()
current:onAnnotationsModified()
advance(30)
assert(#launches == 5)
connected = true
current:onNetworkConnected()
advance(7)
assert(#launches == 5)
advance(10)
assert(#launches == 6 and launches[6].mode == "full")
current:onPageUpdate(2)
local reading_deadline = G_reader_settings:readSetting("kindlespouse_last_sync") + 600
advance(reading_deadline - clock - 1)
assert(#launches == 6)
advance(1)
assert(#launches == 7 and launches[7].mode == "full" and launches[7].time == reading_deadline)
advance(6)
assert(G_reader_settings:readSetting("kindlespouse_reading_dirty") == false)
reader.saveSettings = function() error("Generated current reader save failure") end
assert(current:sync(false))
advance(0)
assert(#launches == 7 and Scheduler.snapshot().result.state == "failed")
assert(not exists("sync.launching"))
current:onCloseWidget()
os.time, os.execute = real_time, real_execute
assert(applied > 0 and clock > base)
print("KindleSpouse scheduler integration acceptance passed: shared hosts, debounce, raw process lock, marker handshake, full ISO result identity, fast completion, pause scope, reconnect")
