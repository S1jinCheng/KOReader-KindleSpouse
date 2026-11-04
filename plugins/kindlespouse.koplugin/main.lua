local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local directory = "/mnt/us/kindlespouse/"
local Status = require("sync_status")
local Scheduler = require("scheduler")
local Launcher = require("launcher")
local Sleep = require("sleep_cover")
local Menu = require("menu")
local Guard = require("version_guard")
local Patches = require("patches")
local T = require("i18n").T
local current_host
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
    Sleep.configure { settings = G_reader_settings, status = Status, logger = logger }
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

function Companion:guardPostInit(ui)
    local id = "kindlespouse:" .. tostring(ui) .. ":postinit"
    if Patches.applied[id] then return id end
    Patches.wrap(id, ui, "registerPostInitCallback", function(original, manager, callback, ...)
        return original(manager, function(...)
            if not self.closed then return Guard.run(callback, ...) end
        end, ...)
    end)
    return id
end

function Companion:installReaderExperience()
    local reader = package.loaded["reader/init"] or package.loaded["reader.init"]
    if type(reader) == "table" and type(reader.install) == "function" then
        return Guard.install(self.ui, function() return reader.install(self.ui) end)
    end
end

function Companion:init()
    self.closed = false
    configureSynchronization(self)
    self.scheduler_token = Scheduler.attach(self)
    current_host = self
    self:queueAnnotationApply(2)
    self:applySleepProfile()
    local menu = self.ui and self.ui.menu
    if menu and type(menu.registerToMainMenu) == "function" then
        local ok, failure = pcall(menu.registerToMainMenu, menu, self)
        if not ok then logger.warn("KindleSpouse:", "cannot register synchronization menu", tostring(failure)) end
    end
    Guard.install(self.ui, function(ui)
        if ui and ui.registerPostInitCallback then
            local postinit = self:guardPostInit(ui)
            require("home").install(self)
            Patches.revert(postinit)
        end
        if ui and ui.document then self:installReaderExperience() end
    end)
    local title_request = self.directory .. "/catalog.requested"
    if lfs.attributes(title_request, "mode") then
        os.remove(title_request)
        self.title_request_task = function() if not self.closed then self:collectTitles() end end
        UIManager:scheduleIn(1, self.title_request_task)
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
    if current_host ~= self then return end
    Scheduler.suspend()
    Sleep.cancel()
    Menu.closeStatus(self)
end

function Companion:onResume()
    if current_host ~= self then return end
    Scheduler.resume()
end

function Companion:onNetworkConnected()
    if current_host ~= self then return end
    Scheduler.networkConnected()
end

function Companion:onNetworkDisconnected()
    if current_host ~= self then return end
    Scheduler.networkDisconnected()
end

function Companion:applySleepProfile()
    return Sleep.applyProfile()
end

function Companion:prepareSleepCover()
    if not self.closed then return Sleep.prepare() end
end

function Companion:onReaderReady()
    self:prepareSleepCover()
    self:installReaderExperience()
    self:onPageUpdate(0)
end

function Companion:setSleepCover(enabled)
    local saved = Sleep.savePreference(enabled, { directory = self.directory })
    if not saved then self:notify(T("sleep_save_failed")) end
    return saved
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
    local ok, count, retry = pcall(function() return require("annotation_apply").run(self.directory) end)
    if not ok then logger.warn("KindleSpouse:", "annotation queue failed", tostring(count)) end
    if ok and count > 0 then
        self:queueAutomaticSync()
        self:queueAnnotationApply(0.5)
    elseif ok and retry then self:queueAnnotationApply(30)
    end
end

function Companion:collectTitles()
    if self.closed then return false end
    if self.title_check then UIManager:unschedule(self.title_check) end
    local started = os.time()
    os.execute("sh /mnt/us/kindlespouse/catalog.sh < /dev/null > /dev/null 2>&1 &")
    self:notify(T("catalog_started"))
    local attempts = 0
    self.title_check = function()
        if self.closed then return end
        attempts = attempts + 1
        local result = readJSON("catalog-result.json")
        if result and tonumber(result.completedAt) and result.completedAt >= started then
            self.title_check = nil
            self:notify(result.ok and T("catalog_ready") or T("catalog_failed"))
        elseif attempts < 15 then UIManager:scheduleIn(2, self.title_check)
        else self.title_check = nil; self:notify(T("catalog_timeout")) end
    end
    UIManager:scheduleIn(2, self.title_check)
    return true
end

function Companion:pause()
    if not Launcher.pause() then self:notify(T("pause_save_failed")); return false end
    self:notify(T("pause_started"))
    return true
end

function Companion:showStatus()
    return Menu.showStatus(self)
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

function Companion:toggleHome()
    return Guard.install(self.ui, function() return require("home").toggle(self) end)
end

function Companion:refreshLibrary()
    if not self.ui or self.ui.document then return false end
    return Guard.install(self.ui, function(ui)
        local Catalog = require("catalog")
        local Home = require("home")
        Catalog.rescan(Home.root(ui))
    end)
end

function Companion:openProfile()
    return Guard.install(self.ui, function() return require("profile").open(self) end)
end

function Companion:addToMainMenu(menu_items)
    menu_items.kindlespouse = Menu.build(self)
end

function Companion:onInvalidateMetadataCache(file)
    local catalog = package.loaded.catalog
    if catalog and type(file) == "string" then catalog.touch(file, true) end
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
    self.closed = true
    Scheduler.detach(self.scheduler_token)
    self.scheduler_token = nil
    for _, name in ipairs({ "annotation_task", "title_check", "title_request_task" }) do
        if self[name] then UIManager:unschedule(self[name]); self[name] = nil end
    end
    Menu.closeStatus(self)
    Patches.revertPrefix("kindlespouse:" .. tostring(self.ui) .. ":")
    local home = package.loaded.home
    if type(home) == "table" and type(home.uninstall) == "function" and self.ui and not self.ui.document then
        local ok, failure = pcall(home.uninstall, self.ui)
        if not ok then logger.warn("KindleSpouse:", "cannot restore home interface", tostring(failure)) end
    end
    if current_host == self then current_host = nil; Sleep.cancel() end
end

return Companion
