local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local Extractor = { pending = {}, sequence = 0 }
local manager
local pump

local function backend()
    if not manager then manager = require("bookinfomanager") end
    return manager
end

local function attributes(filepath)
    local attr = lfs.symlinkattributes(filepath)
    return attr and attr.mode == "file" and attr or nil
end

function Extractor.isFresh(info, attr)
    return info ~= nil and attr ~= nil and tonumber(info.filesize) == attr.size
        and tonumber(info.filemtime) == attr.modification
end

function Extractor.cached(filepath)
    return backend():getBookInfo(filepath, false)
end

function Extractor.needs(info, attr, specs)
    if not attr or info and info._no_provider then return false end
    if not Extractor.isFresh(info, attr) then return true end
    if info.unsupported or not specs or info.ignore_cover then return false end
    if not info.cover_fetched then return true end
    if not info.has_cover then return false end
    if type(info.cover_sizetag) ~= "string" then return true end
    return backend().isCachedCoverInvalid(info, specs) == true
end

local function mergeSpecs(left, right)
    if not right then return left end
    return { max_cover_w = math.max(left and left.max_cover_w or 0, right.max_cover_w),
        max_cover_h = math.max(left and left.max_cover_h or 0, right.max_cover_h) }
end

local function notify(request, info, status)
    for _, callback in pairs(request.owners) do
        if callback then callback(request.filepath, info, status) end
    end
end

local function schedule(delay)
    if Extractor.scheduled then return end
    Extractor.scheduled = true
    UIManager:scheduleIn(delay or 0.01, pump)
end

local function put(request)
    local existing = Extractor.pending[request.filepath]
    if existing then
        existing.cover_specs = mergeSpecs(existing.cover_specs, request.cover_specs)
        existing.attempts = math.max(existing.attempts, request.attempts)
        for owner, callback in pairs(request.owners) do existing.owners[owner] = callback end
    elseif next(request.owners) then
        Extractor.pending[request.filepath] = request
    end
end

function Extractor.enqueue(owner, files, callback)
    assert(owner ~= nil)
    for _, file in ipairs(files) do
        local filepath = file.filepath
        local active = Extractor.active and Extractor.active.by_path[filepath]
        local requested = file.cover_specs
        if active and (not requested or active.cover_specs
                and active.cover_specs.max_cover_w >= requested.max_cover_w
                and active.cover_specs.max_cover_h >= requested.max_cover_h) then
            active.owners[owner] = callback or false
        else
            Extractor.sequence = Extractor.sequence + 1
            put { filepath = filepath, cover_specs = mergeSpecs(nil, requested),
                owners = { [owner] = callback or false }, sequence = Extractor.sequence, attempts = 0 }
        end
    end
    schedule()
end

function Extractor.cancel(owner)
    for filepath, request in pairs(Extractor.pending) do
        request.owners[owner] = nil
        if not next(request.owners) then Extractor.pending[filepath] = nil end
    end
    if Extractor.active then
        for _, request in ipairs(Extractor.active.requests) do request.owners[owner] = nil end
    end
    if not Extractor.active and not next(Extractor.pending) then
        UIManager:unschedule(pump)
        Extractor.scheduled = false
    end
end

local function complete(active)
    for _, request in ipairs(active.requests) do
        local attr = attributes(request.filepath)
        local info = attr and Extractor.cached(request.filepath)
        local same = attr and attr.size == request.size and attr.modification == request.mtime
        if same and info and (Extractor.isFresh(info, attr) or info.unsupported) and next(request.preferences) then
            backend():setBookInfoProperties(request.filepath, request.preferences)
            info = Extractor.cached(request.filepath)
        end
        if next(request.owners) then
            if same and info and (Extractor.isFresh(info, attr) or info.unsupported)
                    and (not Extractor.needs(info, attr, request.cover_specs) or info.unsupported) then
                notify(request, info, info.unsupported and "unsupported" or "ready")
            elseif attr and request.attempts < 3 then
                put(request)
            else
                notify(request, info, attr and "failed" or "missing")
            end
        end
    end
end

pump = function()
    Extractor.scheduled = false
    local current = backend()
    if Extractor.active then
        local done = true
        for _, pid in ipairs(Extractor.active.pids) do
            if not ffiUtil.isSubProcessDone(pid) then done = false end
        end
        if not done then schedule(0.2); return end
        current:collectSubprocesses()
        local active = Extractor.active
        Extractor.active = nil
        complete(active)
    end
    if not next(Extractor.pending) then return end
    if current:isExtractingInBackground() then schedule(0.2); return end
    local queued = {}
    for _, request in pairs(Extractor.pending) do queued[#queued + 1] = request end
    table.sort(queued, function(left, right)
        if (left.cover_specs ~= nil) ~= (right.cover_specs ~= nil) then return left.cover_specs ~= nil end
        return left.sequence < right.sequence
    end)
    local requests, files, by_path = {}, {}, {}
    for index, request in ipairs(queued) do
        if index > 50 then break end
        Extractor.pending[request.filepath] = nil
        local attr = attributes(request.filepath)
        local info = attr and Extractor.cached(request.filepath)
        if not attr then
            notify(request, nil, "missing")
        elseif not Extractor.needs(info, attr, request.cover_specs) then
            notify(request, info, info and info.unsupported and "unsupported" or "ready")
        else
            if not request.cover_specs and info and info.cover_fetched and info.has_cover then
                request.cover_specs = { max_cover_w = tonumber(info.cover_w) or 1,
                    max_cover_h = tonumber(info.cover_h) or 1 }
            end
            request.preferences = request.preferences or {}
            for _, name in ipairs({ "ignore_meta", "ignore_cover" }) do
                if info and info[name] then request.preferences[name] = info[name] end
            end
            request.size, request.mtime = attr.size, attr.modification
            request.attempts = request.attempts + 1
            requests[#requests + 1] = request
            files[#files + 1] = { filepath = request.filepath, cover_specs = request.cover_specs }
            by_path[request.filepath] = request
        end
    end
    if #files == 0 then
        if next(Extractor.pending) then schedule() end
        return
    end
    if current:extractInBackground(files) then
        local pids = {}
        for _, pid in ipairs(current.subprocesses_pids) do pids[#pids + 1] = pid end
        Extractor.active = { requests = requests, by_path = by_path, pids = pids }
        schedule(0.2)
    else
        for _, request in ipairs(requests) do
            if request.attempts < 3 then put(request) else notify(request, nil, "failed") end
        end
        if next(Extractor.pending) then schedule(0.25) end
    end
end

function Extractor.poll()
    UIManager:unschedule(pump)
    pump()
end

function Extractor.isBusy()
    return Extractor.active ~= nil or next(Extractor.pending) ~= nil
end

return Extractor
