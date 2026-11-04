local root = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
package.path = root .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
local I18n = require("i18n")
local filename = root .. "/plugins/kindlespouse.koplugin/scheduler.lua"
local passed = 0

local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", received " .. tostring(actual))
end

local function fixture(options)
    options = options or {}
    G_reader_settings = { readSetting = function() return options.language or "en" end }
    local clock = options.now or 10000
    local settings = { kindlespouse_last_sync = options.last_sync or clock, kindlespouse_sync_generation = 0 }
    local connected, reading, running = true, false, false
    local pauses, tasks, launches, notices, files, warnings = {}, {}, {}, {}, {}, {}
    local sequence = 0
    local value = { state = "idle" }
    local host_seen
    local scheduler = assert(loadfile(filename))()
    local function schedule(delay, action)
        sequence = sequence + 1
        tasks[#tasks + 1] = { due = clock + delay, action = action, sequence = sequence }
    end
    local function unschedule(action)
        for index = #tasks, 1, -1 do if tasks[index].action == action then table.remove(tasks, index) end end
    end
    local deps = {
        logger = { warn = function(...) warnings[#warnings + 1] = { ... } end },
        now = function() return clock end,
        read = function(key, default) if settings[key] == nil then return default end; return settings[key] end,
        save = function(key, item) settings[key] = item end,
        connected = function() return connected end,
        reading = function() return reading end,
        paused = function(mode) return pauses[mode] == true end,
        running = function() return running end,
        progress = function() return value end,
        schedule = schedule,
        unschedule = unschedule,
        reserve = function(mode)
            if files.launching then return nil, "Launch already reserved" end
            local token = { mode = mode, id = #launches + 1 }
            files.launching = token
            return token
        end,
        release = function(token) if files.launching == token then files.launching = nil end end,
        notify = function(result, host) notices[#notices + 1] = result; host_seen = host end,
    }
    deps.launch = function(mode, manual, host)
        launches[#launches + 1] = { mode = mode, manual = manual, time = clock, host = host }
        host_seen = host
        if options.fail_launch then return false, "Generated launch failure" end
        if options.no_progress then return true end
        running = true
        local started, id = clock, #launches
        value = { state = "running", mode = mode, startedAt = started, updatedAt = clock, runId = id }
        schedule(options.duration or 2, function()
            running = false
            value = { state = "completed", mode = mode, startedAt = started, updatedAt = clock, completedAt = clock, runId = id }
        end)
        return true
    end
    scheduler.configure(deps)
    local env = { scheduler = scheduler, settings = settings, launches = launches, notices = notices, warnings = warnings, files = files, pauses = pauses, tasks = tasks, deps = deps }
    function env.advance(seconds)
        local ending = clock + seconds
        local count = 0
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
            assert(count < 2000, "Busy loop in scheduler")
        end
        clock = ending
    end
    function env.setConnected(item) connected = item end
    function env.setReading(item) reading = item end
    function env.setProgress(item, busy) value, running = item, busy end
    function env.host() return host_seen end
    function env.time() return clock end
    return env
end

local function check(name, body)
    body()
    passed = passed + 1
    print("PASS " .. name)
end

check("two hosts share one pending launch and late old detach preserves current host", function()
    local env = fixture()
    local first, second = {}, {}
    local old = env.scheduler.attach(first)
    env.scheduler.markDirty("close")
    env.advance(4)
    env.scheduler.attach(second)
    env.scheduler.detach(old)
    env.advance(12)
    equal(#env.launches, 1)
    equal(env.host(), second)
    equal(env.launches[1].time, 10015)
end)

check("five modifications debounce to one full job", function()
    local env = fixture()
    env.scheduler.attach({})
    for index = 1, 5 do env.scheduler.markDirty("annotations"); env.advance(2) end
    env.advance(12)
    equal(#env.launches, 0)
    env.advance(1)
    equal(#env.launches, 1)
    equal(env.launches[1].mode, "full")
    equal(env.settings.kindlespouse_sync_generation, 5)
end)

check("network reconnect requests full when dirty and updates otherwise after eight seconds", function()
    for _, dirty in ipairs({ false, true }) do
        local env = fixture()
        env.scheduler.attach({})
        env.setConnected(false)
        env.scheduler.networkDisconnected()
        if dirty then env.scheduler.pageDirty() end
        env.advance(50)
        equal(#env.launches, 0)
        env.setConnected(true)
        env.scheduler.networkConnected()
        env.advance(7)
        equal(#env.launches, 0)
        env.advance(1)
        equal(env.launches[1].mode, dirty and "full" or "updates")
    end
end)

check("pause flags remain authoritative even for manual requests", function()
    local env = fixture()
    env.scheduler.attach({})
    env.pauses.full = true
    env.scheduler.request("full", true)
    env.advance(30)
    equal(#env.launches, 0)
    equal(env.pauses.full, true)
    env.pauses.full = nil
    env.scheduler.request("full", true)
    env.advance(1)
    equal(#env.launches, 1)
end)

check("only matching successful full generation clears dirty flags", function()
    local env = fixture({ duration = 10 })
    env.scheduler.attach({})
    env.scheduler.markDirty("annotations")
    env.advance(16)
    env.scheduler.pageDirty()
    env.advance(10)
    equal(env.settings.kindlespouse_sync_dirty, true)
    equal(env.settings.kindlespouse_reading_dirty, true)
    env.scheduler.request("full", true)
    env.advance(12)
    equal(env.settings.kindlespouse_sync_dirty, false)
    equal(env.settings.kindlespouse_reading_dirty, false)
end)

check("old completed status never acknowledges a newly accepted launch", function()
    local env = fixture({ no_progress = true })
    env.scheduler.attach({})
    local stamp = env.time()
    env.setProgress({ state = "completed", mode = "full", startedAt = stamp, updatedAt = stamp, completedAt = stamp }, false)
    env.scheduler.markDirty("annotations")
    env.scheduler.request("full", true)
    env.advance(21)
    equal(env.settings.kindlespouse_sync_dirty, true)
    equal(env.scheduler.snapshot().result.state, "failed")
    equal(env.scheduler.snapshot().failures, 1)
end)

check("reservation prevents spawning until acquired and releases once worker observed", function()
    local env = fixture()
    env.scheduler.attach({})
    env.files.launching = { id = "another-owner" }
    env.scheduler.request("books", true)
    env.advance(1)
    equal(#env.launches, 0)
    equal(env.scheduler.snapshot().failures, 1)
    env.files.launching = nil
    env.advance(60)
    equal(#env.launches, 1)
    equal(env.files.launching, nil)
end)

check("launch failure uses exponential retry capped at fifteen minutes", function()
    local env = fixture({ fail_launch = true })
    env.settings.kindlespouse_auto_receive = false
    env.settings.kindlespouse_auto_sync = false
    env.scheduler.attach({})
    env.scheduler.request("profile", true)
    env.advance(0)
    for _, delay in ipairs({ 60, 120, 240, 480, 900, 900 }) do
        equal(env.scheduler.snapshot().retry_at - env.time(), delay)
        env.advance(delay)
    end
    equal(#env.launches, 7)
    equal(env.files.launching, nil)
end)

check("idle for ten minutes starts no repeated jobs after one stale boot check", function()
    local env = fixture({ last_sync = 1 })
    env.scheduler.attach({})
    env.advance(600)
    equal(#env.launches, 1)
    equal(env.launches[1].mode, "full")
    equal(#env.tasks, 1)
end)

check("fallback queues books and updates after fifteen awake minutes", function()
    local env = fixture()
    env.scheduler.attach({})
    env.advance(899)
    equal(#env.launches, 0)
    env.advance(12)
    equal(#env.launches, 2)
    equal(env.launches[1].mode, "books")
    equal(env.launches[2].mode, "updates")
end)

check("reading dirty full upload starts at exactly 600 seconds since last full sync", function()
    local env = fixture()
    env.setReading(true)
    env.scheduler.attach({})
    for index = 1, 10 do env.scheduler.pageDirty(); env.advance(59) end
    env.advance(9)
    equal(#env.launches, 0)
    env.advance(1)
    equal(#env.launches, 1)
    equal(env.launches[1].time, 10600)
    equal(env.launches[1].mode, "full")
    env.advance(6)
    equal(env.settings.kindlespouse_reading_dirty, false)
    env.scheduler.pageDirty()
    env.advance(595)
    equal(#env.launches, 1)
    env.advance(1)
    equal(#env.launches, 2)
    equal(env.launches[2].time, 11202)
end)

check("reading generation changed during upload remains dirty until next 600 second deadline", function()
    local env = fixture({ duration = 10 })
    env.setReading(true)
    env.scheduler.attach({})
    env.scheduler.pageDirty()
    env.advance(601)
    env.scheduler.pageDirty()
    env.advance(14)
    equal(env.settings.kindlespouse_reading_dirty, true)
    equal(#env.launches, 1)
    env.advance(594)
    equal(#env.launches, 1)
    env.advance(1)
    equal(#env.launches, 2)
    env.advance(15)
    equal(env.settings.kindlespouse_reading_dirty, false)
end)

check("reading deadline failure respects retry and pause without launching every page", function()
    local options = { fail_launch = true }
    local env = fixture(options)
    env.setReading(true)
    env.scheduler.attach({})
    env.scheduler.pageDirty()
    env.advance(600)
    equal(#env.launches, 1)
    equal(env.settings.kindlespouse_reading_dirty, true)
    env.scheduler.pageDirty()
    env.advance(59)
    equal(#env.launches, 1)
    env.pauses.full = true
    env.scheduler.pageDirty()
    env.advance(10)
    equal(#env.launches, 1)
    env.pauses.full = nil
    options.fail_launch = false
    env.scheduler.pageDirty()
    env.advance(6)
    equal(#env.launches, 2)
    equal(env.settings.kindlespouse_reading_dirty, false)
end)

check("reading deadline survives offline and suspended time with one reconnect job", function()
    local env = fixture()
    env.setReading(true)
    env.scheduler.attach({})
    env.scheduler.pageDirty()
    env.advance(599)
    env.setConnected(false)
    env.scheduler.networkDisconnected()
    env.scheduler.suspend()
    env.advance(100)
    equal(#env.launches, 0)
    equal(#env.tasks, 0)
    env.scheduler.resume()
    env.advance(10)
    equal(#env.launches, 0)
    env.setConnected(true)
    env.scheduler.networkConnected()
    env.advance(7)
    equal(#env.launches, 0)
    env.advance(7)
    equal(#env.launches, 1)
    equal(env.launches[1].mode, "full")
    equal(env.settings.kindlespouse_reading_dirty, false)
end)

check("reading deadline remains suspended until resume", function()
    local env = fixture()
    env.setReading(true)
    env.scheduler.attach({})
    env.scheduler.pageDirty()
    env.advance(599)
    env.scheduler.suspend()
    env.advance(100)
    equal(#env.launches, 0)
    env.scheduler.resume()
    env.advance(0)
    equal(#env.launches, 1)
    equal(env.launches[1].mode, "full")
end)

check("reading without dirty state only receives books and updates after thirty minutes", function()
    local env = fixture()
    env.setReading(true)
    env.scheduler.attach({})
    env.advance(1799)
    equal(#env.launches, 0)
    env.advance(12)
    equal(#env.launches, 2)
    equal(env.launches[1].mode, "books")
    equal(env.launches[2].mode, "updates")
end)

check("suspend stops all timers and recent resume adds no full sync", function()
    local env = fixture()
    env.scheduler.attach({})
    env.scheduler.suspend()
    env.advance(100)
    equal(#env.launches, 0)
    equal(#env.tasks, 0)
    env.scheduler.resume()
    env.advance(10)
    equal(#env.launches, 0)
    env.scheduler.suspend()
    env.advance(1801)
    env.scheduler.resume()
    env.advance(8)
    equal(#env.launches, 1)
    equal(env.launches[1].mode, "full")
end)

check("detaching current host retains debounce deadline for next attach", function()
    local env = fixture()
    local old = env.scheduler.attach({})
    env.scheduler.markDirty("close")
    env.scheduler.detach(old)
    env.advance(20)
    equal(#env.launches, 0)
    local host = {}
    env.scheduler.attach(host)
    env.advance(0)
    equal(#env.launches, 1)
    equal(env.host(), host)
end)

check("books completion never clears notes and requests coalesce globally", function()
    local env = fixture()
    local first = env.scheduler.attach({})
    env.scheduler.pageDirty()
    env.scheduler.request("books", false)
    env.scheduler.attach({})
    env.scheduler.detach(first)
    env.scheduler.request("books", false)
    env.advance(5)
    equal(#env.launches, 1)
    equal(env.settings.kindlespouse_reading_dirty, true)
end)

check("terminal status may omit a worker PID after its lock disappears", function()
    local env = fixture({ no_progress = true })
    env.scheduler.attach({})
    env.scheduler.request("full", true)
    env.advance(0)
    local stamp = env.time()
    env.setProgress({ state = "running", mode = "full", startedAt = stamp, updatedAt = stamp, pid = 12345 }, true)
    env.advance(1)
    env.setProgress({ state = "completed", mode = "full", startedAt = stamp, updatedAt = env.time(), completedAt = env.time() }, false)
    env.advance(5)
    equal(env.scheduler.snapshot().result.state, "completed")
    equal(env.scheduler.snapshot().result.manual, true)
end)

check("a restored network promptly retries after a previous failed launch", function()
    local options = { fail_launch = true }
    local env = fixture(options)
    env.scheduler.attach({})
    env.scheduler.request("updates", false)
    env.advance(0)
    equal(#env.launches, 1)
    options.fail_launch = false
    env.setConnected(false)
    env.scheduler.networkDisconnected()
    env.advance(1)
    env.setConnected(true)
    env.scheduler.networkConnected()
    env.advance(7)
    equal(#env.launches, 1)
    env.advance(1)
    equal(#env.launches, 2)
end)

check("reservation filesystem errors retry without wedging the active state", function()
    local env = fixture()
    env.scheduler.attach({})
    env.deps.reserve = function() error("Generated marker write failure") end
    env.scheduler.request("books", true)
    env.advance(0)
    equal(#env.launches, 0)
    equal(env.scheduler.snapshot().launch_pending, false)
    equal(env.scheduler.snapshot().failures, 1)
end)

check("overlapping offline sleep is excluded once from fallback elapsed time", function()
    local env = fixture()
    env.scheduler.attach({})
    env.advance(100)
    env.setConnected(false)
    env.scheduler.networkDisconnected()
    env.advance(100)
    env.scheduler.suspend()
    env.advance(300)
    env.scheduler.resume()
    env.advance(100)
    env.setConnected(true)
    env.scheduler.networkConnected()
    env.advance(10)
    equal(#env.launches, 1)
    env.advance(789)
    equal(#env.launches, 1)
    env.advance(13)
    equal(#env.launches, 3)
end)

check("automatic debounce cannot postpone an explicit manual request", function()
    local env = fixture()
    env.scheduler.attach({})
    env.scheduler.request("full", true)
    env.scheduler.markDirty("annotations")
    env.advance(0)
    equal(#env.launches, 1)
    equal(env.launches[1].manual, true)
end)

check("scheduler failures remain visible and localized in both languages", function()
    for _, locale in ipairs({ "en", "zh_CN" }) do
        local function expect(env, key, raw)
            local result = env.scheduler.snapshot().result
            equal(result.state, "failed")
            equal(result.error, I18n.T(key))
            equal(env.notices[#env.notices].error, I18n.T(key))
            equal(env.scheduler.snapshot().failures, 1)
            assert(result.retryAt > env.time())
            if raw then
                assert(not result.error:find(raw, 1, true))
                local warning = env.warnings[#env.warnings]
                equal(warning[1], "KindleSpouse:")
                assert(tostring(warning[3]):find(raw, 1, true))
            end
        end
        local env = fixture({ language = locale, fail_launch = true })
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        expect(env, "scheduler_cannot_launch", "Generated launch failure")
        env = fixture({ language = locale })
        env.deps.reserve = function() error("Generated raw reserve failure") end
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        expect(env, "scheduler_reserved", "Generated raw reserve failure")
        env = fixture({ language = locale })
        env.deps.launch = function() error("Generated raw execute failure") end
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        expect(env, "scheduler_cannot_launch", "Generated raw execute failure")
        env = fixture({ language = locale })
        env.deps.launch = function() return false, I18n.T("launcher_reading_failed") end
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        expect(env, "launcher_reading_failed")
        env = fixture({ language = locale, no_progress = true })
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(20)
        expect(env, "scheduler_timeout")
        env = fixture({ language = locale, no_progress = true })
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        local stamp = env.time()
        env.setProgress({ state = "running", mode = "full", startedAt = stamp, updatedAt = stamp }, true)
        env.advance(1)
        env.setProgress({ state = "idle" }, false)
        env.advance(5)
        expect(env, "scheduler_stopped")
        env = fixture({ language = locale, no_progress = true })
        env.scheduler.attach({})
        env.scheduler.request("full", true)
        env.advance(0)
        stamp = env.time()
        env.setProgress({ state = "failed", mode = "full", startedAt = stamp, error = "Generated raw worker failure" }, false)
        env.advance(1)
        expect(env, "scheduler_failed", "Generated raw worker failure")
    end
end)

print("KindleSpouse scheduler acceptance passed: " .. passed .. " scenarios")
