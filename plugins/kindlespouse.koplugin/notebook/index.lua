local DocSettings = require("docsettings")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
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

local function annotations(values)
    local output, seen = {}, {}
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

local function sidecar(filename)
    local path = DocSettings:findSidecarFile(filename)
    local info = path and lfs.attributes(path)
    if not info or info.mode ~= "file" then return nil, "" end
    return path, table.concat({ path, info.modification, info.size, info.change }, "\0"), info.size
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
    if record.status == "new" then return {} end
    local filename = record.path
    local reader = ReaderUI.instance
    if reader and reader.document and reader.document.file == filename and reader.annotation then
        return annotations(reader.annotation.annotations)
    end
    local path, signature, size = sidecar(filename)
    local previous = self.cache[filename]
    if previous and previous.signature == signature then return previous.items end
    local settings
    if path and size <= 10 * 1024 * 1024 then
        local loaded, value = pcall(DocSettings.openSettingsFile, path)
        if loaded and value and type(value.data) == "table" and next(value.data) ~= nil then
            settings = value.data
        else
            logger.warn("KindleSpouse: empty or invalid annotation sidecar", path)
        end
    end
    local items = annotations(settings and settings.annotations)
    self.cache[filename] = { signature = signature, items = items }
    return items
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
        if type(record) == "table" and record.status ~= "new" and type(record.path) == "string" and not seen[record.path] then
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