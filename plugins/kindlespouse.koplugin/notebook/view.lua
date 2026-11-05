local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalSpan = require("ui/widget/verticalspan")
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

local AnnotationMenu = Menu:extend {}

local function metadata(item)
    local date = item.datetime:match("^%d%d%d%d%-%d%d%-%d%d") or ""
    local chapter = item.chapter or ""
    if type(item.position) == "number" then
        chapter = chapter ~= "" and chapter .. " · " .. T("notebook.page", item.position) or T("notebook.page", item.position)
    end
    return chapter ~= "" and date ~= "" and chapter .. " · " .. date or chapter .. date
end

local function annotationWidgets(item, width, available_height)
    local padding = Screen:scaleBySize(12)
    local gap = Screen:scaleBySize(8)
    local indent = Screen:scaleBySize(20)
    local widgets = {}
    local function textbox(text, font_size, box_width, height, color)
        return TextBoxWidget:new {
            text = text, face = Font:getFace("cfont", font_size), width = box_width,
            height = height, height_adjust = height ~= nil, height_overflow_show_ellipsis = true,
            alignment = "left", fgcolor = color or Blitbuffer.COLOR_BLACK,
        }
    end
    local footer = metadata(item)
    if footer ~= "" then
        widgets.metadata = textbox(footer, 13, width, Screen:scaleBySize(40), Blitbuffer.COLOR_DARK_GRAY)
    end
    if item.text ~= "" then widgets.quote = textbox(item.text, 18, width) end
    if item.note ~= "" then widgets.note = textbox(T("notebook.note", item.note), 18, width - indent) end
    local count = (widgets.quote and 1 or 0) + (widgets.note and 1 or 0) + (widgets.metadata and 1 or 0)
    local text_budget = available_height - 2 * padding - math.max(0, count - 1) * gap
        - (widgets.metadata and widgets.metadata:getSize().h or 0)
    local quote_height = widgets.quote and widgets.quote:getSize().h or 0
    local note_height = widgets.note and widgets.note:getSize().h or 0
    if quote_height + note_height > text_budget then
        local quote_budget = widgets.note and math.min(quote_height, math.max(text_budget / 2, text_budget - note_height)) or text_budget
        if widgets.quote and quote_height > quote_budget then
            widgets.quote:free()
            widgets.quote = textbox(item.text, 18, width, quote_budget)
        end
        local note_budget = text_budget - (widgets.quote and widgets.quote:getSize().h or 0)
        if widgets.note and note_height > note_budget then
            widgets.note:free()
            widgets.note = textbox(T("notebook.note", item.note), 18, width - indent, note_budget)
        end
    end
    local group = VerticalGroup:new { align = "left", VerticalSpan:new { width = padding } }
    for _, name in ipairs({ "quote", "note", "metadata" }) do
        local widget = widgets[name]
        if widget then
            if #group > 1 then group[#group + 1] = VerticalSpan:new { width = gap } end
            group[#group + 1] = name == "note" and HorizontalGroup:new {
                HorizontalSpan:new { width = indent }, widget,
            } or widget
        end
    end
    group[#group + 1] = VerticalSpan:new { width = padding }
    return group, widgets
end

function AnnotationMenu:setupItemHeights()
    if not self.item_table[1] or not self.item_table[1].annotation then return Menu.setupItemHeights(self) end
    self.page_items = { {} }
    local used = 0
    for index, item in ipairs(self.item_table) do
        local group = annotationWidgets(item.annotation, self.inner_dimen.w - 2 * Size.padding.fullscreen, self.available_height - self.linesize)
        item.height = group:getSize().h + self.linesize
        group:free()
        if used > 0 and used + item.height > self.available_height then
            self.page_items[#self.page_items + 1] = {}
            used = 0
        end
        local page = self.page_items[#self.page_items]
        page[#page + 1] = index
        used = used + item.height
    end
end

function AnnotationMenu:updateItems(...)
    Menu.updateItems(self, ...)
    for _, row in ipairs(self.item_group) do
        if row.entry.annotation then
            local group, widgets = annotationWidgets(row.entry.annotation, row.content_width, self.available_height - self.linesize)
            row._underline_container[1]:free()
            row._underline_container[1] = group
            row.rich = widgets
        end
    end
    self.item_group:resetLayout()
    self.content_group:resetLayout()
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
                text = table.concat({ annotation.text, annotation.note ~= "" and T("notebook.note", annotation.note) or "", metadata(annotation) }, "\n"),
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
    self.title:setText(self.book and self.book.title or T("notebook.summary"))
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
    self.title = TextBoxWidget:new { text = T("notebook.summary"), width = self.dimen.w - 2 * Size.padding.fullscreen,
        height = Screen:scaleBySize(64), face = Font:getFace("cfont", 24), bold = true,
        height_overflow_show_ellipsis = true, alignment = "left" }
    local heading = FrameContainer:new { bordersize = 0, padding = Size.padding.fullscreen, background = Blitbuffer.COLOR_WHITE, self.title }
    self.menu = AnnotationMenu:new {
        width = self.dimen.w, height = math.max(Screen:scaleBySize(100), self.height - buttons:getSize().h - heading:getSize().h - self.native:getSize().h), no_title = true,
        item_table = {}, is_borderless = true, is_popout = false, show_parent = self.companion.ui or self,
        items_max_lines = 3, items_font_size = 18, is_enable_shortcut = false, line_color = Blitbuffer.COLOR_LIGHT_GRAY,
    }
    self:installMenuHandlers()
    self[1] = VerticalGroup:new { align = "left", buttons, heading, self.menu, self.native }
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
