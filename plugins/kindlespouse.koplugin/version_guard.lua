local logger = require("logger")
local Patches = require("patches")
local Version = require("version")
local Guard = { supported_version = 202607010000 }
local disabled, warned, reason = false, false, nil
local prefixes = { "home:", "reader:", "menu:", "library:", "notebook:", "profile:", "kindlespouse:" }

local function owned(id)
    if type(id) ~= "string" then return false end
    for _, prefix in ipairs(prefixes) do
        if id:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function rollback()
    for index = #Patches.order, 1, -1 do
        local id = Patches.order[index]
        if owned(id) then
            local ok, error = pcall(Patches.revert, id)
            if not ok then logger.err("KindleSpouse:", "cannot restore interface patch", id, tostring(error)) end
        end
    end
end

local function warning(message, key)
    if warned then return end
    warned = true
    logger.warn("KindleSpouse:", message)
    local manager = package.loaded["ui/uimanager"]
    if type(manager) ~= "table" or type(manager.scheduleIn) ~= "function" then return end
    manager:scheduleIn(0.1, function()
        local shown, error = pcall(function()
            local text = "The KindleSpouse interface is disabled. Synchronization remains available."
            local translated, i18n = pcall(require, "i18n")
            if translated and type(i18n) == "table" and type(i18n.T) == "function" then text = i18n.T(key) end
            manager:show(require("ui/widget/infomessage"):new { text = text })
        end)
        if not shown then logger.err("KindleSpouse:", "cannot display interface compatibility notice", tostring(error)) end
    end)
end

function Guard.isSupported()
    if type(Version.getNormalizedCurrentVersion) ~= "function" then return false end
    local ok, current = pcall(Version.getNormalizedCurrentVersion, Version)
    return ok and current == Guard.supported_version, ok and current or nil
end

function Guard.status()
    local supported, current = Guard.isSupported()
    return { supported = supported, disabled = disabled, version = current, reason = reason }
end

function Guard.run(install, ...)
    if disabled then rollback(); return false, reason end
    local supported, current = Guard.isSupported()
    if not supported then
        disabled = true
        reason = "unsupported KOReader version (normalized " .. tostring(current or "unknown") .. "); expected v2026.07.1"
        rollback()
        warning(reason, "version.unsupported")
        return false, reason
    end
    local function results(...) return { n = select("#", ...), ... } end
    local outcome = results(pcall(install, ...))
    if not outcome[1] then
        disabled = true
        reason = "interface installation failed: " .. tostring(outcome[2])
        rollback()
        warning(reason, "version.install_failed")
        return false, reason
    end
    return unpack(outcome, 1, outcome.n)
end

function Guard.install(ui, install)
    return Guard.run(install, ui)
end

return Guard