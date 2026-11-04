local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Patches = require("patches")
local T = require("i18n").T
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local Screen = Device.screen
local Highlight = {}

function Highlight.settings()
    local previous = G_reader_settings:readSetting("kindlespouse_reader")
    if type(previous) == "table" and previous.schema == 1
        and type(previous.highlight_bar) == "boolean" and type(previous.reader_bar) == "boolean" then return previous end
    local settings = { schema = 1, highlight_bar = previous ~= false, reader_bar = previous ~= false }
    if type(previous) == "table" then
        for key, value in pairs(previous) do settings[key] = value end
        settings.schema = 1
        settings.highlight_bar = previous.highlight_bar ~= false
        settings.reader_bar = previous.reader_bar ~= false
    end
    G_reader_settings:saveSetting("kindlespouse_reader", settings)
    return settings
end

local function closeDialog(highlight)
    local dialog = highlight.highlight_dialog
    if dialog and dialog.kindlespouse_highlight_bar then
        highlight.highlight_dialog = nil
        UIManager:close(dialog)
    end
end

local function anchor(highlight, dialog)
    local selected = highlight.selected_text
    local boxes = selected and (selected.sboxes or selected.pboxes)
    if type(boxes) ~= "table" or not boxes[1] then return end
    local first, last = boxes[1], boxes[#boxes]
    if highlight.ui.paging then
        local page = type(selected.pos0) == "table" and selected.pos0.page
        if not page or type(highlight.view.pageToScreenTransform) ~= "function" then return end
        first = highlight.view:pageToScreenTransform(page, first)
        last = highlight.view:pageToScreenTransform(page, last)
    end
    if not first or not last then return end
    local padding = Screen:scaleBySize(6)
    local top = math.max(0, math.min(first.y, last.y) - padding)
    local bottom = math.min(Screen:getHeight(), math.max(first.y + first.h, last.y + last.h) + padding)
    local height = dialog:getContentSize().h
    if bottom + height <= Screen:getHeight() then return { y = bottom }, true end
    if top >= height then return { y = top } end
    return { y = math.max(height, math.min(Screen:getHeight(), top)) }
end

local function action(highlight, key, label)
    local builder = highlight._highlight_buttons[key]
    if type(builder) ~= "function" then return end
    local button = builder(highlight)
    if type(button) ~= "table" or type(button.callback) ~= "function" then return end
    if button.show_in_highlight_dialog_func and not button.show_in_highlight_dialog_func() then return end
    button.text = T(label)
    return button
end

function Highlight.install(ui)
    if not Highlight.settings().highlight_bar or ui._kindlespouse_highlight_bar then return false end
    local highlight = ui.highlight
    if not highlight or type(highlight.onShowHighlightMenu) ~= "function"
        or type(highlight.saveHighlight) ~= "function" or type(highlight.clear) ~= "function"
        or type(highlight._highlight_buttons) ~= "table" then return false end
    local scope = "reader:" .. tostring(ui) .. ":highlight:"
    ui._kindlespouse_highlight_bar = { scope = scope, highlight = highlight }
    Patches.wrap(scope .. "menu", highlight, "onShowHighlightMenu", function(original, self, index)
        local selected = self.selected_text
        if index ~= nil or not selected or not selected.pos0 or not selected.pos1 or not self.hold_pos then
            return original(self, index)
        end
        local note = action(self, "04_add_note", "reader.highlight.note")
        local copy = action(self, "03_copy", "reader.highlight.copy")
        local dictionary = action(self, "06_dictionary", "reader.highlight.dictionary")
        if not note or not copy or not dictionary then return original(self, index) end
        closeDialog(self)
        local choices = Screen:isColorScreen() and { "yellow", "blue", "purple", "orange" } or { false }
        local colors = {}
        for _, color in ipairs(choices) do
            local name = color
            colors[#colors + 1] = {
                id = name and "kindlespouse-color-" .. name or "kindlespouse-highlight",
                text = name and T("reader.highlight." .. name) or gettext("Highlight"),
                background = name and Blitbuffer.colorFromName(name) or nil,
                callback = function()
                    if self.selected_text ~= selected then return end
                    closeDialog(self)
                    if name then selected.color = name end
                    local saved = self:saveHighlight()
                    self:clear()
                    return saved
                end,
            }
        end
        note.id, copy.id, dictionary.id = "kindlespouse-note", "kindlespouse-copy", "kindlespouse-dictionary"
        local dialog
        dialog = ButtonDialog:new {
            width = math.min(Screen:getWidth() - Screen:scaleBySize(24), Screen:scaleBySize(460)),
            buttons = {
                colors,
                { note, copy, dictionary, {
                    id = "kindlespouse-highlight-more", text = T("reader.more"),
                    callback = function()
                        if self.selected_text ~= selected then return end
                        closeDialog(self)
                        return original(self, nil)
                    end,
                } },
            },
            anchor = function() return anchor(self, dialog) end,
            tap_close_callback = function()
                if self.highlight_dialog == dialog then self.highlight_dialog = nil end
                if self.selected_text == selected then self:clear() end
            end,
        }
        for _, name in ipairs({ "blue", "purple" }) do
            local button = dialog:getButtonById("kindlespouse-color-" .. name)
            if button and button.label_widget then button.label_widget.fgcolor = Blitbuffer.COLOR_WHITE end
        end
        dialog.kindlespouse_highlight_bar = true
        self.highlight_dialog = dialog
        UIManager:show(dialog)
        return true
    end)
    if type(highlight.onSetDimensions) == "function" then
        Patches.wrap(scope .. "dimensions", highlight, "onSetDimensions", function(original, self, ...)
            if self.highlight_dialog and self.highlight_dialog.kindlespouse_highlight_bar then self:onClose() end
            return original(self, ...)
        end)
    end
    if type(ui.onCloseWidget) == "function" then
        Patches.wrap(scope .. "close", ui, "onCloseWidget", function(original, self, ...)
            Highlight.uninstall(self)
            return original(self, ...)
        end)
    end
    return true
end

function Highlight.uninstall(ui)
    local state = ui._kindlespouse_highlight_bar
    if not state then return end
    if state.highlight.highlight_dialog and state.highlight.highlight_dialog.kindlespouse_highlight_bar then
        state.highlight:onClose()
    end
    Patches.revertPrefix(state.scope)
    ui._kindlespouse_highlight_bar = nil
end

return Highlight
