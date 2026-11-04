local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Status = require("sync_status")
local T = require("i18n").T
local Menu = {}

local function call(host, name, ...)
    if type(host[name]) == "function" then return host[name](host, ...) end
end

local function read(key, default)
    if not G_reader_settings then return default end
    return G_reader_settings:readSetting(key, default)
end

local function progress(host)
    return call(host, "status") or Status.snapshot()
end

local function summary(host, value)
    return call(host, "summary", value) or Status.summary(value)
end

local function statusText(host)
    local value = progress(host)
    local text = summary(host, value)
    local sleep = package.loaded.sleep_cover
    local warning = sleep and sleep.warning() or call(host, "sleepWarning")
    if warning then text = text .. "\n\n" .. warning end
    local hint = (value.state == "running" or value.state == "pausing") and T("sync_background_hint") or ""
    return text .. "\n\n" .. hint .. T("tap_return")
end

function Menu.closeStatus(host)
    local session = host.kindlespouse_status_session
    if not session then return end
    host.kindlespouse_status_session, host.status_dialog = nil, nil
    UIManager:unschedule(session.refresh)
    if session.dialog then UIManager:close(session.dialog) end
end

function Menu.showStatus(host)
    Menu.closeStatus(host)
    local session = {}
    host.kindlespouse_status_session = session
    local function replace(text)
        local previous = session.dialog
        local dialog
        dialog = InfoMessage:new { text = text, show_icon = false,
            dismiss_callback = function()
                if host.kindlespouse_status_session == session and session.dialog == dialog then
                    host.kindlespouse_status_session, host.status_dialog = nil, nil
                    UIManager:unschedule(session.refresh)
                end
            end }
        session.dialog, session.text, host.status_dialog = dialog, text, dialog
        if previous then UIManager:close(previous) end
        UIManager:show(dialog)
    end
    session.refresh = function()
        if host.kindlespouse_status_session ~= session then return end
        if host.suspended then Menu.closeStatus(host); return end
        local text = statusText(host)
        if text ~= session.text then replace(text) end
        UIManager:scheduleIn(3, session.refresh)
    end
    replace(statusText(host))
    UIManager:scheduleIn(3, session.refresh)
    return session.dialog
end

function Menu.build(host)
    local function action(id, key, method, ...)
        local args = { ... }
        return { id = id, text = T(key), callback = function() return call(host, method, unpack(args)) end }
    end
    local function atHome()
        return host.ui ~= nil and not host.ui.document
    end
    local entries = {
        { id = "sync", text_func = function() return T(Status.paused("full") and "sync_resume" or "sync_now") end,
            callback = function() return call(host, "sync", false) end },
        { id = "pause", text = T("sync_pause"), enabled_func = function() return Status.isRunning() end,
            callback = function() return call(host, "pause") end },
        { id = "status", text_func = function() return T("sync_status_label", summary(host, progress(host))) end,
            callback = function() if host.showStatus then return host:showStatus() end; return Menu.showStatus(host) end },
        { id = "auto_sync", text = T("auto_sync"), checked_func = function()
                local enabled = call(host, "autoSyncEnabled")
                if enabled ~= nil then return enabled end
                return read("kindlespouse_auto_sync", true) ~= false
            end,
            callback = function()
                return call(host, "setAutoSyncEnabled", read("kindlespouse_auto_sync", true) == false)
            end },
        { id = "auto_receive", text = T("auto_receive"), checked_func = function() return read("kindlespouse_auto_receive", true) ~= false end,
            callback = function() return call(host, "setAutoReceiveEnabled", read("kindlespouse_auto_receive", true) == false) end },
        { id = "refresh", text = T("refresh_library"), enabled_func = atHome,
            callback = function() return call(host, "refreshLibrary") end },
        { id = "home", text = T("home_enabled"), enabled_func = atHome,
            checked_func = function() return read("kindlespouse_home", true) ~= false end,
            callback = function()
                if not atHome() then return end
                if host.toggleHome then return host:toggleHome() end
                return require("home").toggle(host)
            end },
        { id = "sleep_cover", text = T("sleep_cover"), checked_func = function() return read("screensaver_type") == "customisable_ss" end,
            callback = function() return call(host, host.saveSleepPreference and "saveSleepPreference" or "setSleepCover", read("screensaver_type") ~= "customisable_ss") end },
    }
    if type(host.readerMenuItems) == "function" then
        local reader_items = host:readerMenuItems()
        if reader_items and #reader_items > 0 then
            entries[#entries + 1] = { id = "reading_experience", text = T("reading_experience"), sub_item_table = reader_items }
        end
    end
    entries[#entries + 1] = { id = "advanced", text = T("advanced"), sub_item_table = {
        { id = "profile", text = T("profile_sync"), callback = function()
            if host.openProfile then return host:openProfile() end
            return require("profile").open(host)
        end },
        action("sync_profile", "sync_profile", "syncProfile"),
        action("receive_books", "receive_books", "receiveBooks", false),
        action("collect_titles", "collect_titles", "collectTitles"),
        action("sync_titles", "sync_titles", "syncTitles"),
        action("apply_edits", "apply_edits", "applyAnnotations"),
    } }
    return { text = "KindleSpouse", sub_item_table = entries }
end

return Menu
