local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Screen = Device.screen
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local output = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
local feature = os.getenv("KINDLESPOUSE_READER_FEATURE") or "highlight"
package.path = (os.getenv("KINDLESPOUSE_PLUGIN_DIR") or project .. "/plugins/kindlespouse.koplugin") .. "/?.lua;" .. package.path
local translations = {
    ["reader.highlight.yellow"] = "Yellow", ["reader.highlight.blue"] = "Blue",
    ["reader.highlight.purple"] = "Purple", ["reader.highlight.orange"] = "Orange",
    ["reader.highlight.note"] = "Note", ["reader.highlight.copy"] = "Copy",
    ["reader.highlight.dictionary"] = "Dictionary", ["reader.more"] = "More",
    ["reader.library"] = "← Library", ["reader.contents"] = "Contents",
    ["reader.bookmarks"] = "Bookmarks", ["reader.search"] = "Search",
    ["reader.appearance"] = "Aa", ["reader.book"] = "Book",
    ["reader.progress"] = "%1 / %2 · %3%", ["reader.remaining"] = "%1 left",
}
if not pcall(require, "i18n") then
    package.loaded.i18n = { T = function(key, ...)
        local arguments = { ... }
        return (translations[key] or key):gsub("%%(%d+)", function(index) return tostring(arguments[tonumber(index)]) end)
    end }
end
local Patches = require("patches")
local Highlight = require("reader/highlight_bar")
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end

local function paint(ui, name)
    if ReaderUI.instance then UIManager:widgetRepaint(ReaderUI.instance, 0, 0) end
    UIManager:widgetRepaint(ui, 0, 0)
    Screen:shot(output .. "/" .. name .. ".png")
end

local function tap(widget, button)
    local rectangle = assert(button.dimen)
    return widget:handleEvent(Event:new("Gesture", {
        ges = "tap", pos = Geom:new { x = rectangle.x + rectangle.w / 2, y = rectangle.y + rectangle.h / 2 },
    }))
end

local function closeAbove(ui)
    if ui.menu.menu_container then ui.menu:onCloseReaderMenu() end
    while UIManager:getTopmostVisibleWidget() and UIManager:getTopmostVisibleWidget() ~= ui do
        UIManager:close(UIManager:getTopmostVisibleWidget())
    end
end

local function select(ui)
    local position
    for y = Screen:scaleBySize(40), math.floor(Screen:getHeight() / 2), Screen:scaleBySize(8) do
        for x = Screen:scaleBySize(25), math.floor(Screen:getWidth() / 2), Screen:scaleBySize(25) do
            local candidate = Geom:new { x = x, y = y }
            local word = ui.document:getWordFromPosition(candidate, true)
            if word and word.word and #word.word > 2 then position = candidate; break end
        end
        if position then break end
    end
    assert(position, "Generated EPUB has no selectable word")
    ui.highlight:onHold(nil, { pos = position })
    assert(ui.highlight.selected_text and ui.highlight.selected_text.pos0)
    ui.highlight.is_word_selection = false
    ui.highlight:onHoldRelease()
    return ui.highlight.selected_text
end

local function highlights(ui)
    local highlight = ui.highlight
    local original = highlight.onShowHighlightMenu
    local buttons = highlight._highlight_buttons
    assert(Highlight.install(ui))
    assert(not Highlight.install(ui), "Highlight install must be idempotent")
    assert(not Highlight.install({ highlight = {} }))
    G_reader_settings:saveSetting("kindlespouse_reader", false)
    local migrated = Highlight.settings()
    assert(migrated.schema == 1 and not migrated.highlight_bar and not migrated.reader_bar)
    G_reader_settings:saveSetting("kindlespouse_reader", { highlight_bar = false, reader_bar = true })
    migrated = Highlight.settings()
    assert(migrated.schema == 1 and not migrated.highlight_bar and migrated.reader_bar)
    G_reader_settings:saveSetting("kindlespouse_reader", true)
    migrated = Highlight.settings()
    assert(migrated.schema == 1 and migrated.highlight_bar and migrated.reader_bar)
    local before = #ui.annotation.annotations
    highlight.view.highlight.saved_drawer = "invert"
    select(ui)
    local dialog = assert(highlight.highlight_dialog)
    assert(dialog.kindlespouse_highlight_bar)
    paint(dialog, "highlight")
    local rectangle = dialog:getContentSize()
    assert(rectangle.x >= 0 and rectangle.y >= 0 and rectangle.x + rectangle.w <= Screen:getWidth() and rectangle.y + rectangle.h <= Screen:getHeight())
    local yellow = assert(dialog:getButtonById("kindlespouse-color-yellow"))
    tap(dialog, yellow)
    assert(#ui.annotation.annotations == before + 1)
    assert(ui.annotation.annotations[#ui.annotation.annotations].color == "yellow")
    assert(ui.annotation.annotations[#ui.annotation.annotations].drawer == "lighten")
    assert(highlight.selected_text == nil and highlight.highlight_dialog == nil)
    yellow.callback()
    assert(#ui.annotation.annotations == before + 1, "Repeated stale action must not save twice")
    select(ui)
    local purple_dialog = assert(highlight.highlight_dialog)
    paint(purple_dialog, "highlight-purple")
    tap(purple_dialog, purple_dialog:getButtonById("kindlespouse-color-purple"))
    assert(ui.annotation.annotations[#ui.annotation.annotations].color == "purple")
    highlight:addToHighlightDialog("99_synthetic_thirdparty", function()
        return { text = "Synthetic third-party action", callback = function() end }
    end)
    local selected = select(ui)
    dialog = assert(highlight.highlight_dialog)
    paint(dialog, "highlight-more-before")
    local count = #ui.annotation.annotations
    tap(dialog, dialog:getButtonById("kindlespouse-highlight-more"))
    local stock = assert(highlight.highlight_dialog)
    assert(not stock.kindlespouse_highlight_bar and highlight.selected_text == selected)
    assert(#ui.annotation.annotations == count)
    local found = false
    for _, row in ipairs(stock.buttons) do
        for _, button in ipairs(row) do if button.text == "Synthetic third-party action" then found = true end end
    end
    assert(found and buttons == highlight._highlight_buttons, "More must preserve third-party builders")
    paint(stock, "highlight-stock-more")
    highlight:onClose()
    highlight:removeFromHighlightDialog("99_synthetic_thirdparty")
    Highlight.uninstall(ui)
    assert(highlight.onShowHighlightMenu == original)
    G_reader_settings:saveSetting("kindlespouse_reader", { highlight_bar = false })
    assert(not Highlight.install(ui))
    G_reader_settings:saveSetting("kindlespouse_reader", {})
    print("READER CHECK highlight: real selection, yellow and purple annotations, stale callback, More and original restoration passed")
end

UIManager:tickAfterNext(function()
    UIManager:scheduleIn(2, function()
        local ok, error = xpcall(function()
            local ui = assert(ReaderUI.instance)
            assert(ui.document and ui.rolling and ui.rolling.current_page > 0)
            assert(ui.document.info.number_of_pages > 3, "Fixture must load the generated multi-page EPUB, never an error document")
            if os.getenv("KINDLESPOUSE_TEST_INTEGRATED") == "1" then
                assert(ui._kindlespouse_highlight_bar, "Loaded plugin must install the highlight toolbar automatically")
                Highlight.uninstall(ui)
                local adapter = package.loaded["reader/init"]
                if adapter then adapter.uninstall(ui) end
            end
            local filename = ui.document.file
            if feature ~= "reader" then highlights(ui) end
            ui:onClose()
            if feature ~= "reader" then
                local saved = require("docsettings"):open(filename):readSetting("annotations")
                assert(type(saved) == "table" and #saved == 2)
                assert(saved[1].color == "yellow" and saved[2].color == "purple")
            end
            print("READER CHECK PASSED " .. feature)
        end, debug.traceback)
        if not ok then print("READER CHECK FAILED " .. tostring(error)) end
        UIManager:quit(ok and 0 or 1)
    end)
end)