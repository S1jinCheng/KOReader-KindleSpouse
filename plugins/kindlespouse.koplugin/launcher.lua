local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Launcher = {}
local modes = { full = true, books = true, updates = true, profile = true, titles = true }
local configured
local reserved
local sequence = 0

local function report(message)
    local log = configured and configured.logger or logger
    if log and log.warn then log.warn("KindleSpouse:", message) end
end

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
    return Launcher
end

function Launcher.reserve(mode)
    if not valid(mode) then return nil, "Unsupported synchronization mode" end
    if configured.status.workerRunning() then return nil, "Synchronization worker is already running" end
    if configured.status.launchMarker() then return nil, "Synchronization launch is already reserved" end
    sequence = sequence + 1
    local owner = string.format("%d-%d-%s", configured.now(), sequence, tostring({}):gsub("[^%w]", ""))
    local token = { owner = owner, mode = mode, startedAt = configured.now() }
    local temporary = configured.directory .. "sync.launching." .. owner .. ".partial"
    local stream, failure = io.open(temporary, "wb")
    if not stream then report("cannot write launch marker: " .. tostring(failure)); return nil, "Cannot reserve synchronization launch" end
    local written, write_error = stream:write(json.encode({ version = 1, owner = owner, mode = mode, startedAt = token.startedAt }))
    local closed, close_error = stream:close()
    if not written or not closed then
        os.remove(temporary)
        report("cannot save launch marker: " .. tostring(write_error or close_error))
        return nil, "Cannot save synchronization launch"
    end
    local renamed, rename_error = os.rename(temporary, markerPath())
    if not renamed then
        os.remove(temporary)
        report("cannot publish launch marker: " .. tostring(rename_error))
        return nil, "Cannot publish synchronization launch"
    end
    local marker = readMarker()
    if not marker or marker.owner ~= owner then return nil, "Synchronization launch ownership changed" end
    reserved = token
    return token
end

function Launcher.release(token)
    if not token then return end
    local marker = readMarker()
    if marker and marker.owner == token.owner then
        local removed, failure = os.remove(markerPath())
        if not removed then report("cannot remove owned launch marker: " .. tostring(failure)) end
    end
    if reserved == token then reserved = nil end
end

function Launcher.manual(mode)
    if not valid(mode) then return false, "Unsupported synchronization mode" end
    local flags = mode == "full" and { "pause.requested", "books-pause.requested" }
        or { mode == "updates" and "pause.requested" or mode .. "-pause.requested" }
    for _, name in ipairs(flags) do
        local filename = configured.directory .. name
        if lfs.attributes(filename, "mode") then
            local removed, failure = os.remove(filename)
            if not removed then report("cannot resume synchronization: " .. tostring(failure)); return false, "Cannot remove the requested pause flag" end
        end
    end
    return true
end

function Launcher.pause()
    for _, name in ipairs({ "pause.requested", "books-pause.requested", "profile-pause.requested", "titles-pause.requested" }) do
        local stream, failure = io.open(configured.directory .. name, "wb")
        if not stream then report("cannot save pause request: " .. tostring(failure)); return false end
        local written = stream:write("paused\n")
        local closed = stream:close()
        if not written or not closed then report("cannot finish pause request"); return false end
    end
    return true
end

function Launcher.launch(mode, manual, host)
    if not valid(mode) then return false, "Unsupported synchronization mode" end
    local token = reserved
    local marker = readMarker()
    if not token or token.mode ~= mode or not marker or marker.owner ~= token.owner then return false, "Synchronization launch reservation was lost" end
    if configured.now() - token.startedAt < 0 or configured.now() - token.startedAt >= 20 then return false, "Synchronization launch reservation expired" end
    if configured.status.workerRunning() then return false, "Synchronization worker is already running" end
    if configured.status.paused(mode) then return false, "Synchronization is paused" end
    if lfs.attributes(configured.directory .. "config.json", "mode") ~= "file" then return false, "Pair this Kindle before synchronizing" end
    if mode == "full" then
        if not host or type(host.saveReadingState) ~= "function" then report("cannot save reading state: current host is unavailable"); return false, "Cannot save reading state" end
        local ok, saved = pcall(host.saveReadingState, host)
        if not ok or not saved then report("cannot save reading state: " .. tostring(ok and "save failed" or saved)); return false, "Cannot save reading state" end
    end
    marker = readMarker()
    if not marker or marker.owner ~= token.owner or configured.status.workerRunning() then return false, "Synchronization launch ownership changed" end
    if configured.now() - token.startedAt < 0 or configured.now() - token.startedAt >= 20 then return false, "Synchronization launch reservation expired" end
    local command = "sh " .. quote(configured.directory .. "sync.sh") .. (mode == "full" and "" or " " .. quote(mode))
        .. " < /dev/null > /dev/null 2>&1 &"
    local ok, result = pcall(configured.execute, command)
    if not ok or result ~= 0 and result ~= true then report("cannot launch synchronization: " .. tostring(result)); return false, "Cannot start synchronization worker" end
    return true
end

return Launcher
