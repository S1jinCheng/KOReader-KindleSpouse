local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local T = require("i18n").T
local Launcher = {}
local modes = { full = true, books = true, updates = true, profile = true, titles = true }
local configured
local reserved
local sequence = 0

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function valid(mode)
    return type(mode) == "string" and modes[mode] == true
end

local function markerPath()
    return configured.directory .. "sync.launching"
end

local function readMarker()
    return configured.status.readJSON("sync.launching")
end

function Launcher.configure(options)
    local directory = options.directory or "/mnt/us/kindlespouse/"
    assert(type(directory) == "string" and directory:sub(1, 1) == "/" and not directory:find("[%c\\]"), "Invalid synchronization directory")
    for part in directory:gmatch("[^/]+") do assert(part ~= "." and part ~= "..", "Invalid synchronization directory") end
    configured = { directory = directory:gsub("/+$", "") .. "/", status = assert(options.status),
        now = options.now or os.time, execute = options.execute or os.execute, logger = options.logger or logger }
    logger = options.logger or logger
    return Launcher
end

function Launcher.reserve(mode)
    if not valid(mode) then return nil, T("launcher_mode") end
    if configured.status.workerRunning() then return nil, T("launcher_running") end
    if configured.status.launchMarker() then return nil, T("launcher_reserved") end
    sequence = sequence + 1
    local owner = string.format("%d-%d-%s", configured.now(), sequence, tostring({}):gsub("[^%w]", ""))
    local token = { owner = owner, mode = mode, startedAt = configured.now() }
    local temporary = configured.directory .. "sync.launching." .. owner .. ".partial"
    local stream, failure = io.open(temporary, "wb")
    if not stream then logger.warn("KindleSpouse:", "cannot write launch marker: " .. tostring(failure)); return nil, T("launcher_reserve_failed") end
    local written, write_error = stream:write(json.encode({ version = 1, owner = owner, mode = mode, startedAt = token.startedAt }))
    local closed, close_error = stream:close()
    if not written or not closed then
        os.remove(temporary)
        logger.warn("KindleSpouse:", "cannot save launch marker: " .. tostring(write_error or close_error))
        return nil, T("launcher_save_failed")
    end
    local renamed, rename_error = os.rename(temporary, markerPath())
    if not renamed then
        os.remove(temporary)
        logger.warn("KindleSpouse:", "cannot publish launch marker: " .. tostring(rename_error))
        return nil, T("launcher_publish_failed")
    end
    local marker = readMarker()
    if not marker or marker.owner ~= owner then return nil, T("launcher_owner_changed") end
    reserved = token
    return token
end

function Launcher.release(token)
    if not token then return end
    local marker = readMarker()
    if marker and marker.owner == token.owner then
        local removed, failure = os.remove(markerPath())
        if not removed then logger.warn("KindleSpouse:", "cannot remove owned launch marker: " .. tostring(failure)) end
    end
    if reserved == token then reserved = nil end
end

function Launcher.manual(mode)
    if not valid(mode) then return false, T("launcher_mode") end
    local flags = mode == "full" and { "pause.requested", "books-pause.requested" }
        or { mode == "updates" and "pause.requested" or mode .. "-pause.requested" }
    for _, name in ipairs(flags) do
        local filename = configured.directory .. name
        if lfs.attributes(filename, "mode") then
            local removed, failure = os.remove(filename)
            if not removed then logger.warn("KindleSpouse:", "cannot resume synchronization: " .. tostring(failure)); return false, T("launcher_resume_failed") end
        end
    end
    return true
end

function Launcher.pause()
    for _, name in ipairs({ "pause.requested", "books-pause.requested", "profile-pause.requested", "titles-pause.requested" }) do
        local stream, failure = io.open(configured.directory .. name, "wb")
        if not stream then logger.warn("KindleSpouse:", "cannot save pause request: " .. tostring(failure)); return false, T("pause_save_failed") end
        local written = stream:write("paused\n")
        local closed = stream:close()
        if not written or not closed then logger.warn("KindleSpouse:", "cannot finish pause request"); return false, T("pause_save_failed") end
    end
    return true
end

function Launcher.launch(mode, manual, host)
    if not valid(mode) then return false, T("launcher_mode") end
    local token = reserved
    local marker = readMarker()
    if not token or token.mode ~= mode or not marker or marker.owner ~= token.owner then return false, T("launcher_reservation_lost") end
    if configured.now() - token.startedAt < 0 or configured.now() - token.startedAt >= 20 then return false, T("launcher_expired") end
    if configured.status.workerRunning() then return false, T("launcher_running") end
    if configured.status.paused(mode) then return false, T("launcher_paused") end
    if lfs.attributes(configured.directory .. "config.json", "mode") ~= "file" then return false, T("launcher_pair_first") end
    if mode == "full" then
        if not host or type(host.saveReadingState) ~= "function" then logger.warn("KindleSpouse:", "cannot save reading state: current host is unavailable"); return false, T("launcher_reading_failed") end
        local ok, saved = pcall(host.saveReadingState, host)
        if not ok or not saved then logger.warn("KindleSpouse:", "cannot save reading state: " .. tostring(ok and "save failed" or saved)); return false, T("launcher_reading_failed") end
    end
    marker = readMarker()
    if not marker or marker.owner ~= token.owner or configured.status.workerRunning() then return false, T("launcher_owner_changed") end
    if configured.now() - token.startedAt < 0 or configured.now() - token.startedAt >= 20 then return false, T("launcher_expired") end
    local command = "sh " .. quote(configured.directory .. "sync.sh") .. (mode == "full" and "" or " " .. quote(mode))
        .. " < /dev/null > /dev/null 2>&1 &"
    local ok, result = pcall(configured.execute, command)
    if not ok or result ~= 0 and result ~= true then logger.warn("KindleSpouse:", "cannot launch synchronization: " .. tostring(result)); return false, T("launcher_start_failed") end
    return true
end

return Launcher
