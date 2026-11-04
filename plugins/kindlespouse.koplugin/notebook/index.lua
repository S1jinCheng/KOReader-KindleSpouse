local DocSettings = require("docsettings")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local natural = require("sort").natsort_cmp()
local util = require("util")
local Index = {}
Index.__index = Index
local cache = {}

local function normalized(value)
    return util.stringLower(type(value) == "string" and value or "")
end

local function position(item)
    if type(item.page) == "number" then return item.page end
    if type(item.pos0) == "table" and type(item.pos0.page) == "number" then return item.pos0.page end
    if type(item.pos0) == "string" then return item.pos0 end
    if type(item.page) == "string" then return item.page end
end

local function annotations(data)
    local output, seen = {}, {}
    local values = type(data) == "table" and data.annotations
    if type(values) == "table" then
        for _, item in ipairs(values) do
            if type(item) == "table" then
                local location = position(item)
                local text = type(item.text) == "string" and item.text or ""
                local note = type(item.note) == "string" and item.note or ""
                if location and (note ~= "" or type(item.drawer) == "string") then
                    local datetime = type(item.datetime_updated) == "string" and item.datetime_updated
                        or type(item.datetime) == "string" and item.datetime or ""
                    local signature = table.concat({ type(location), tostring(location), text, note, datetime }, "\0")
                    if not seen[signature] then
                        seen[signature] = true
                        output[#output + 1] = {
                            position = location, text = text, note = note, datetime = datetime,
                            chapter = type(item.chapter) == "string" and item.chapter or "",
                            color = item.color, drawer = item.drawer, order = #output + 1,
                        }
                    end
                end
            end
        end
    end
    table.sort(output, function(left, right)
        if type(left.position) == type(right.position) then
            if left.position ~= right.position then
                if type(left.position) == "number" then return left.position < right.position end
                return natural(left.position, right.position)
            end
        else return type(left.position) == "number" end
        return left.order < right.order
    end)
    return output
end

local function sidecars(filename)
    local name = DocSettings.getSidecarFilename(filename)
    local document = DocSettings:getSidecarDir(filename, "doc")
    local directory = DocSettings:getSidecarDir(filename, "dir")
    local paths = { document .. "/" .. name, document .. "/" .. name .. ".old",
        document .. "/" .. filename:match("[^/]+$") .. ".lua", directory .. "/" .. name, directory .. "/" .. name .. ".old" }
    if DocSettings.isHashLocationEnabled() then
        local hashed = DocSettings:getSidecarDir(filename, "hash") .. "/" .. name
        paths[#paths + 1], paths[#paths + 2] = hashed, hashed .. ".old"
    end
    local history = DocSettings:getHistoryPath(filename)
    paths[#paths + 1], paths[#paths + 2] = history, history .. ".old"
    paths[#paths + 1] = filename .. ".kpdfview.lua"
    local candidates, signature, previous = {}, {}, nil
    for priority, path in ipairs(paths) do
        local info = lfs.attributes(path)
        if info and info.mode == "file" then
            local candidate = { path = path, mtime = info.modification, priority = priority, size = info.size }
            if previous and path == previous.path .. ".old" and candidate.mtime > previous.mtime then previous.mtime = candidate.mtime end
            candidates[#candidates + 1] = candidate
            signature[#signature + 1] = table.concat({ path, info.modification, info.size, info.change }, "\0")
            previous = candidate
        else previous = nil end
    end
    table.sort(candidates, function(left, right)
        if left.mtime ~= right.mtime then return left.mtime > right.mtime end
        return left.priority < right.priority
    end)
    return candidates, table.concat(signature, "\0")
end

function Index.new(options)
    options = options or {}
    return setmetatable({ catalog = options.catalog or require("catalog"), cache = options.cache or cache,
        books = {}, generation = 0, delay = 0.01, batch_size = 50, processed = 0 }, Index)
end

function Index.invalidate(filename)
    cache[filename] = nil
end

function Index:invalidatePath(filename)
    self.cache[filename] = nil
end

function Index:read(record)
    local filename = record.path
    local reader = ReaderUI.instance
    local data
    if reader and reader.document and reader.document.file == filename and reader.annotation then
        data = { annotations = reader.annotation.annotations }
    else
        local candidates, signature = sidecars(filename)
        local previous = self.cache[filename]
        if previous and previous.signature == signature then return previous.items end
        local settings
        for _, candidate in ipairs(candidates) do
            if candidate.size <= 10 * 1024 * 1024 then
                local loaded, value = pcall(DocSettings.openSettingsFile, candidate.path)
                if loaded and value and type(value.data) == "table" and next(value.data) ~= nil then
                    settings = value.data
                    break
                end
            end
        end
        local items = annotations(settings)
        self.cache[filename] = { signature = signature, items = items }
        return items
    end
    return annotations(data)
end

function Index:cancel()
    self.generation = self.generation + 1
    if self.task then UIManager:unschedule(self.task); self.task = nil end
    self.pending = false
end

function Index:refresh(callback, root)
    self:cancel()
    local generation = self.generation
    local records = self.catalog.records(root)
    local queued, seen = {}, {}
    for _, record in ipairs(type(records) == "table" and records or {}) do
        if type(record) == "table" and type(record.path) == "string" and not seen[record.path] then
            seen[record.path] = true
            queued[#queued + 1] = record
        end
    end
    self.books, self.processed, self.pending = {}, 0, true
    local function batch()
        if self.generation ~= generation then return end
        local limit = math.min(#queued, self.processed + self.batch_size)
        for index = self.processed + 1, limit do
            local record = queued[index]
            local ok, items = pcall(self.read, self, record)
            if ok and #items > 0 then
                local notes, highlights, latest = 0, 0, ""
                for _, item in ipairs(items) do
                    if item.note ~= "" then notes = notes + 1 end
                    if item.drawer then highlights = highlights + 1 end
                    if item.datetime > latest then latest = item.datetime end
                end
                self.books[#self.books + 1] = {
                    path = record.path, title = record.title or record.name or record.path:match("[^/]+$"),
                    author = record.author or "", recent = tonumber(record.recent) or 0, latest = latest,
                    highlights = highlights, notes = notes, items = items,
                }
            end
        end
        self.processed = limit
        table.sort(self.books, function(left, right)
            if left.recent ~= right.recent then return left.recent > right.recent end
            if left.latest ~= right.latest then return left.latest > right.latest end
            if left.title ~= right.title then return natural(left.title, right.title) end
            return left.path < right.path
        end)
        self.pending = limit < #queued
        if callback then callback(self.books, not self.pending) end
        if self.generation ~= generation then return end
        if self.pending then UIManager:scheduleIn(self.delay, batch) else self.task = nil end
    end
    self.task = batch
    UIManager:scheduleIn(self.delay, batch)
end

function Index:search(query, filename)
    query = normalized(query)
    local results = {}
    for _, book in ipairs(self.books) do
        if not filename or book.path == filename then
            if filename then
                for _, item in ipairs(book.items) do
                    if query == "" or normalized(item.text .. " " .. item.note):find(query, 1, true) then results[#results + 1] = item end
                end
            else
                local matches = query == "" or normalized(book.title .. " " .. book.author):find(query, 1, true)
                if not matches then
                    for _, item in ipairs(book.items) do
                        if normalized(item.text .. " " .. item.note):find(query, 1, true) then matches = true; break end
                    end
                end
                if matches then results[#results + 1] = book end
            end
        end
    end
    return results
end

return Index