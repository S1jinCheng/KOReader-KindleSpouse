require("setupkoenv")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local sandbox = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open(sandbox .. "/bootstrap.lua")
local Device = require("device")
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Version = require("version")
local util = require("util")
local json = require("json")
local real_time, real_execute = os.time, os.execute
local original_version = Version.getNormalizedCurrentVersion
local cases, scenario = 0, 0

local function fixture(options)
    options = options or {}
    cases = cases + 1
    local root = sandbox .. "/case-" .. cases .. "/"
    util.makePath(root .. "proc/4242")
    local clock, tasks, sequence = real_time() + cases * 100, {}, 0
    local prepared, applied, installed, removed, registered, rescanned, reinits = 0, 0, 0, 0, 0, 0, 0
    local commands, notifications = {}, {}
    os.time = function() return clock end
    G_reader_settings = require("luasettings"):open(root .. "settings.reader.lua")
    G_reader_settings:saveSetting("kindlespouse_last_sync", clock)
    G_reader_settings:saveSetting("kindlespouse_sync_generation", 0)
    G_reader_settings:saveSetting("screensaver_type", options.sleep and "customisable_ss" or "cover")
    for _, name in ipairs({ "scheduler", "launcher", "sync_status", "sleep_cover", "menu", "version_guard", "patches" }) do package.loaded[name] = nil end
    package.loaded["reader/init"], package.loaded["reader.init"] = nil, nil
    local reader = { document = {}, saveSettings = function() end }
    package.loaded["apps/reader/readerui"] = { instance = options.reading and reader or nil }
    package.preload.spouse_preset = nil
    package.loaded.spouse_preset = { prepare = function() prepared = prepared + 1 end }
    Version.getNormalizedCurrentVersion = function() return options.unsupported and 202601010000 or 202607010000 end
    UIManager.scheduleIn = function(_, delay, action)
        sequence = sequence + 1
        tasks[#tasks + 1] = { due = clock + delay, action = action, sequence = sequence }
    end
    UIManager.unschedule = function(_, action)
        for index = #tasks, 1, -1 do if tasks[index].action == action then table.remove(tasks, index) end end
    end
    UIManager.show = function() end
    UIManager.close = function(_, widget) if widget.dismiss_callback then widget.dismiss_callback() end end
    UIManager.setDirty = function() end
    NetworkMgr.isConnected = function() return true end
    local function write(name, value)
        local stream = assert(io.open(root .. name, "wb"))
        assert(stream:write(value)); assert(stream:close())
    end
    local function data(name, value) write(name, json.encode(value)) end
    data("config.json", { version = 1, deviceId = "generated" })
    if options.catalog_request then write("catalog.requested", "requested\n") end
    os.execute = function(command)
        commands[#commands + 1] = command
        if command:find("catalog.sh", 1, true) then return 0 end
        local mode, started, id = command:match(" '(%w+)' <") or "full", clock, #commands
        write("proc/4242/cmdline", "kindlespouse-sync\0generated")
        write("sync.lock", "4242\n")
        data("progress.json", { state = "running", mode = mode, startedAt = started, updatedAt = clock })
        UIManager:scheduleIn(2, function()
            os.remove(root .. "sync.lock")
            data("progress.json", { state = "completed", mode = mode, startedAt = started, updatedAt = clock, completedAt = clock })
            data("last-result.json", { ok = true, mode = mode, completedAt = os.date("!%Y-%m-%dT%H:%M:%S", clock) .. string.format(".%09dZ", id) })
        end)
        return 0
    end
    local target = { run = function() return "original" end }
    package.loaded.home = {
        install = function(host)
            installed = installed + 1
            if options.throw then
                require("patches").wrap("home:lifecycle-test", target, "run", function() return "wrapped" end)
                error("Generated missing upstream UI method")
            end
            if options.deferred_throw then
                host.ui:registerPostInitCallback(function() error("Generated missing deferred upstream UI method") end)
            end
        end,
        uninstall = function() removed = removed + 1 end,
        toggle = function() end,
        root = function() return root end,
    }
    package.loaded.catalog = { rescan = function(directory) assert(directory == root); rescanned = rescanned + 1 end }
    local Companion = dofile(project .. "/plugins/kindlespouse.koplugin/main.lua")
    Companion.directory = root
    local env = { tasks = tasks, commands = commands, target = target, root = root, write = write, data = data }
    function env.read(name)
        local stream = assert(io.open(root .. name, "rb"))
        local bytes = stream:read("*a")
        stream:close()
        return bytes
    end
    function env.host(document)
        local ui = { document = document, callbacks = {}, file_chooser = { path = root },
            menu = { registerToMainMenu = function() registered = registered + 1 end } }
        ui.registerPostInitCallback = function(manager, callback) manager.callbacks[#manager.callbacks + 1] = callback end
        ui.reinit = function() reinits = reinits + 1 end
        local host = setmetatable({ directory = root, ui = ui }, { __index = Companion })
        host.notify = function(_, message) notifications[#notifications + 1] = message end
        host.applyAnnotations = function() applied = applied + 1 end
        host:init()
        require("sync_status").configure { directory = root, proc_directory = root .. "proc/", now = os.time }
        return host
    end
    function env.advance(seconds)
        local ending, turns = clock + seconds, 0
        while true do
            local selected
            for index, task in ipairs(tasks) do
                if task.due <= ending and (not selected or task.due < tasks[selected].due or task.due == tasks[selected].due and task.sequence < tasks[selected].sequence) then selected = index end
            end
            if not selected then break end
            local task = table.remove(tasks, selected)
            clock = math.max(clock, task.due)
            task.action()
            turns = turns + 1
            assert(turns < 1000, "Lifecycle callback loop")
        end
        clock = ending
    end
    function env.counts() return prepared, applied, installed, removed, registered, rescanned, reinits end
    function env.syncAttached() return require("scheduler").snapshot().attached end
    return env
end

local function check(name, test)
    test()
    scenario = scenario + 1
    print("PASS " .. name)
end

for _, kind in ipairs({ "supported", "unsupported", "throw" }) do
    check(kind .. " interface preserves shared synchronization", function()
        local env = fixture({ unsupported = kind == "unsupported", throw = kind == "throw" })
        local host = env.host(nil)
        local _, _, installed, _, registered = env.counts()
        assert(env.syncAttached() and registered == 1)
        assert(installed == (kind == "unsupported" and 0 or 1))
        assert(env.target.run() == "original")
        assert(require("version_guard").status().disabled == (kind ~= "supported"))
        assert(host:receiveBooks(false))
        env.advance(10)
        assert(#env.commands == 1 and require("scheduler").snapshot().result.state == "completed")
        host:onCloseWidget()
        assert(not env.syncAttached())
    end)
end

check("deferred PostInit failures are guarded and do not stop sync", function()
    local env = fixture({ deferred_throw = true })
    local host = env.host(nil)
    assert(#host.ui.callbacks == 1)
    assert(pcall(host.ui.callbacks[1]))
    assert(require("version_guard").status().disabled and env.syncAttached())
    assert(host:receiveBooks(false))
    env.advance(10)
    assert(#env.commands == 1 and require("scheduler").snapshot().result.state == "completed")
    host:onCloseWidget()
end)

check("reader hook is optional until its module is explicitly loaded", function()
    local env = fixture({ reading = true })
    local host = env.host({})
    host:onReaderReady()
    assert(package.loaded["reader/init"] == nil)
    local installed = 0
    package.loaded["reader/init"] = { install = function(current) assert(current == host.ui); installed = installed + 1 end }
    host:onReaderReady()
    assert(installed == 1 and env.syncAttached())
    host:onCloseWidget()
end)

check("closing current host cancels annotation title status and sleep callbacks", function()
    local env = fixture({ reading = true, sleep = true })
    local host = env.host({})
    host:prepareSleepCover()
    host:queueAnnotationApply(20)
    host:collectTitles()
    host:showStatus()
    assert(#env.tasks > 3)
    host:onCloseWidget()
    assert(#env.tasks == 0 and not env.syncAttached())
    env.advance(40)
    local prepared, applied = env.counts()
    assert(prepared == 0 and applied == 0 and host.title_check == nil and host.kindlespouse_status_session == nil)
end)

check("late old close cannot cancel successor synchronization status or sleep preparation", function()
    local env = fixture({ reading = true, sleep = true })
    local old = env.host(nil)
    old:queueAnnotationApply(20)
    old:collectTitles()
    old:showStatus()
    local current = env.host({})
    current:prepareSleepCover()
    current:showStatus()
    old:onCloseWidget()
    old:onSuspend()
    assert(env.syncAttached() and not require("scheduler").snapshot().suspended)
    assert(current.kindlespouse_status_session and old.kindlespouse_status_session == nil)
    env.advance(0.5)
    local prepared = env.counts()
    assert(prepared == 1)
    current:onCloseWidget()
    assert(#env.tasks == 0)
end)

check("menu and sleep operations delegate to their shared helpers", function()
    local env = fixture()
    local host = env.host(nil)
    local entries = {}
    host:addToMainMenu(entries)
    assert(entries.kindlespouse and #entries.kindlespouse.sub_item_table >= 8)
    assert(host:refreshLibrary())
    local _, _, _, _, _, rescanned, reinits = env.counts()
    assert(rescanned == 1 and reinits == 0)
    assert(host:setSleepCover(true))
    assert(G_reader_settings:readSetting("screensaver_type") == "customisable_ss")
    assert(host:setSleepCover(false))
    assert(G_reader_settings:readSetting("screensaver_type") == "cover")
    assert(host:setAutoSyncEnabled(false))
    assert(G_reader_settings:readSetting("kindlespouse_auto_sync") == false)
    assert(host:setAutoReceiveEnabled(false))
    assert(G_reader_settings:readSetting("kindlespouse_auto_receive") == false)
    host:onCloseWidget()
end)

check("queued title collection and retired PostInit callbacks stop on close", function()
    local env = fixture({ catalog_request = true, deferred_throw = true })
    local host = env.host(nil)
    assert(host.title_request_task and #host.ui.callbacks == 1)
    host:onCloseWidget()
    assert(#env.tasks == 0)
    assert(pcall(host.ui.callbacks[1]))
    assert(not require("version_guard").status().disabled)
    env.advance(10)
    assert(#env.commands == 0)
end)

check("Home registration guard never wraps another plugin's PostInit callback", function()
    local env = fixture()
    local host = env.host(nil)
    host.ui:registerPostInitCallback(function() error("Generated foreign plugin failure") end)
    assert(not pcall(host.ui.callbacks[1]))
    assert(not require("version_guard").status().disabled and env.syncAttached())
    host:onCloseWidget()
end)

check("missing preset preserves the previous persisted sleep profile and acknowledgment", function()
    local env = fixture()
    local host = env.host(nil)
    local original = '{ "version": 1, "revision": "new-remote", "enabled": false, "displayName": "Preserved" }'
    env.write("sleep-profile.json", original)
    G_reader_settings:saveSetting("kindlespouse_sleep_revision", "old-acknowledgment")
    package.loaded.spouse_preset = nil
    package.preload.spouse_preset = function() error("Generated missing preset") end
    assert(host:setSleepCover(true) == false)
    assert(env.read("sleep-profile.json") == original)
    assert(G_reader_settings:readSetting("screensaver_type") == "cover")
    assert(G_reader_settings:readSetting("kindlespouse_sleep_revision") == "old-acknowledgment")
    host:onCloseWidget()
end)

for _, failure in ipairs({ "write", "rename" }) do
    check(failure .. " failure preserves the old sleep profile and settings", function()
        local env = fixture()
        local host = env.host(nil)
        local original = '{ "version": 1, "revision": "new-remote", "enabled": false }'
        env.write("sleep-profile.json", original)
        G_reader_settings:saveSetting("kindlespouse_sleep_revision", "old-acknowledgment")
        local open, rename = io.open, os.rename
        if failure == "write" then
            io.open = function(name, mode)
                if mode == "wb" and name:find("sleep-profile.json.", 1, true) then return nil, "Generated write failure" end
                return open(name, mode)
            end
        else os.rename = function() return nil, "Generated atomic rename failure" end end
        local called, saved = pcall(host.setSleepCover, host, true)
        io.open, os.rename = open, rename
        assert(called and saved == false)
        assert(env.read("sleep-profile.json") == original)
        assert(G_reader_settings:readSetting("screensaver_type") == "cover")
        assert(G_reader_settings:readSetting("kindlespouse_sleep_revision") == "old-acknowledgment")
        for name in require("libs/libkoreader-lfs").dir(env.root) do assert(not name:match("%.partial$")) end
        host:onCloseWidget()
    end)
end

check("user preference persists atomically before preparation and disabling restores the old screen", function()
    local env = fixture({ reading = true })
    local host = env.host({})
    env.data("sleep-profile.json", { version = 1, revision = "server-revision", enabled = false, displayName = "Preserved", avatar = "P" })
    G_reader_settings:saveSetting("kindlespouse_sleep_revision", "old-acknowledgment")
    assert(host:setSleepCover(true))
    local profile = json.decode(env.read("sleep-profile.json"))
    assert(profile.enabled == true and profile.displayName == "Preserved" and profile.revision == "server-revision")
    assert(G_reader_settings:readSetting("screensaver_type") == "customisable_ss")
    assert(G_reader_settings:readSetting("kindlespouse_sleep_revision") == "old-acknowledgment")
    env.advance(0.5)
    local prepared = env.counts()
    assert(prepared == 1)
    assert(host:setSleepCover(false))
    assert(json.decode(env.read("sleep-profile.json")).enabled == false)
    assert(G_reader_settings:readSetting("screensaver_type") == "cover")
    env.advance(1)
    assert(env.counts() == 1)
    host:onCloseWidget()
end)

check("incoming profiles apply without rewriting their bytes through preference persistence", function()
    local env = fixture({ reading = true })
    local host = env.host({})
    local original = '{ "version": 1, "revision": "incoming-revision", "enabled": true, "displayName": "Incoming" }'
    env.write("sleep-profile.json", original)
    local preference_writes = 0
    local open = io.open
    io.open = function(name, mode)
        if mode == "wb" and name:find("sleep-profile.json", 1, true) then preference_writes = preference_writes + 1 end
        return open(name, mode)
    end
    local called, applied = pcall(host.applySleepProfile, host)
    io.open = open
    assert(called and applied and preference_writes == 0)
    assert(env.read("sleep-profile.json") == original)
    assert(G_reader_settings:readSetting("kindlespouse_sleep_revision") == "incoming-revision")
    host:onCloseWidget()
end)

check("a failed Home module require cannot break synchronization or teardown", function()
    local env = fixture()
    package.loaded.home = nil
    package.preload.home = function() error("Generated Home module load failure") end
    local host = env.host(nil)
    assert(require("version_guard").status().disabled and env.syncAttached())
    assert(host:receiveBooks(false))
    env.advance(10)
    assert(#env.commands == 1 and require("scheduler").snapshot().result.state == "completed")
    local closed, failure = pcall(host.onCloseWidget, host)
    package.preload.home = nil
    assert(closed, tostring(failure))
    assert(not env.syncAttached())
end)

os.time, os.execute = real_time, real_execute
Version.getNormalizedCurrentVersion = original_version
print("KindleSpouse main lifecycle acceptance passed: " .. scenario .. " scenarios")
