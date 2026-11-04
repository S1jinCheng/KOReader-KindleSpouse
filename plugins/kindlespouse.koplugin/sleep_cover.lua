local UIManager = require("ui/uimanager")
local Status = require("sync_status")
local T = require("i18n").T
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local Sleep = {}
local dependencies = {}
local warned_missing, missing, requested = false, false, false
local prepare_task

local function settings()
    return dependencies.settings or G_reader_settings
end

local function logger()
    return dependencies.logger or require("logger")
end

local function preset()
    local ok, value = pcall(dependencies.require_preset or require, "spouse_preset")
    if not ok or type(value) ~= "table" or type(value.prepare) ~= "function" then
        missing = true
        if not warned_missing then
            warned_missing = true
            logger().warn("KindleSpouse:", "sleep cover preset is not installed")
        end
        return
    end
    missing = false
    return value
end

function Sleep.configure(options)
    Sleep.cancel()
    dependencies = options or {}
    requested = settings() and settings():readSetting("screensaver_type") == "customisable_ss" or false
    return Sleep
end

local function setEnabled(enabled, validated)
    if type(enabled) ~= "boolean" or not settings() then return false end
    requested = enabled
    local current = settings():readSetting("screensaver_type")
    if enabled then
        if not validated and not preset() then return false end
        if current ~= "customisable_ss" then settings():saveSetting("kindlespouse_previous_screensaver", current or "cover") end
        settings():saveSetting("screensaver_type", "customisable_ss")
    else
        Sleep.cancel()
        if current == "customisable_ss" then
            settings():saveSetting("screensaver_type", settings():readSetting("kindlespouse_previous_screensaver", "cover"))
        end
    end
    return true
end

function Sleep.setEnabled(enabled)
    return setEnabled(enabled, false)
end

function Sleep.savePreference(enabled, options)
    if type(enabled) ~= "boolean" or not settings() then return false end
    requested = enabled
    if enabled and not preset() then return false end
    local directory = options and options.directory or (dependencies.status or Status).directory
    if type(directory) ~= "string" or directory == "" or directory:find("%c") then return false end
    local destination = directory:gsub("/+$", "") .. "/sleep-profile.json"
    local profile = { version = 1, displayName = "Reader", avatar = "R" }
    local stream = io.open(destination, "rb")
    if stream then
        local bytes = stream:read(65537)
        stream:close()
        local ok, value = pcall(json.decode, bytes or "")
        if not bytes or #bytes > 65536 or not ok or type(value) ~= "table" or value.version ~= 1 then
            logger().warn("KindleSpouse:", "cannot save sleep preference: invalid existing profile")
            return false
        end
        profile = value
    elseif lfs.attributes(destination, "mode") then
        logger().warn("KindleSpouse:", "cannot read existing sleep preference")
        return false
    end
    profile.enabled = enabled
    local encoded, bytes = pcall(json.encode, profile)
    if not encoded or #bytes > 65536 then return false end
    local temporary = destination .. "." .. tostring({}):gsub("[^%w]", "") .. ".partial"
    local target, failure = io.open(temporary, "wb")
    if not target then logger().warn("KindleSpouse:", "cannot write sleep preference", tostring(failure)); return false end
    local written, write_error = target:write(bytes)
    local closed, close_error = target:close()
    if not written or not closed then
        os.remove(temporary)
        logger().warn("KindleSpouse:", "cannot finish sleep preference", tostring(write_error or close_error))
        return false
    end
    local renamed, rename_error = os.rename(temporary, destination)
    if not renamed then
        os.remove(temporary)
        logger().warn("KindleSpouse:", "cannot publish sleep preference", tostring(rename_error))
        return false
    end
    if not setEnabled(enabled, true) then return false end
    if enabled then Sleep.prepare() end
    return true
end

prepare_task = function()
    local reader
    if dependencies.reader then reader = dependencies.reader()
    else
        local module = package.loaded["apps/reader/readerui"]
        reader = module and module.instance
    end
    if not reader or not reader.document or not settings() or settings():readSetting("screensaver_type") ~= "customisable_ss" then return end
    local value = preset()
    if not value then return end
    local ok, failure = pcall(value.prepare, reader)
    if not ok then logger().warn("KindleSpouse:", "sleep cover preparation failed", tostring(failure)) end
end

function Sleep.prepare()
    if not settings() or settings():readSetting("screensaver_type") ~= "customisable_ss" then return false end
    if not preset() then return false end
    Sleep.cancel()
    local schedule = dependencies.schedule or function(delay, action) UIManager:scheduleIn(delay, action) end
    schedule(0.5, prepare_task)
    return true
end

function Sleep.cancel()
    local unschedule = dependencies.unschedule or function(action) UIManager:unschedule(action) end
    unschedule(prepare_task)
end

function Sleep.applyProfile()
    local status = dependencies.status or Status
    local profile = status.readJSON("sleep-profile.json")
    if not profile or profile.version ~= 1 or type(profile.revision) ~= "string" or profile.revision == ""
            or type(profile.enabled) ~= "boolean" or not settings() then return false end
    requested = profile.enabled
    if settings():readSetting("kindlespouse_sleep_revision") == profile.revision then return true end
    if not Sleep.setEnabled(profile.enabled) then return false end
    settings():saveSetting("kindlespouse_sleep_revision", profile.revision)
    if profile.enabled then Sleep.prepare() end
    return true
end

function Sleep.warning()
    if requested or settings() and settings():readSetting("screensaver_type") == "customisable_ss" then
        if not missing then preset() end
        if missing then return T("sleep_missing") end
    end
end

return Sleep
