local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local logger = require("logger")
local I18n = require("i18n")
local T = I18n.T
local Status = { directory = "/mnt/us/kindlespouse/" }
local clock = os.time
local proc_directory = "/proc/"
local warned = {}
local observed, last_identity, launching = false, nil, nil
local states = { idle = true, running = true, completed = true, failed = true, paused = true, pausing = true }
local modes = { full = true, books = true, profile = true, titles = true, updates = true }
local pause_files = { full = "pause.requested", books = "books-pause.requested", profile = "profile-pause.requested",
    titles = "titles-pause.requested", updates = "pause.requested" }

local function slash(value)
    return value:gsub("/+$", "") .. "/"
end

function Status.configure(options)
    options = options or {}
    if options.directory then
        local directory = slash(options.directory)
        if directory ~= Status.directory then observed, last_identity, launching = false, nil, nil end
        Status.directory = directory
    end
    clock = options.now or os.time
    proc_directory = slash(options.proc_directory or "/proc")
    logger = options.logger or require("logger")
    return Status
end

local function warning(name, reason)
    local key = Status.directory .. name
    if warned[key] then return end
    warned[key] = true
    logger.warn("KindleSpouse:", "cannot read local JSON", name, reason)
end

function Status.readJSON(name, limit)
    assert(type(name) == "string" and name:match("^[%w_.%-]+$"))
    limit = limit or 65536
    assert(limit > 0 and limit <= 1048576)
    local stream = io.open(Status.directory .. name, "rb")
    if not stream then return end
    local bytes = stream:read(limit + 1)
    stream:close()
    if not bytes or bytes == "" then warning(name, "empty file"); return end
    if #bytes > limit then warning(name, "size limit exceeded"); return end
    local ok, value = pcall(json.decode, bytes)
    if ok and type(value) == "table" then return value end
    warning(name, "invalid JSON object")
end

local function number(value)
    local result = tonumber(value)
    if result and result == result and result >= 0 and result < math.huge then return result end
end

local function isoSeconds(value)
    if type(value) ~= "string" then return end
    local year, month, day, hour, minute, second = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)")
    local suffix = value:sub(20)
    if not year or suffix ~= "Z" and not suffix:match("^%.%d+Z$") then return end
    year, month, day, hour, minute, second = tonumber(year), tonumber(month), tonumber(day), tonumber(hour), tonumber(minute), tonumber(second)
    if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 59 then return end
    local adjusted = year - (month <= 2 and 1 or 0)
    local era = math.floor(adjusted / 400)
    local within = adjusted - era * 400
    local shifted = month + (month > 2 and -3 or 9)
    local days = math.floor((153 * shifted + 2) / 5) + day - 1
    local epoch = (era * 146097 + within * 365 + math.floor(within / 4) - math.floor(within / 100) + days - 719468) * 86400
        + hour * 3600 + minute * 60 + second
    if os.date("!%Y-%m-%dT%H:%M:%S", epoch) == value:sub(1, 19) then return epoch end
end

local function mode(value)
    if modes[value.mode] then return value.mode end
    if value.booksOnly == true then return "books" end
    if value.profileOnly == true then return "profile" end
    if value.titlesOnly == true then return "titles" end
    if value.updatesOnly == true then return "updates" end
    return "full"
end

local function normalized(value)
    local result = { state = states[value.state] and value.state or "idle", mode = mode(value) }
    for _, name in ipairs({ "startedAt", "updatedAt", "completedAt", "done", "total", "bytes", "totalBytes", "speed", "received", "files", "pid" }) do
        result[name] = number(value[name])
    end
    for _, name in ipairs({ "stage", "error", "profileRoute", "runId" }) do
        if type(value[name]) == "string" then result[name] = value[name] end
    end
    result.booksOnly, result.profileOnly = result.mode == "books", result.mode == "profile"
    result.titlesOnly, result.updatesOnly = result.mode == "titles", result.mode == "updates"
    return result
end

function Status.workerRunning()
    local lock = io.open(Status.directory .. "sync.lock", "rb")
    if not lock then return false end
    local bytes = lock:read(33)
    lock:close()
    local pid = bytes and #bytes <= 32 and bytes:match("^(%d+)%s*$")
    if not pid then return false end
    local stream = io.open(proc_directory .. pid .. "/cmdline", "rb")
    if not stream then return false end
    local command = stream:read(4096)
    stream:close()
    return command ~= nil and command:find("kindlespouse-sync", 1, true) ~= nil, tonumber(pid)
end

function Status.launchMarker()
    local stream = io.open(Status.directory .. "sync.launching", "rb")
    if not stream then return end
    local bytes = stream:read(65537)
    stream:close()
    if not bytes or #bytes > 65536 then return end
    local ok, marker = pcall(json.decode, bytes)
    if not ok or type(marker) ~= "table" then
        marker = { startedAt = number(bytes and bytes:match("^%s*(%d+)%s*$")) }
    end
    local started = number(marker.startedAt or marker.createdAt) or lfs.attributes(Status.directory .. "sync.launching", "modification")
    if not started or started > clock() or clock() - started >= 20 then return end
    return { startedAt = started, mode = modes[marker.mode] and marker.mode or "full",
        owner = type(marker.owner) == "string" and marker.owner or nil }
end

function Status.isRunning()
    return Status.workerRunning() or Status.launchMarker() ~= nil
end

function Status.paused(selected)
    return lfs.attributes(Status.directory .. (pause_files[selected or "full"] or pause_files.full), "mode") ~= nil
end

local function finalResult(result)
    if not result or type(result.ok) ~= "boolean" then return end
    local value = normalized(result)
    value.state = result.paused and "paused" or result.ok and "completed" or "failed"
    value.completedAt = number(result.completedAt) or isoSeconds(result.completedAt)
    if type(result.completedAt) == "string" and isoSeconds(result.completedAt) then value.runId = result.completedAt end
    return value
end

function Status.snapshot()
    local raw = Status.readJSON("progress.json")
    local final = finalResult(Status.readJSON("last-result.json"))
    local value = raw and states[raw.state] and normalized(raw) or final or { state = "idle", mode = "full" }
    local running, pid = Status.workerRunning()
    local marker = Status.launchMarker()
    if final and final.runId and (value.state == "completed" or value.state == "failed")
            and final.state == value.state and final.completedAt == value.completedAt
            and (not value.startedAt or final.completedAt >= value.startedAt)
            and (final.mode == value.mode or final.state == "failed") then
        value.runId = final.runId
    end
    if marker then
        local identity = marker.owner or tostring(marker.startedAt) .. ":" .. marker.mode
        if not launching or launching.identity ~= identity then
            launching = { identity = identity, baseline = last_identity, observed = observed }
        end
    else
        launching = nil
    end
    local completed_launch = marker and launching.observed and value.runId and value.runId ~= launching.baseline
        and (value.state == "completed" or value.state == "failed") and value.mode == marker.mode
        and value.startedAt and value.startedAt >= marker.startedAt
    if marker and not running and not completed_launch then
        value = normalized { state = "running", mode = marker.mode, startedAt = marker.startedAt, stage = "checking_pairing" }
        value.launching = true
        value.launchOwner = marker.owner
    elseif running and value.state ~= "running" and value.state ~= "pausing" then
        value = normalized { state = "running", mode = marker and marker.mode or value.mode,
            startedAt = marker and marker.startedAt, stage = "checking_pairing", pid = pid }
    elseif value.state == "running" or value.state == "pausing" then
        if not running then
            value.state, value.error = "failed", "Sync was interrupted. Connect Wi-Fi and select Sync now to retry."
        end
    end
    if running then value.pid = pid end
    if Status.paused(value.mode) then value.state = running and "pausing" or "paused" end
    if not marker or completed_launch then observed = true end
    if value.runId and (value.state == "completed" or value.state == "failed") then last_identity = value.runId end
    return value
end

function Status.summary(value)
    value = value or Status.snapshot()
    if value.state == "paused" then return T("sync_paused") end
    if value.state == "pausing" then return T("sync_pausing") end
    if value.state == "idle" then return T("sync_idle") end
    if value.state == "completed" then
        local selected = mode(value)
        if selected == "updates" then return T("sync_updates_complete") end
        if selected == "books" then return T("sync_books_complete", math.floor(number(value.received) or 0)) end
        if selected == "profile" then return T(value.profileRoute == "lan" and "sync_profile_lan_complete" or "sync_profile_cloud_complete") end
        if selected == "titles" then return T("sync_titles_complete") end
        return T("sync_complete", math.floor(number(value.received) or 0), math.floor(number(value.files) or 0))
    end
    if value.state == "failed" then
        local error = value.error and (I18n.keys[value.error] and T(value.error) or value.error) or T("sync_retry_hint")
        return T("sync_stopped", error)
    end
    local stage = "stage_" .. tostring(value.stage or "")
    local text = T(I18n.en[stage] and stage or "sync_starting")
    local done, total = number(value.done) or 0, number(value.total) or 0
    if total > 0 then text = text .. string.format(" (%d/%d)", done, total)
    elseif done > 0 then text = text .. T("sync_file_count", done) end
    local bytes, total_bytes, speed = number(value.bytes) or 0, number(value.totalBytes) or 0, number(value.speed) or 0
    if total_bytes > 0 then text = text .. string.format(" · %.1f/%.1f MiB", bytes / 1048576, total_bytes / 1048576) end
    if speed > 0 then text = text .. string.format(" · %.0f KiB/s", speed / 1024) end
    local started = number(value.startedAt)
    if started then
        local elapsed = math.max(0, (number(value.completedAt) or clock()) - started)
        text = text .. T("sync_elapsed", math.floor(elapsed / 60), elapsed % 60)
    end
    return text
end

return Status
