require("setupkoenv")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local sandbox = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
local seconds = tonumber(os.getenv("KINDLESPOUSE_IDLE_SECONDS")) or 600
assert(seconds >= 3)
io.stdout:setvbuf("line")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(sandbox .. "/settings.reader.lua")
G_reader_settings:saveSetting("disable_network_connection", true)
G_reader_settings:saveSetting("auto_suspend_timeout_seconds", 0)
G_reader_settings:saveSetting("kindlespouse_last_sync", os.time() - 601)
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup("en")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local time = require("ui/time")
local json = require("json")
local Scheduler = require("scheduler")
local started = time.now()
local started_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
local launches = {}
local running = false
local progress = { state = "idle" }
local host = {}
local token
local reservation
local completed = false
local function elapsed()
    return time.to_s(time.now() - started)
end
Scheduler.configure {
    now = os.time,
    read = function(key, default) return G_reader_settings:readSetting(key, default) end,
    save = function(key, value) G_reader_settings:saveSetting(key, value) end,
    connected = function() return true end,
    reading = function() return false end,
    paused = function() return false end,
    running = function() return running end,
    progress = function() return progress end,
    schedule = function(delay, callback) UIManager:scheduleIn(delay, callback) end,
    unschedule = function(callback) UIManager:unschedule(callback) end,
    reserve = function()
        if reservation then return nil, "Synthetic launch already reserved" end
        reservation = {}
        return reservation
    end,
    release = function(value) if reservation == value then reservation = nil end end,
    launch = function(mode, manual, current)
        assert(current == host)
        local epoch = os.time()
        local id = #launches + 1
        launches[id] = { mode = mode, manual = manual, elapsed_seconds = elapsed() }
        running = true
        progress = { state = "running", mode = mode, runId = id, startedAt = epoch, updatedAt = epoch }
        print(json.encode({ event = "synthetic_launch", mode = mode, elapsed_seconds = elapsed(), count = id }))
        UIManager:scheduleIn(2, function()
            running = false
            progress = { state = "completed", mode = mode, runId = id, startedAt = epoch, updatedAt = os.time(), completedAt = os.time() }
        end)
        return true
    end,
    notify = function(result) print(json.encode({ event = "scheduler_result", state = result.state, mode = result.mode, elapsed_seconds = elapsed() })) end,
}
token = Scheduler.attach(host)
UIManager:show(InfoMessage:new { text = "KindleSpouse scheduler idle acceptance\nReal-time UI event loop; isolated synthetic sync adapter.", dismissable = false })
print(json.encode({ event = "idle_started", started_at = started_at, requested_seconds = seconds, fake_clock = false, network_used = false }))
UIManager:scheduleIn(seconds, function()
    local duration = elapsed()
    local snapshot = Scheduler.snapshot()
    local passed = duration >= seconds - 0.05 and #launches == 1 and snapshot.result and snapshot.result.state == "completed"
    local result = { passed = passed == true, started_at = started_at, finished_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        requested_seconds = seconds, elapsed_seconds = duration, launch_count = #launches, launches = launches,
        fake_clock = false, real_uimanager = true, synthetic_worker = true, network_used = false,
        active = snapshot.running or snapshot.launch_pending }
    local stream = assert(io.open(sandbox .. "/result.json", "wb"))
    assert(stream:write(json.encode(result))); assert(stream:close())
    print(json.encode(result))
    completed = true
    Scheduler.detach(token)
    UIManager:quit(passed and 0 or 1)
end)
local exit_code = UIManager:run()
assert(completed, "UIManager exited before the idle acceptance deadline")
assert(exit_code == 0, "Idle acceptance failed")
print("KindleSpouse real-time scheduler idle acceptance passed")
