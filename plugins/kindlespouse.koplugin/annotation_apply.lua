local logger = require("logger")
local M = {}

local function matches(item, expected)
    return type(item) == "table" and (item.text or "") == expected.text and (item.note or "") == expected.note
        and (item.datetime or "") == expected.datetime
        and (type(item.pos0) == "string" and item.pos0 or "") == expected.pos0
        and (type(item.pos1) == "string" and item.pos1 or "") == expected.pos1
        and (not expected.page or (item.pageno or item.page) == expected.page)
end

local function unique(items, expected)
    if type(items) ~= "table" then return end
    local found
    for index, item in ipairs(items) do
        if matches(item, expected) then
            if found then return end
            found = index
        end
    end
    return found
end

local function change(items, index, job)
    if job.operation == "delete" then table.remove(items, index)
    else
        items[index].note = job.note ~= "" and job.note or nil
        items[index].datetime_updated = os.date("%Y-%m-%d %H:%M:%S")
    end
end

function M.apply(settings, job)
    local completed = settings:readSetting("kindlespouse_applied_jobs") or {}
    if type(completed) ~= "table" then return "conflict" end
    if completed[job.jobId] then return "applied" end
    local annotations = settings:readSetting("annotations")
    local index = unique(annotations, job.expected)
    if not index or not (job.operation == "delete" or job.operation == "edit" and type(job.note) == "string") then return "conflict" end
    change(annotations, index, job)
    local alternate
    for _, name in ipairs({ "annotations_paging", "annotations_rolling" }) do
        local items = settings:readSetting(name)
        if items ~= nil then
            local other = unique(items, job.expected)
            if other then change(items, other, job); settings:saveSetting(name, items)
            else alternate = "skipped" end
        end
    end
    completed[job.jobId] = true
    settings:saveSetting("annotations", annotations)
    settings:saveSetting("kindlespouse_applied_jobs", completed)
    return "applied", alternate
end

local function read(file, limit)
    local stream = io.open(file, "rb")
    if not stream then return end
    local value = stream:read(limit + 1)
    stream:close()
    if not value or #value > limit then return end
    return value
end

local function write(file, value)
    local stream, error = io.open(file .. ".partial", "wb")
    if not stream then return nil, error end
    local ok = stream:write(value)
    local closed = stream:close()
    if not ok or not closed then return nil, "cannot write result" end
    return os.rename(file .. ".partial", file)
end

function M.run(directory, mount)
    local reader = package.loaded["apps/reader/readerui"]
    if reader and reader.instance then return 0 end
    mount = mount or "/mnt/us"
    local lfs = require("libs/libkoreader-lfs")
    local json = require("json")
    local util = require("util")
    local function safe(relative)
        if type(relative) ~= "string" or relative:find("[\\:%c]") or not (relative:match("^Books/") or relative:match("^documents/")) then return false end
        local current = mount
        for part in relative:gmatch("[^/]+") do
            if part == "." or part == ".." then return false end
            current = current .. "/" .. part
            if lfs.symlinkattributes(current, "mode") == "link" then return false end
        end
        return not relative:find("//", 1, true)
    end
    local queue = directory .. "annotation-jobs/"
    if lfs.attributes(queue, "mode") ~= "directory" then return 0 end
    for _, name in ipairs({ "annotation-results", "annotation-backups", "annotation-failed" }) do util.makePath(directory .. name) end
    local files = {}
    for filename in lfs.dir(queue) do if filename:match("%.json$") then files[#files+1] = filename end end
    table.sort(files)
    local start = 1
    if M.cursor then for index, filename in ipairs(files) do if filename > M.cursor then start = index; break end end end
    local processed, retry = 0, false
    local function invalid(filename, reason)
        local result = { jobId = filename:gsub("%.json$", ""), status = "invalid", error = reason }
        assert(write(directory .. "annotation-results/" .. filename, json.encode(result)))
        local failed = directory .. "annotation-failed/" .. filename
        local suffix = 0
        while lfs.attributes(failed) do suffix = suffix + 1; failed = directory .. "annotation-failed/" .. filename .. "." .. suffix end
        assert(os.rename(queue .. filename, failed))
        logger.warn("KindleSpouse:", "quarantined invalid annotation task", filename, reason)
    end
    local function process(filename)
        local bytes = read(queue .. filename, 200000)
        local decoded, job = pcall(json.decode, bytes or "")
        if not decoded or type(job) ~= "table" then return invalid(filename, "invalid or empty JSON") end
        if type(job.jobId) ~= "string" or not job.jobId:match("^[%da-fA-F%-]+$") or #job.jobId > 64 or job.jobId .. ".json" ~= filename then return invalid(filename, "task identity does not match filename") end
        if type(job.expected) ~= "table" or not safe(job.bookRelative) or not safe(job.relative) or not (job.operation == "delete" or job.operation == "edit" and type(job.note) == "string") then return invalid(filename, "invalid annotation task fields") end
        for _, key in ipairs({ "text", "note", "datetime", "pos0", "pos1" }) do if type(job.expected[key]) ~= "string" then return invalid(filename, "invalid annotation revision") end end
        local status, alternate = "conflict", nil
        local target, source = mount .. "/" .. job.bookRelative, mount .. "/" .. job.relative
        local info = lfs.attributes(target)
        if info and info.size == job.bookSize and info.modification == job.bookModified then
            local original = read(source, 10485760)
            if original then
                local backup = directory .. "annotation-backups/" .. filename .. ".lua"
                if not lfs.attributes(backup) then assert(write(backup, original)) end
                local DocSettings = require("docsettings")
                local settings = DocSettings:open(target)
                if settings.source_candidate == source and G_reader_settings:readSetting("document_metadata_folder", "doc") == "doc" then
                    status, alternate = M.apply(settings, job)
                    if status == "applied" then
                        local flushed, result = pcall(settings.flush, settings, nil, true)
                        if not flushed or not result then logger.warn("KindleSpouse:", "annotation save failed; retaining task", filename); return false end
                        local verify = DocSettings:open(target):readSetting("kindlespouse_applied_jobs")
                        if not (type(verify) == "table" and verify[job.jobId]) then logger.warn("KindleSpouse:", "annotation verification failed; retaining task", filename); return false end
                    end
                end
            end
        end
        assert(write(directory .. "annotation-results/" .. filename, json.encode({ jobId = job.jobId, status = status, alternate = alternate })))
        assert(os.remove(queue .. filename))
        return true
    end
    for offset = 0, math.min(#files, 4)-1 do
        local filename = files[(start + offset - 1) % #files + 1]
        M.cursor = filename
        local ok, error = pcall(process, filename)
        if not ok then
            logger.warn("KindleSpouse:", "annotation task failed", filename, tostring(error))
            local quarantined, reason = pcall(invalid, filename, "annotation task failed")
            if not quarantined then logger.warn("KindleSpouse:", "task retained after result failure", filename, tostring(reason)) end
        end
        if not lfs.attributes(queue .. filename) then processed = processed + 1 else retry = true end
    end
    return processed, retry
end
return M
