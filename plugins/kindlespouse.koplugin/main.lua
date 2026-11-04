local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local logger = require("logger")

local directory = "/mnt/us/kindlespouse/"
local Status = require("sync_status")
local Scheduler = require("scheduler")
local Launcher = require("launcher")
local Menu = require("menu")
local T = require("i18n").T
local synchronization_configured = false
local Companion = WidgetContainer:extend { name = "kindlespouse", is_doc_only = false, directory = directory }

local function readJSON(name)
    return Status.readJSON(name)
end

local function configureSynchronization(host)
    if synchronization_configured then return end
    synchronization_configured = true
    local root = host.directory or directory
    Status.configure { directory = root, logger = logger }
    Launcher.configure { directory = root, status = Status, logger = logger }
    Scheduler.configure {
        now = os.time,
        read = function(key, default) return G_reader_settings:readSetting(key, default) end,
        save = function(key, value) G_reader_settings:saveSetting(key, value) end,
        connected = function() return NetworkMgr:isConnected() end,
        reading = function()
            local reader = package.loaded["apps/reader/readerui"]
            return reader and reader.instance ~= nil or false
        end,
        enabled = function(mode)
            if lfs.attributes(root .. "/config.json", "mode") ~= "file" then return false end
            return G_reader_settings:readSetting(mode == "books" and "kindlespouse_auto_receive" or "kindlespouse_auto_sync") ~= false
        end,
        paused = Status.paused,
        running = Status.workerRunning,
        progress = function()
            local value = Status.snapshot()
            if value.launching then return { state = "idle" } end
            return value
        end,
        schedule = function(delay, callback) UIManager:scheduleIn(delay, callback) end,
        unschedule = function(callback) UIManager:unschedule(callback) end,
        reserve = Launcher.reserve,
        release = Launcher.release,
        launch = Launcher.launch,
        notify = function(result, current)
            if result.state == "completed" then
                current:applySleepProfile()
                current:queueAnnotationApply(0)
                local catalog = package.loaded.catalog
                if catalog and catalog.root and (result.mode == "books" or result.mode == "full") then catalog.rescan(catalog.root) end
            elseif result.state == "failed" then
                logger.warn("KindleSpouse:", "synchronization failed", tostring(result.error))
            end
            if result.manual then
                current:notify(result.state == "completed" and Status.summary(result.progress)
                    or result.state == "paused" and T("sync_paused_notice")
                    or T("sync_stopped_hint"))
            end
        end,
    }
end

function Companion:isRunning()
    return Status.isRunning()
end

function Companion:status()
    return Status.snapshot()
end

function Companion:summary(progress)
    return Status.summary(progress)
end

function Companion:requestSync(mode, manual)
    configureSynchronization(self)
    if not NetworkMgr:isConnected() then
        if manual then self:notify(T("sync_wifi_retry")) end
        return false
    end
    if lfs.attributes(self.directory .. "/config.json", "mode") ~= "file" then
        if manual then self:notify(T("pair_desktop")) end
        return false
    end
    if manual then
        local ok, failure = Launcher.manual(mode)
        if not ok then self:notify(failure); return false end
    elseif Status.paused(mode) then return false end
    Scheduler.request(mode, manual)
    if manual then self:notify(T("sync_queued")) end
    return true
end

function Companion:syncTitles()
    return self:requestSync("titles", true)
end

function Companion:notify(text)
    UIManager:show(Notification:new { text = text, timeout = 3, toast = true })
end

function Companion:syncProfile()
    return self:requestSync("profile", true)
end

function Companion:init()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.registerPostInitCallback then require("home").install(self) end
    configureSynchronization(self)
    self.scheduler_token = Scheduler.attach(self)
    self:queueAnnotationApply(2)
    if G_reader_settings then self:applySleepProfile() end
    if lfs.attributes(directory .. "catalog.requested", "mode") then
        os.remove(directory .. "catalog.requested")
        UIManager:scheduleIn(1, function() self:collectTitles() end)
    end
end

function Companion:autoSyncEnabled()
    return G_reader_settings:readSetting("kindlespouse_auto_sync") ~= false
end

function Companion:checkUpdates()
    return self:requestSync("updates", false)
end

function Companion:onPageUpdate(page)
    if page == self.reading_page then return end
    self.reading_page = page
    Scheduler.pageDirty()
end

function Companion:queueAutomaticSync()
    Scheduler.markDirty("annotations")
end

function Companion:onAnnotationsModified()
    Scheduler.markDirty("annotations")
end

function Companion:saveReadingState()
    local ok, failure = pcall(function()
        local reader = package.loaded["apps/reader/readerui"]
        reader = reader and reader.instance
        if reader and reader.document then reader:saveSettings() end
    end)
    if not ok then logger.warn("KindleSpouse:", "cannot save reading state before synchronization", tostring(failure)) end
    return ok
end

function Companion:receiveBooks(silent)
    return self:requestSync("books", not silent)
end

function Companion:onSuspend()
    Scheduler.suspend()
end

function Companion:onResume()
    Scheduler.resume()
end

function Companion:onNetworkConnected()
    Scheduler.networkConnected()
end

function Companion:onNetworkDisconnected()
    Scheduler.networkDisconnected()
end

function Companion:applySleepProfile()
    local profile = readJSON("sleep-profile.json")
    if not profile or type(profile.revision) ~= "string" or profile.version ~= 1 then return end
    if G_reader_settings:readSetting("kindlespouse_sleep_revision") == profile.revision then return end
    self.sleep_cover_requested = profile.enabled
    if self:setSleepCover(profile.enabled) == false then return end
    G_reader_settings:saveSetting("kindlespouse_sleep_revision", profile.revision)
    self:prepareSleepCover()
end

function Companion:sleepPreset()
    local ok, preset = pcall(require, "spouse_preset")
    if not ok or type(preset) ~= "table" or type(preset.prepare) ~= "function" then
        if not Companion.preset_missing then logger.warn("KindleSpouse:", "sleep cover preset is not installed") end
        Companion.preset_missing = true
        return
    end
    Companion.preset_missing = false
    return preset
end

function Companion:prepareSleepCover()
    local preset = self:sleepPreset()
    if not preset then return end
    UIManager:scheduleIn(0.5, function()
        local reader = package.loaded["apps/reader/readerui"]
        reader = reader and reader.instance
        if reader and reader.document then
            local ok, error = pcall(preset.prepare, reader)
            if not ok then logger.warn("KindleSpouse:", "sleep cover preparation failed", tostring(error)) end
        end
    end)
end

function Companion:onReaderReady()
    self:prepareSleepCover()
    self:onPageUpdate(0)
end

function Companion:setSleepCover(enabled)
    local current = G_reader_settings:readSetting("screensaver_type")
    if enabled then
        if not self:sleepPreset() then return false end
        if current ~= "customisable_ss" then G_reader_settings:saveSetting("kindlespouse_previous_screensaver", current or "cover") end
        G_reader_settings:saveSetting("screensaver_type", "customisable_ss")
    elseif current == "customisable_ss" then
        G_reader_settings:saveSetting("screensaver_type", G_reader_settings:readSetting("kindlespouse_previous_screensaver", "cover"))
    end
end

function Companion:queueAnnotationApply(delay)
    if not self.annotation_task then
        self.annotation_task = function()
            if self.scheduler_token then self:applyAnnotations() end
        end
    end
    UIManager:unschedule(self.annotation_task)
    UIManager:scheduleIn(delay, self.annotation_task)
end

function Companion:applyAnnotations()
    local ok, count, retry = pcall(function() return require("annotation_apply").run(directory) end)
    if not ok then logger.warn("KindleSpouse:", "annotation queue failed", tostring(count)) end
    if ok and count > 0 then
        self:queueAutomaticSync()
        self:queueAnnotationApply(0.5)
    elseif ok and retry then self:queueAnnotationApply(30)
    end
end

function Companion:collectTitles()
    local started = os.time()
    os.execute("sh /mnt/us/kindlespouse/catalog.sh < /dev/null > /dev/null 2>&1 &")
    self:notify(T("catalog_started"))
    local attempts = 0
    local check
    check = function()
        attempts = attempts + 1
        local result = readJSON("catalog-result.json")
        if result and tonumber(result.completedAt) and result.completedAt >= started then
            self:notify(result.ok and T("catalog_ready") or T("catalog_failed"))
        elseif attempts < 15 then UIManager:scheduleIn(2, check)
        else self:notify(T("catalog_timeout")) end
    end
    UIManager:scheduleIn(2, check)
end

function Companion:pause()
    if not Launcher.pause() then self:notify(T("pause_save_failed")); return false end
    self:notify(T("pause_started"))
    return true
end

function Companion:showStatus()
    return Menu.showStatus(self)
end

function Companion:saveSleepPreference(enabled)
    local profile = readJSON("sleep-profile.json") or { version = 1, displayName = "Reader", avatar = "R" }
    profile.enabled = enabled
    local file = io.open(directory .. "sleep-profile.json.partial", "wb")
    if not file then self:notify(T("sleep_save_failed")); return false end
    local written = file:write(json.encode(profile))
    local closed = file:close()
    if not written or not closed or not os.rename(directory .. "sleep-profile.json.partial", directory .. "sleep-profile.json") then
        self:notify(T("sleep_save_failed")); return false
    end
    return self:setSleepCover(enabled)
end

function Companion:sleepWarning()
    if Companion.preset_missing and (self.sleep_cover_requested or G_reader_settings:readSetting("screensaver_type") == "customisable_ss") then
        return T("sleep_missing")
    end
end

function Companion:sync(silent)
    return self:requestSync("full", not silent)
end

function Companion:setAutoSyncEnabled(enabled)
    G_reader_settings:saveSetting("kindlespouse_auto_sync", enabled == true)
    if enabled then
        local ok, failure = Launcher.manual("updates")
        if not ok then self:notify(failure); return false end
        Scheduler.markDirty("annotations")
    end
    return true
end

function Companion:setAutoReceiveEnabled(enabled)
    G_reader_settings:saveSetting("kindlespouse_auto_receive", enabled == true)
    if enabled then
        local ok, failure = Launcher.manual("books")
        if not ok then self:notify(failure); return false end
        self:receiveBooks(true)
    end
    return true
end

function Companion:refreshLibrary()
    if self.ui.document then return end
    require("catalog").rescan(require("home").root(self.ui))
end

function Companion:toggleHome()
    require("home").toggle(self)
end

function Companion:openProfile()
    require("profile").open(self)
end

function Companion:addToMainMenu(menu_items)
    menu_items.kindlespouse = Menu.build(self)
end

function Companion:onCloseDocument()
    local file = self.ui and self.ui.document and self.ui.document.file
    if file then UIManager:scheduleIn(0.05, function()
        require("ui/widget/booklist").resetBookInfoCache(file)
        local catalog = package.loaded.catalog
        if catalog then catalog.touch(file) end
    end) end
    self:queueAnnotationApply(1)
    Scheduler.markDirty("close")
end

function Companion:onCloseWidget()
    if self.ui and not self.ui.document then require("home").uninstall(self.ui) end
    Scheduler.detach(self.scheduler_token)
    self.scheduler_token = nil
    if self.annotation_task then UIManager:unschedule(self.annotation_task) end
    Menu.closeStatus(self)
end

return Companion
