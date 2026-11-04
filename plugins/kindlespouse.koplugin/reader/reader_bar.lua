local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Highlight = require("reader/highlight_bar")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Patches = require("patches")
local ProgressWidget = require("ui/widget/progresswidget")
local T = require("i18n").T
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Screen = Device.screen
local ReaderBar = {}
local Bar = InputContainer:extend { covers_fullscreen = false, modal = true }

local function has(target, name)
    return target and type(target[name]) == "function"
end

local function progress(ui)
    local engine = ui.rolling or ui.paging
    local total = ui.document.info and ui.document.info.number_of_pages or 0
    local current = engine and engine.current_page or 0
    local ratio = has(engine, "getLastPercent") and engine:getLastPercent() or 0
    if type(ratio) ~= "number" or ratio ~= ratio then ratio = 0 end
    if type(total) ~= "number" or total < 1 then total = 1 end
    if type(current) ~= "number" or current < 1 then current = 1 end
    return math.max(0, math.min(1, ratio)), math.min(current, total), total
end

function Bar:refreshProgress(ratio)
    local actual, page, pages = progress(self.ui)
    ratio = ratio or actual
    self.progress.percentage = ratio
    local text = T("reader.progress", page, pages, math.floor(ratio * 100 + 0.5))
    if has(self.ui.statistics, "getTimeForPages") then
        local remaining = self.ui.statistics:getTimeForPages(math.max(0, pages - page))
        if remaining then text = text .. " · " .. T("reader.remaining", remaining) end
    end
    self.progress_text:setText(text)
    self.bottom[1]:resetLayout()
    UIManager:setDirty(self, "ui", self.bottom_rect)
end

function Bar:jump(ratio)
    local engine = self.ui.rolling or self.ui.paging
    if has(engine, "onGotoPercent") then
        engine:onGotoPercent(math.max(0, math.min(1, ratio)) * 100)
        self:refreshProgress()
    end
end

function Bar:close()
    if self.closed then return end
    self.closed = true
    if self.state.overlay == self then self.state.overlay = nil end
    UIManager:close(self)
end

function Bar:init()
    self.dimen = Screen:getSize()
    local width = Screen:getWidth()
    local padding = Screen:scaleBySize(8)
    local button_height = Screen:scaleBySize(36)
    self.actions = {}
    local function button(key, text, target, method, callback, button_width)
        local widget = Button:new {
            text = text, width = button_width, height = button_height,
            padding = Screen:scaleBySize(4), bordersize = 0,
            text_font_size = 16, text_font_bold = false,
            enabled = callback ~= nil or has(target, method),
            callback = function()
                self:close()
                if callback then return callback() end
                if has(target, method) then return target[method](target) end
            end,
        }
        self.actions[key] = widget
        return widget
    end
    local back_width = math.min(math.floor(width / 3), Screen:scaleBySize(90))
    local title = self.ui.doc_props and (self.ui.doc_props.display_title or self.ui.doc_props.title)
        or self.ui.document.file and self.ui.document.file:match("[^/]+$") or T("reader.book")
    local heading = HorizontalGroup:new {
        align = "center",
        button("library", T("reader.library"), self.ui, "onHome", nil, back_width),
        HorizontalSpan:new { width = padding },
        TextWidget:new { text = title, face = Font:getFace("cfont", 18), max_width = width - back_width - padding * 2 },
    }
    local actions = HorizontalGroup:new { align = "center" }
    local definitions = {
        { "toc", "reader.contents", self.ui.toc, "onShowToc" },
        { "bookmarks", "reader.bookmarks", self.ui.bookmark, "onShowBookmark" },
        { "search", "reader.search", self.ui.search, "onShowFulltextSearchInput" },
        { "appearance", "reader.appearance", self.ui.config, "onShowConfigMenu" },
        { "more", "reader.more", nil, nil, self.more },
    }
    local action_width = math.floor(width / #definitions)
    for _, definition in ipairs(definitions) do
        actions[#actions + 1] = button(definition[1], T(definition[2]), definition[3], definition[4], definition[5], action_width)
    end
    self.top = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0,
        VerticalGroup:new { align = "left", heading, actions },
    }
    self.progress = ProgressWidget:new {
        width = width - padding * 2, height = Screen:scaleBySize(30),
        margin_v = Screen:scaleBySize(10), percentage = 0, radius = Screen:scaleBySize(2),
    }
    local scrub = InputContainer:new { self.progress }
    scrub.ges_events = {}
    for _, event in ipairs({ "tap", "pan", "pan_release", "swipe" }) do
        scrub.ges_events["Scrub" .. event] = {
            GestureRange:new { ges = event, range = function() return scrub.dimen or Geom:new { w = 0, h = 0 } end },
            event = "Scrub",
        }
    end
    scrub.onScrub = function(_, _, gesture)
        if not gesture.pos or not scrub.dimen or scrub.dimen.w <= 0 then return true end
        local ratio = math.max(0, math.min(1, (gesture.pos.x - scrub.dimen.x) / scrub.dimen.w))
        if gesture.ges == "pan" then self:refreshProgress(ratio)
        else self:jump(ratio) end
        return true
    end
    self.scrubber = scrub
    self.progress_text = TextWidget:new { text = "", face = Font:getFace("cfont", 16), max_width = width - padding * 2 }
    self.bottom = FrameContainer:new {
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = padding,
        VerticalGroup:new { align = "center", self.progress_text, scrub },
    }
    self[1], self[2] = self.top, self.bottom
    self.top_rect = Geom:new { x = 0, y = 0, w = width, h = self.top:getSize().h }
    self.bottom_rect = Geom:new { x = 0, y = Screen:getHeight() - self.bottom:getSize().h, w = width, h = self.bottom:getSize().h }
    self.ges_events.Dismiss = { GestureRange:new { ges = "tap", range = Screen:getSize() } }
    if Device:hasKeys() and Device.input.group.Back then self.key_events.Close = { { Device.input.group.Back } } end
    self:refreshProgress()
end

function Bar:paintTo(bb)
    self.top:paintTo(bb, 0, 0)
    self.bottom:paintTo(bb, 0, self.bottom_rect.y)
end

function Bar:onDismiss()
    self:close()
    return true
end

function Bar:onClose()
    self:close()
    return true
end

function Bar:onShow()
    UIManager:setDirty(self, "ui", self.top_rect)
    UIManager:setDirty(self, "ui", self.bottom_rect)
end

function Bar:onCloseWidget()
    self.closed = true
    if self.state.overlay == self then self.state.overlay = nil end
    UIManager:setDirty(nil, "ui", self.top_rect)
    UIManager:setDirty(nil, "ui", self.bottom_rect)
end

function ReaderBar.install(ui)
    local settings = Highlight.settings()
    if not settings.reader_bar or ui._kindlespouse_reader_bar then return false end
    local menu = ui.menu
    if not menu or not ui.document or type(menu.onTapShowMenu) ~= "function" then return false end
    local state = { scope = "reader:" .. tostring(ui) .. ":bar:" }
    ui._kindlespouse_reader_bar = state
    Patches.wrap(state.scope .. "tap", menu, "onTapShowMenu", function(original, self, gesture)
        if self.activation_menu == "swipe" then return original(self, gesture) end
        if state.overlay then state.overlay:close(); return true end
        local bar = Bar:new { ui = ui, state = state, more = function() return original(self, gesture) end }
        state.overlay = bar
        UIManager:show(bar)
        return true
    end)
    if type(menu.onSetDimensions) == "function" then
        Patches.wrap(state.scope .. "dimensions", menu, "onSetDimensions", function(original, self, ...)
            if state.overlay then state.overlay:close() end
            return original(self, ...)
        end)
    end
    if type(ui.onCloseWidget) == "function" then
        Patches.wrap(state.scope .. "close", ui, "onCloseWidget", function(original, self, ...)
            ReaderBar.uninstall(self)
            return original(self, ...)
        end)
    end
    return true
end

function ReaderBar.uninstall(ui)
    local state = ui._kindlespouse_reader_bar
    if not state then return end
    if state.overlay then state.overlay:close() end
    Patches.revertPrefix(state.scope)
    ui._kindlespouse_reader_bar = nil
end

return ReaderBar