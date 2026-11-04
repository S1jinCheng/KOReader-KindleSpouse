local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local Extractor = require("extractor")
local Catalog = { entries = {}, roots = {}, subscribers = {}, books = {} }
local store, bookinfo, persist_task

local function normalize(root)
    assert(type(root) == "string" and root ~= "")
    return root == "/" and root or root:gsub("/+$", "")
end

local function inside(filepath, root)
    return filepath:sub(1, #root + (root == "/" and 0 or 1)) == (root == "/" and root or root .. "/")
end

local function allowed(filepath, root)
    if not inside(filepath, root) then return false end
    local relative = filepath:sub(#root + (root == "/" and 1 or 2))
    for part in relative:gmatch("[^/]+") do
        if part:sub(1, 1) == "." or part:match("%.sdr$") then return false end
    end
    return true
end

local function filename(filepath)
    return filepath:match("([^/]+)$")
end

local function fallback(filepath)
    return filename(filepath):gsub("%.[^.]+$", "")
end

local function persist()
    if not store then return end
    local roots = {}
    for root, state in pairs(Catalog.roots) do roots[root] = state.complete == true end
    store:saveSetting("schema", 2)
    store:saveSetting("books", Catalog.books)
    store:saveSetting("roots", roots)
    store:flush()
end

persist_task = function()
    Catalog.persist_pending = false
    persist()
end

local function saveLater()
    if Catalog.persist_pending then return end
    Catalog.persist_pending = true
    UIManager:scheduleIn(0.2, persist_task)
end

local function load()
    if store then return end
    store = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/kindlespouse-library.lua")
    local saved = store:readSetting("books", {})
    for filepath, value in pairs(saved) do
        if type(filepath) == "string" and type(value) == "table" then
            value.path = filepath
            value.name = value.name or filename(filepath)
            value.format = value.format or filepath:lower():match("%.([^.]+)$") or ""
            value.mtime = value.mtime or value.modified
            value.modified = value.mtime
            value.title = value.title or fallback(filepath)
            value.author = value.author or ""
            if value.meta_ready == nil then value.meta_ready = value.title ~= fallback(filepath) or value.author ~= "" end
            value.status, value.progress, value.recent = value.status or "new", value.progress or 0, value.recent or 0
            Catalog.books[filepath] = value
        end
    end
    local roots = store:readSetting("roots", {})
    for root, complete in pairs(roots) do
        if type(root) == "string" then
            local entries = {}
            for filepath, entry in pairs(Catalog.books) do
                if allowed(filepath, root) then entries[filepath] = entry end
            end
            Catalog.roots[root] = { root = root, entries = entries, complete = complete == true, scanning = false }
        end
    end
    if store:readSetting("schema") ~= 2 then saveLater() end
end

local function history()
    local recent = {}
    for _, item in ipairs(require("readhistory").hist) do recent[item.file] = item.time end
    return recent
end

local function reading(entry, recent)
    local info = BookList.getBookInfo(entry.path)
    entry.status = info.been_opened and (info.status or "reading") or "new"
    entry.progress = info.percent_finished or 0
    entry.recent = recent[entry.path] or 0
end

local function stateFor(root)
    load()
    local state = Catalog.roots[root]
    if not state then
        local entries = {}
        for filepath, entry in pairs(Catalog.books) do
            if allowed(filepath, root) then entries[filepath] = entry end
        end
        state = { root = root, entries = entries, complete = false, scanning = false }
        Catalog.roots[root] = state
    end
    return state
end

local function selectRoot(root)
    local state = stateFor(normalize(root))
    Catalog.root, Catalog.entries = state.root, state.entries
    return state
end

local function emit(kind, root, done)
    local state = Catalog.roots[root]
    local count = 0
    for _ in pairs(state.entries) do count = count + 1 end
    local event = { kind = kind, root = root, scanning = state.scanning, count = count, done = done == true }
    for _, callback in pairs(Catalog.subscribers) do callback(event, root) end
end

function Catalog.subscribe(owner, callback)
    assert(owner ~= nil and type(callback) == "function")
    Catalog.subscribers[owner] = callback
end

function Catalog.unsubscribe(owner)
    Catalog.subscribers[owner] = nil
end

function Catalog.attachBookInfo(value)
    bookinfo = value
end

local function source(filepath, root)
    local relative = filepath:sub(#root + (root == "/" and 1 or 2))
    return relative:match("^([^/]+)/") or "书籍根目录"
end

local function metadata(entry, info)
    if info and not info.ignore_meta then
        entry.title = info.title and info.title ~= "" and info.title or entry.title
        entry.author = info.authors or entry.author
    end
    entry.meta_ready = true
    entry.meta_error = info and info.unsupported or nil
end

local function requestMetadata(state, entries)
    local files = {}
    for _, entry in ipairs(entries) do files[#files + 1] = { filepath = entry.path } end
    if #files == 0 then return end
    Extractor.enqueue(state, files, function(filepath, info, status)
        local entry = Catalog.books[filepath]
        if not entry or state.entries[filepath] ~= entry then return end
        if info and Extractor.isFresh(info, { size = entry.size, modification = entry.mtime }) then
            metadata(entry, info)
        elseif status == "unsupported" then
            entry.meta_ready, entry.meta_error = true, info and info.unsupported
        else
            entry.meta_error = status
        end
        saveLater()
        emit("metadata", state.root)
    end)
end

local function record(state, filepath, attr, recent, pending)
    local previous = Catalog.books[filepath]
    local changed = not previous or previous.size ~= attr.size or previous.mtime ~= attr.modification
    local entry = previous or { path = filepath, added = attr.change or os.time() }
    entry.name = filename(filepath)
    entry.format = filepath:lower():match("%.([^.]+)$") or ""
    entry.source = source(filepath, state.root)
    entry.size, entry.mtime, entry.modified = attr.size, attr.modification, attr.modification
    if changed then
        local info = Extractor.cached(filepath)
        local props
        if not Extractor.isFresh(info, attr) and bookinfo then props = bookinfo:getDocProps(filepath, nil, true) end
        entry.title = props and props.title or previous and previous.title or fallback(filepath)
        entry.author = props and props.authors or previous and previous.author or ""
        entry.meta_ready, entry.meta_error = false, nil
        if Extractor.isFresh(info, attr) then
            metadata(entry, info)
        else
            pending[#pending + 1] = entry
        end
    elseif not entry.meta_ready then
        pending[#pending + 1] = entry
    end
    reading(entry, recent)
    Catalog.books[filepath] = entry
    state.entries[filepath] = entry
    return entry
end

local function closeIterator(scan)
    if scan.handle then pcall(scan.handle.close, scan.handle) end
    scan.iterator, scan.handle = nil, nil
end

local function finish(state, scan)
    closeIterator(scan)
    for filepath in pairs(state.entries) do
        if not scan.seen[filepath] then
            state.entries[filepath], Catalog.books[filepath] = nil, nil
            for _, other in pairs(Catalog.roots) do other.entries[filepath] = nil end
        end
    end
    state.scanning, state.complete, state.scan = false, true, nil
    persist()
    emit("scan", state.root, true)
    for _, callback in ipairs(scan.callbacks) do callback(state) end
end

local function start(state, on_done)
    if state.scanning then
        if on_done then state.scan.callbacks[#state.scan.callbacks + 1] = on_done end
        return state
    end
    local scan = { directories = { state.root }, head = 1, seen = {}, recent = history(), callbacks = {}, generation = (state.generation or 0) + 1 }
    if on_done then scan.callbacks[1] = on_done end
    state.scanning, state.scan, state.generation = true, scan, scan.generation
    scan.step = function()
        if state.scan ~= scan then return end
        local processed, pending = 0, {}
        while processed < 50 do
            if not scan.iterator then
                local directory = scan.directories[scan.head]
                if not directory then break end
                scan.head = scan.head + 1
                local attr = lfs.symlinkattributes(directory)
                local ok, iterator, handle
                if attr and attr.mode == "directory" then ok, iterator, handle = pcall(lfs.dir, directory) end
                if ok then scan.iterator, scan.handle, scan.directory = iterator, handle, directory
                else processed = processed + 1 end
            end
            if scan.iterator then
                local ok, name = pcall(scan.iterator, scan.handle)
                processed = processed + 1
                if not ok or not name then
                    closeIterator(scan)
                elseif name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
                    local filepath = scan.directory .. "/" .. name
                    local attr = lfs.symlinkattributes(filepath)
                    if attr and attr.mode == "directory" then
                        scan.directories[#scan.directories + 1] = filepath
                    elseif attr and attr.mode == "file" and DocumentRegistry:hasProvider(filepath) then
                        scan.seen[filepath] = true
                        record(state, filepath, attr, scan.recent, pending)
                    end
                end
            end
        end
        requestMetadata(state, pending)
        if not scan.iterator and scan.head > #scan.directories then
            finish(state, scan)
        else
            emit("scan", state.root)
            UIManager:scheduleIn(0.01, scan.step)
        end
    end
    UIManager:scheduleIn(0.01, scan.step)
    return state
end

function Catalog.ensure(root, on_done)
    local state = selectRoot(root)
    if not state.complete then return start(state, on_done) end
    if not state.metadata_requested then
        state.metadata_requested = true
        local pending = {}
        for _, entry in pairs(state.entries) do
            if not entry.meta_ready then pending[#pending + 1] = entry end
        end
        requestMetadata(state, pending)
    end
    if on_done then UIManager:scheduleIn(0.01, on_done, state) end
    return state
end

function Catalog.rescan(root, on_done)
    return start(selectRoot(root), on_done)
end

function Catalog.cancel(root)
    local state = Catalog.roots[normalize(root)]
    if not state then return end
    if state.scan then
        UIManager:unschedule(state.scan.step)
        closeIterator(state.scan)
        state.scan = nil
        state.scanning, state.complete = false, false
    end
    Extractor.cancel(state)
    state.metadata_requested = nil
end

function Catalog.records(root)
    load()
    local state = root and Catalog.roots[normalize(root)] or Catalog.root and Catalog.roots[Catalog.root]
    local result = {}
    for _, entry in pairs(state and state.entries or {}) do result[#result + 1] = entry end
    table.sort(result, function(left, right) return left.path < right.path end)
    return result
end

function Catalog.items(chooser)
    local state = selectRoot(chooser.path)
    local result, recent = {}, history()
    local collate = chooser:getCollate()
    for _, entry in ipairs(Catalog.records(state.root)) do
        reading(entry, recent)
        local attr = { mode = "file", size = entry.size, modification = entry.mtime, change = entry.added }
        local directory = entry.path:match("^(.*)/[^/]+$")
        local item = chooser:getListItem(directory, entry.name, entry.path, attr, collate)
        local data = {}
        for name, value in pairs(entry) do data[name] = value end
        data.author = entry.author ~= "" and entry.author or "未提供作者"
        data.source = source(entry.path, state.root)
        item.kindlespouse = data
        result[#result + 1] = item
    end
    return result
end

local function change(filepath, kind)
    load()
    local attr = lfs.symlinkattributes(filepath)
    if not attr or attr.mode ~= "file" or not DocumentRegistry:hasProvider(filepath) then
        if Catalog.books[filepath] then Catalog.remove(filepath) end
        return
    end
    local recent = history()
    for root, state in pairs(Catalog.roots) do
        if allowed(filepath, root) then
            local pending = {}
            record(state, filepath, attr, recent, pending)
            requestMetadata(state, pending)
            emit(kind, root)
        end
    end
    saveLater()
end

function Catalog.touch(filepath)
    change(filepath, "touch")
end

function Catalog.add(filepath)
    change(filepath, "add")
end

function Catalog.remove(filepath)
    load()
    Catalog.books[filepath] = nil
    for root, state in pairs(Catalog.roots) do
        if state.entries[filepath] then
            state.entries[filepath] = nil
            emit("remove", root)
        end
    end
    saveLater()
end

function Catalog.flush()
    load()
    UIManager:unschedule(persist_task)
    Catalog.persist_pending = false
    persist()
end

return Catalog
