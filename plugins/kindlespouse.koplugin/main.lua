local WidgetContainer = require("ui/widget/container/widgetcontainer")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local NetworkMgr = require("ui/network/manager")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local logger = require("logger")

local directory = "/mnt/us/kindlespouse/"
local Status = require("sync_status")
local Scheduler = require("scheduler")
local Launcher = require("launcher")
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
                    or result.state == "paused" and "KindleSpouse: sync paused."
                    or "KindleSpouse: sync stopped. Open Sync status for details.")
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
        if manual then self:notify("KindleSpouse: connect Wi-Fi, then retry.") end
        return false
    end
    if lfs.attributes(self.directory .. "/config.json", "mode") ~= "file" then
        if manual then self:notify("KindleSpouse: pair this Kindle from the desktop app first.") end
        return false
    end
    if manual then
        local ok, failure = Launcher.manual(mode)
        if not ok then self:notify(failure); return false end
    elseif Status.paused(mode) then return false end
    Scheduler.request(mode, manual)
    if manual then self:notify("KindleSpouse: synchronization queued in background.") end
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
    self:notify("KindleSpouse: preparing notebook titles offline.")
    local attempts = 0
    local check
    check = function()
        attempts = attempts + 1
        local result = readJSON("catalog-result.json")
        if result and tonumber(result.completedAt) and result.completedAt >= started then
            self:notify(result.ok and "KindleSpouse: title index ready. You can reconnect USB." or "KindleSpouse: could not read title index.")
        elseif attempts < 15 then UIManager:scheduleIn(2, check)
        else self:notify("KindleSpouse: title collection stopped. Try Collect notebook titles again.") end
    end
    UIManager:scheduleIn(2, check)
end

function Companion:pause()
    if not Launcher.pause() then self:notify("KindleSpouse: cannot save pause request."); return false end
    self:notify("KindleSpouse: pausing sync. Uploaded files are kept.")
    return true
end

function Companion:showStatus()
    if self.status_dialog then UIManager:close(self.status_dialog) end
    local dialog
    local refresh
    local function text()
        local progress = self:status()
        local hint = progress.state == "running" and "Sync continues in the background. " or ""
        local cover = Companion.preset_missing and (self.sleep_cover_requested or G_reader_settings and G_reader_settings:readSetting("screensaver_type") == "customisable_ss")
            and "\n\n休眠封面组件未安装，请在桌面端重新配对" or ""
        return self:summary(progress) .. cover .. "\n\n" .. hint .. "Tap to return to reading."
    end
    dialog = InfoMessage:new {
        text = text(), show_icon = false,
        dismiss_callback = function()
            self.status_dialog = nil
            if refresh then UIManager:unschedule(refresh) end
        end,
    }
    self.status_dialog = dialog
    UIManager:show(dialog)
    refresh = function()
        if self.status_dialog ~= dialog then return end
        local value = text()
        if dialog.text ~= value then
            local previous_area = dialog:getVisibleArea()
            dialog:free()
            dialog.text = value
            dialog:init()
            UIManager:setDirty(nil, "ui", previous_area)
            UIManager:setDirty(dialog, "ui")
        end
        if self:isRunning() then UIManager:scheduleIn(3, refresh) end
    end
    if self:isRunning() then UIManager:scheduleIn(3, refresh) end
end

function Companion:sync(silent)
    return self:requestSync("full", not silent)
end

function Companion:addToMainMenu(menu_items)
    menu_items.kindlespouse = { text = "KindleSpouse", sub_item_table = {
        { text = "Profile and cloud sync", callback = function() require("profile").open(self) end },
        { text = "Use KindleSpouse home", enabled_func = function() return not self.ui.document end,
          checked_func = function() return G_reader_settings:readSetting("kindlespouse_home") ~= false end,
          callback = function() if not self.ui.document then require("home").toggle(self) end end },
        { text_func = function() return lfs.attributes(directory .. "pause.requested", "mode") and "Resume sync" or "Sync now" end,
          callback = function() self:sync(false) end },
        { text = "Pause sync", callback = function() self:pause() end },
        { text = "Sync profile now", callback = function() self:syncProfile() end },
        { text = "Check for new books", callback = function() self:receiveBooks(false) end },
        { text = "Automatically receive books", checked_func = function() return not G_reader_settings or G_reader_settings:readSetting("kindlespouse_auto_receive") ~= false end,
          callback = function() if G_reader_settings then local enabled = G_reader_settings:readSetting("kindlespouse_auto_receive") == false; G_reader_settings:saveSetting("kindlespouse_auto_receive", enabled); if enabled then os.remove(directory .. "books-pause.requested"); self:receiveBooks(true) end end end },
        { text = "Automatically sync notes and reading history", checked_func = function() return self:autoSyncEnabled() end,
          callback = function()
              if G_reader_settings then
                  local enabled = not self:autoSyncEnabled()
                  G_reader_settings:saveSetting("kindlespouse_auto_sync", enabled)
                  if enabled then os.remove(directory .. "pause.requested"); self:queueAutomaticSync() end
              end
          end },
        { text_func = function() return "Sync status: " .. self:summary(self:status()) end,
          callback = function() self:showStatus() end },
        { text = "Last result", callback = function() self:showStatus() end },
        { text = "Collect notebook titles", callback = function() self:collectTitles() end },
        { text = "Sync titles", callback = function() self:syncTitles() end },
        { text = "Apply pending annotation edits", callback = function() self:applyAnnotations() end },
        { text = "Use KindleSpouse sleep cover", checked_func = function() return G_reader_settings:readSetting("screensaver_type") == "customisable_ss" end,
          callback = function()
              local profile = readJSON("sleep-profile.json") or { version = 1, displayName = "Reader", avatar = "R" }
              profile.enabled = G_reader_settings:readSetting("screensaver_type") ~= "customisable_ss"
              local file = io.open(directory .. "sleep-profile.json.partial", "wb")
              if not file then self:notify("Cannot save sleep cover preference."); return end
              file:write(json.encode(profile)); file:close()
              os.rename(directory .. "sleep-profile.json.partial", directory .. "sleep-profile.json")
              self:setSleepCover(profile.enabled)
          end },
    } }
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
    if self.status_dialog then UIManager:close(self.status_dialog) end
end

return Companion
