local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Index = require("notebook/index")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local ReaderUI = require("apps/reader/readerui")
local T = require("i18n").T
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen
local Patches = require("patches")
local View = {}
local Panel = InputContainer:extend { covers_fullscreen = false }

local function excerpt(text, limit)
    local characters = {}
    for character in text:gsub("%s+", " "):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #characters == limit then return table.concat(characters) .. "…" end
        characters[#characters+1] = character
    end
    return table.concat(characters)
end

local function preview(item)
    local limit = math.max(12, math.floor(Screen:getWidth() / Screen:scaleBySize(18)) - 3 - (type(item.position) == "number" and 6 or 0))
    local date = item.datetime:match("^%d%d%d%d%-%d%d%-%d%d") or ""
    local footer = excerpt(item.chapter or "", math.max(4, limit - (date ~= "" and 13 or 0)))
    if date ~= "" then footer = footer ~= "" and footer .. " · " .. date or date end
    local rows = {}
    if item.text ~= "" then rows[#rows+1] = excerpt(item.text, limit * (item.note == "" and (footer == "" and 3 or 2) or 1)) end
    if item.note ~= "" then rows[#rows+1] = excerpt(T("notebook.note", item.note), limit * (#rows == 0 and (footer == "" and 3 or 2) or 1)) end
    if footer ~= "" then rows[#rows+1] = footer end
    return table.concat(rows, "\n")
end

function View.navigate(filename, item)
    local function unavailable()
        UIManager:show(InfoMessage:new { text = T("notebook.location_unavailable"), timeout = 3 })
    end
    local function jump(reader)
        if not reader.document or reader.document.file ~= filename then return unavailable() end
        local location = item.position
        if type(location) == "string" and reader.rolling then
            if type(reader.document.isXPointerInDocument) == "function" and not reader.document:isXPointerInDocument(location) then return unavailable() end
            if reader.link and type(reader.link.addCurrentLocationToStack) == "function" then reader.link:addCurrentLocationToStack() end
            return reader:handleEvent(Event:new("GotoXPointer", location, location))
        elseif type(location) == "number" and reader.paging and location >= 1 and location % 1 == 0 then
            local pages = reader.document.info and reader.document.info.number_of_pages
            if type(pages) == "number" and location > pages then return unavailable() end
            if reader.link and type(reader.link.addCurrentLocationToStack) == "function" then reader.link:addCurrentLocationToStack() end
            return reader:handleEvent(Event:new("GotoPage", location))
        end
        unavailable()
    end
    local current = ReaderUI.instance
    if current and current.document and current.document.file == filename then return jump(current) end
    return ReaderUI:showReader(filename, nil, nil, nil, jump)
end

function Panel:render()
    if self.closed then return end
    local items = {}
    if self.book then
        for _, annotation in ipairs(self.index:search(self.query, self.book.path)) do
            local selected = annotation
            items[#items + 1] = {
                text = preview(annotation),
                mandatory = type(annotation.position) == "number" and T("notebook.page", annotation.position) or "",
                annotation = annotation,
                callback = function()
                    local filename = self.book.path
                    if UIManager:getTopmostVisibleWidget() == self then UIManager:close(self) else self:onCloseWidget() end
                    View.navigate(filename, selected)
                end,
            }
        end
    else
        for _, book in ipairs(self.index:search(self.query)) do
            local selected = book
            items[#items + 1] = {
                text = book.title .. (book.author ~= "" and " · " .. book.author or ""), mandatory = T("notebook.counts", book.highlights, book.notes), book = book,
                callback = function() self.book = selected; self:render() end,
            }
        end
    end
    if #items == 0 then
        items[1] = { text = T(self.index.pending and "notebook.loading" or "notebook.empty"), select_enabled = false }
    end
    self.menu:switchItemTable(nil, items)
    self.back:setText(self.book and T("notebook.books") or T("notebook.summary"), self.back.width)
    UIManager:setDirty(self.companion.ui or self, "ui", self.dimen)
end

function Panel:search(query)
    if query == nil then
        if self.search_dialog then return self.search_dialog end
        local dialog
        dialog = InputDialog:new {
            title = T("notebook.search"), input = self.query,
            buttons = { {
                { text = T("notebook.cancel"), callback = function() UIManager:close(dialog) end },
                { text = T("notebook.search"), is_enter_default = true, callback = function()
                    local text = dialog:getInputText()
                    UIManager:close(dialog)
                    self:search(text)
                end },
            } },
        }
        local scope = "notebook:" .. tostring(self) .. ":dialog:" .. tostring(dialog) .. ":"
        Patches.wrap(scope .. "close", dialog, "onCloseWidget", function(original, widget, ...)
            if self.search_dialog == widget then self.search_dialog = nil end
            Patches.revertPrefix(scope)
            return original(widget, ...)
        end)
        self.search_dialog = dialog
        UIManager:show(dialog)
        dialog:onShowKeyboard()
        return dialog
    end
    if self.closed then return end
    self.query = type(query) == "string" and query or ""
    self:render()
end

function Panel:refresh()
    self.closed = false
    self:installMenuHandlers()
    self.index:refresh(function()
        if self.closed then return end
        self:render()
    end, self.root)
    self:render()
end

function Panel:installMenuHandlers()
    self.scope = self.scope or "notebook:" .. tostring(self) .. ":"
    if Patches.applied[self.scope .. "select"] then return end
    Patches.wrap(self.scope .. "select", self.menu, "onMenuSelect", function(_, _, item)
        if item.select_enabled ~= false and item.callback then item.callback() end
        return true
    end)
    Patches.wrap(self.scope .. "close", self.menu, "onClose", function()
        if self.book then self.book = nil; self:render() end
        return true
    end)
end

function Panel:init()
    self.query = ""
    self.dimen = Geom:new { x = 0, y = 0, w = Screen:getWidth(), h = self.height }
    local buttons = ButtonTable:new { width = self.dimen.w, buttons = { {
        { id = "kindlespouse-summary-back", text = T("notebook.summary"), callback = function() self.book = nil; self:render() end },
        { text = T("notebook.search"), callback = function() self:search() end },
        { text = T("notebook.refresh"), callback = function() self:refresh() end },
    } } }
    self.native = require("ui/widget/button"):new { text = T("notebook.native"),
        enabled = Device:isKindle(), width = self.dimen.w, height = Screen:scaleBySize(32),
        bordersize = 0, padding = 0, text_font_size = 14, text_font_bold = false,
        callback = function() require("home").returnToKindle(self.companion) end }
    self.back = buttons:getButtonById("kindlespouse-summary-back")
    self.menu = Menu:new {
        width = self.dimen.w, height = math.max(Screen:scaleBySize(100), self.height - buttons:getSize().h - self.native:getSize().h), no_title = true,
        item_table = {}, is_borderless = true, is_popout = false, show_parent = self.companion.ui or self,
        items_max_lines = 3, items_font_size = 18, is_enable_shortcut = false,
    }
    self:installMenuHandlers()
    self[1] = VerticalGroup:new { align = "left", buttons, self.menu, self.native }
    self:refresh()
end

function Panel:onCloseWidget()
    self.closed = true
    self.index:cancel()
    if self.search_dialog then UIManager:close(self.search_dialog); self.search_dialog = nil end
    if self.scope then Patches.revertPrefix(self.scope) end
end

function Panel:free()
    if not self.closed then self:onCloseWidget() end
    Patches.revertPrefix(self.scope)
    InputContainer.free(self)
end

function View.open(companion, height, options)
    options = options or {}
    return Panel:new {
        companion = companion, height = height or Screen:getHeight(),
        index = options.index or Index.new({ catalog = options.catalog }), root = options.root,
    }
end

return View
