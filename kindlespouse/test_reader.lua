local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Screen = Device.screen
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local output = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
local feature = os.getenv("KINDLESPOUSE_READER_FEATURE") or "all"
package.path = (os.getenv("KINDLESPOUSE_PLUGIN_DIR") or project .. "/plugins/kindlespouse.koplugin") .. "/?.lua;" .. package.path
local translations = {
    ["reader.highlight.yellow"] = "Yellow", ["reader.highlight.blue"] = "Blue",
    ["reader.highlight.purple"] = "Purple", ["reader.highlight.orange"] = "Orange",
    ["reader.highlight.note"] = "Note", ["reader.highlight.copy"] = "Copy",
    ["reader.highlight.dictionary"] = "Dictionary", ["reader.more"] = "More",
    ["reader.library"] = "← Library", ["reader.contents"] = "Contents",
    ["reader.bookmarks"] = "Bookmarks", ["reader.search"] = "Search",
    ["reader.appearance"] = "Aa", ["reader.book"] = "Book",
    ["reader.progress"] = "%1 / %2 · %3%",
    ["reader.remaining.minutes"] = "about %1 min", ["reader.remaining.hours"] = "about %1 h %2 min",
}
if not pcall(require, "i18n") then
    package.loaded.i18n = { T = function(key, ...)
        local arguments = { ... }
        return (translations[key] or key):gsub("%%(%d+)", function(index) return tostring(arguments[tonumber(index)]) end)
    end }
end
local Patches = require("patches")
local Highlight = require("reader/highlight_bar")
local ReaderBar
if feature ~= "highlight" then ReaderBar = require("reader/reader_bar") end
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
    local color_screen = os.getenv("KINDLESPOUSE_READER_SCREEN") == "color"
    assert(Screen:isColorScreen() == color_screen, "Profile must exercise the real screen capability API")
    assert(not Screen:isColorEnabled(), "Screen capability must be independent of color rendering settings")
    local global_drawer = G_reader_settings:readSetting("highlight_drawing_style")
    local global_color = G_reader_settings:readSetting("highlight_color")
    local before = #ui.annotation.annotations
    local choices = color_screen and { "yellow", "blue", "purple", "orange" } or { false }
    local stale
    local function checkChoices(dialog)
        assert(dialog.kindlespouse_highlight_bar)
        assert(#dialog.buttons[1] == #choices)
        assert((dialog:getButtonById("kindlespouse-highlight") ~= nil) == not color_screen)
        for _, name in ipairs({ "yellow", "blue", "purple", "orange" }) do
            assert((dialog:getButtonById("kindlespouse-color-" .. name) ~= nil) == color_screen)
        end
        if not color_screen then
            assert(dialog:getButtonById("kindlespouse-highlight").text == require("gettext")("Highlight"))
        end
    end
    local dialog
    for _, drawer in ipairs({ "lighten", "underscore", "strikeout", "invert" }) do
        highlight.view.highlight.saved_drawer = drawer
        highlight.view.highlight.saved_color = "green"
        for choice_index, color in ipairs(choices) do
            select(ui)
            dialog = assert(highlight.highlight_dialog)
            checkChoices(dialog)
            if stale then
                local count = #ui.annotation.annotations
                stale()
                assert(highlight.highlight_dialog == dialog and highlight.selected_text)
                assert(#ui.annotation.annotations == count, "Stale action must preserve a newer selection and dialog")
            end
            paint(dialog, "highlight-" .. (color or "monochrome") .. "-" .. drawer)
            local rectangle = dialog:getContentSize()
            assert(rectangle.x >= 0 and rectangle.y >= 0 and rectangle.x + rectangle.w <= Screen:getWidth() and rectangle.y + rectangle.h <= Screen:getHeight())
            local button = assert(dialog:getButtonById(color and "kindlespouse-color-" .. color or "kindlespouse-highlight"))
            local count = #ui.annotation.annotations
            local index
            if count == before then
                tap(dialog, button)
                index = #ui.annotation.annotations
            else
                index = dialog.buttons[1][choice_index].callback()
            end
            assert(#ui.annotation.annotations == count + 1)
            local annotation = assert(ui.annotation.annotations[index], "Action must return the upstream annotation index")
            assert(annotation.color == (color or "green") and annotation.drawer == drawer)
            assert(highlight.selected_text == nil and highlight.highlight_dialog == nil)
            assert(highlight.view.highlight.saved_drawer == drawer and highlight.view.highlight.saved_color == "green")
            assert(G_reader_settings:readSetting("highlight_drawing_style") == global_drawer)
            assert(G_reader_settings:readSetting("highlight_color") == global_color)
            stale = button.callback
            stale()
            assert(#ui.annotation.annotations == count + 1, "Repeated stale action must not save twice")
        end
    end
    highlight.view.highlight.saved_drawer = "underscore"
    for choice_index, color in ipairs(choices) do
        local selection = select(ui)
        selection.drawer = "strikeout"
        selection.color = "orange"
        dialog = assert(highlight.highlight_dialog)
        local index = dialog.buttons[1][choice_index].callback()
        assert(ui.annotation.annotations[index].drawer == "strikeout", "Selection-specific drawer must override saved drawer")
        assert(ui.annotation.annotations[index].color == (color or "orange"))
        assert(highlight.view.highlight.saved_drawer == "underscore" and highlight.view.highlight.saved_color == "green")
    end
    assert(#ui.annotation.annotations == before + #choices * 5)
    local expected = {}
    for index, annotation in ipairs(ui.annotation.annotations) do
        expected[index] = { color = annotation.color, drawer = annotation.drawer }
    end
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
    local selected_for_stale_more = select(ui)
    local stale_more_dialog = assert(highlight.highlight_dialog)
    local stale_more = stale_more_dialog:getButtonById("kindlespouse-highlight-more").callback
    highlight:onClose()
    select(ui)
    dialog = assert(highlight.highlight_dialog)
    assert(highlight.selected_text ~= selected_for_stale_more)
    stale_more()
    assert(highlight.highlight_dialog == dialog and dialog.kindlespouse_highlight_bar)
    highlight:onSetDimensions({ w = Screen:getWidth(), h = Screen:getHeight() })
    assert(highlight.highlight_dialog == nil and highlight.selected_text == nil)
    select(ui)
    dialog = assert(highlight.highlight_dialog)
    dialog.tap_close_callback()
    UIManager:close(dialog)
    assert(highlight.highlight_dialog == nil and highlight.selected_text == nil)
    select(ui)
    Highlight.uninstall(ui)
    assert(highlight.highlight_dialog == nil and highlight.selected_text == nil)
    assert(highlight.onShowHighlightMenu == original)
    G_reader_settings:saveSetting("kindlespouse_reader", { highlight_bar = false })
    assert(not Highlight.install(ui))
    G_reader_settings:saveSetting("kindlespouse_reader", {})
    print("READER CHECK highlight: " .. (color_screen and "color" or "monochrome") .. ", all drawer styles, per-selection overrides, defaults, stale callbacks, More, third-party builders and lifecycle passed")
    return expected
end

local function readerBar(ui)
    local original = ui.menu.onTapShowMenu
    assert(ReaderBar.install(ui))
    assert(not ReaderBar.install(ui))
    assert(not ReaderBar.install({ menu = {} }))
    ui.menu.activation_menu = "swipe"
    assert(ui.menu:onTapShowMenu({ pos = Geom:new { x = 10, y = 10 } }) == nil)
    assert(not ui._kindlespouse_reader_bar.overlay)
    ui.menu.activation_menu = "tap"
    local function open()
        assert(ui.menu:onTapShowMenu({ pos = Geom:new { x = Screen:getWidth() / 2, y = 10 } }))
        local bar = assert(ui._kindlespouse_reader_bar.overlay)
        paint(bar, "reader-bar")
        return bar
    end
    local engine = ui.rolling or ui.paging
    local location = engine.current_page
    local dimensions = ui.view.dimen:copy()
    local footer_visible = ui.view.footer_visible
    local footer_settings = require("rapidjson").encode(ui.view.footer.settings, { sort_keys = true })
    local document_settings = require("rapidjson").encode(ui.doc_settings.data, { sort_keys = true })
    local bar = open()
    paint(bar, "reader-body-unobscured")
    assert(bar.top_rect.h < Screen:getHeight() / 3 and bar.bottom_rect.h < Screen:getHeight() / 3)
    assert(bar.title == "A Quiet Morning", "Only the redundant trailing reading marker is removed")
    assert(engine.current_page == location and ui.view.dimen == dimensions)
    assert(ui.view.footer_visible == footer_visible)
    assert(require("rapidjson").encode(ui.view.footer.settings, { sort_keys = true }) == footer_settings)
    assert(require("rapidjson").encode(ui.doc_settings.data, { sort_keys = true }) == document_settings)
    if ui.statistics then
        assert(bar.progress_text.text:find("about", 1, true), "Available statistics must supply remaining time")
    else
        assert(not bar.progress_text.text:find("about", 1, true), "Disabled statistics must not invent remaining time")
    end
    local Blitbuffer = require("ffi/blitbuffer")
    local source = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Screen.bb:getType())
    source:fill(Blitbuffer.COLOR_WHITE)
    ui.view:paintTo(source, 0, 0)
    source:writePNG(output .. "/reader-source.png")
    local expected = require("ui/renderimage"):scaleBlitBuffer(source, bar.viewport_rect.w, bar.viewport_rect.h, false)
    expected:writePNG(output .. "/reader-expected-viewport.png")
    local function compareBuffer(buffer, x, y)
        for row = 0, buffer:getHeight() - 1 do
            for column = 0, buffer:getWidth() - 1 do
                local actual = Screen.bb:getPixel(x + column, y + row)
                local pixel = buffer:getPixel(column, row)
                assert(actual:getR() == pixel:getR() and actual:getG() == pixel:getG() and actual:getB() == pixel:getB(), "Entire viewport pixels must be retained or restored exactly")
            end
        end
    end
    local viewport, body = bar.viewport_rect, bar.body_rect
    assert(viewport.y >= body.y and viewport.y + viewport.h <= body.y + body.h)
    compareBuffer(expected, viewport.x, viewport.y)
    local function solidRow(y, color, from, to)
        for x = from or 0, (to or Screen:getWidth()) - 1 do
            if Screen.bb:getPixel(x, y):getColor8().a ~= color then return false end
        end
        return true
    end
    for _, y in ipairs({ bar.top_rect.h, bar.bottom_rect.y - 1 }) do
        assert(solidRow(y, 0), "Separators must span exactly one physical row")
        assert(not solidRow(y - 1, 0) and not solidRow(y + 1, 0), "Separator must not grow with DPI")
    end
    for y = body.y, body.y + body.h - 1 do
        assert(solidRow(y, 255, 0, viewport.x) and solidRow(y, 255, viewport.x + viewport.w, Screen:getWidth()), "Unscaled text must be cleared behind the fitted viewport")
    end
    local draw = ui.view.paintTo
    local new_buffer = Blitbuffer.new
    local allocated
    Blitbuffer.new = function(...)
        allocated = new_buffer(...)
        return allocated
    end
    ui.view.paintTo = function() error("synthetic render failure") end
    assert(not pcall(bar.paintTo, bar, Screen.bb))
    ui.view.paintTo = draw
    Blitbuffer.new = new_buffer
    assert(allocated:getAllocated() == 0 and not bar.painting, "Render failures must free the temporary framebuffer and reset recursion state")
    local renderer = require("ui/renderimage")
    local scale = renderer.scaleBlitBuffer
    renderer.scaleBlitBuffer = function(_, buffer)
        allocated = buffer
        error("synthetic scaling failure")
    end
    assert(not pcall(bar.paintTo, bar, Screen.bb))
    renderer.scaleBlitBuffer = scale
    assert(allocated:getAllocated() == 0, "Scaling failures must free the temporary framebuffer")
    ui.view.paintTo = function(self, buffer, ...)
        bar:paintTo(buffer)
        return draw(self, buffer, ...)
    end
    bar:paintTo(Screen.bb)
    ui.view.paintTo = draw
    assert(not bar.painting, "Recursive view modules must not recursively render the toolbar")
    expected:free()
    local geometry = assert(io.open(output .. "/reader-geometry.json", "w"))
    geometry:write(require("rapidjson").encode({ top = bar.top_rect, bottom = bar.bottom_rect, body = bar.body_rect, viewport = bar.viewport_rect }))
    geometry:close()
    local statistics = ui.statistics
    local language = G_reader_settings:readSetting("language")
    local left = ui.document.info.number_of_pages - engine.current_page
    assert(left > 0)
    for _, locale in ipairs({ "en", "zh_CN" }) do
        G_reader_settings:saveSetting("language", locale)
        for _, case in ipairs({ { 0, 0 }, { 29, 0 }, { 30, 1 }, { 3569, 59 }, { 3570, 60 }, { 3599, 60 }, { 3600, 60 }, { 3629, 60 }, { 3630, 61 }, { 7199, 120 } }) do
            ui.statistics = { settings = { is_enabled = true }, avg_time = case[1] / left,
                getTimeForPages = function() error("Presentation strings must never be parsed") end }
            bar:refreshProgress()
            local minutes = case[2]
            local text
            if locale == "zh_CN" then
                text = minutes < 60 and ("约 " .. minutes .. " 分钟")
                    or ("约 " .. math.floor(minutes / 60) .. " 小时 " .. minutes % 60 .. " 分")
            else
                text = minutes < 60 and ("about " .. minutes .. " min")
                    or ("about " .. math.floor(minutes / 60) .. " h " .. minutes % 60 .. " min")
            end
            assert(bar.progress_text.text:sub(-#text) == text, "Remaining time rounding or localization failed")
        end
        for _, average in ipairs({ false, -1, math.huge, 0 / 0 }) do
            ui.statistics.avg_time = average
            bar:refreshProgress()
            assert(not bar.progress_text.text:find("about", 1, true) and not bar.progress_text.text:find("约", 1, true))
        end
        ui.statistics = { settings = { is_enabled = false }, avg_time = 30 }
        bar:refreshProgress()
        assert(not bar.progress_text.text:find("about", 1, true) and not bar.progress_text.text:find("约", 1, true))
    end
    ui.statistics = statistics
    G_reader_settings:saveSetting("language", "zh_CN")
    bar:refreshProgress()
    paint(bar, "reader-bar-zh")
    G_reader_settings:saveSetting("language", language)
    bar:refreshProgress()
    assert(bar.bottom:getSize().w == Screen:getWidth(), "Bottom panel must cover the stock footer without gaps")
    bar:handleEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new { x = 20, y = Screen:getHeight() / 2 } }))
    assert(not ui._kindlespouse_reader_bar.overlay)
    paint(ui, "reader-restored")
    compareBuffer(source, 0, 0)
    source:free()
    print("READER CHECK pixels: complete viewport, blank gutters, 1 physical pixel separators and exact restoration passed")
    assert(engine.current_page == location and ui.view.dimen == dimensions and ui.view.footer_visible == footer_visible)
    G_reader_settings:saveSetting("language", "zh_CN")
    bar = open()
    assert(bar.actions.library.text == "← 书库" and bar.actions.toc.text == "目录")
    paint(bar, "reader-body-unobscured-zh")
    bar:close()
    G_reader_settings:saveSetting("language", language)
    local title = ui.doc_props.display_title
    for _, text in ipairs({ "阅读 · A Quiet Morning", "A · 阅读 · Morning", "A Quiet Morning · Reading", "文学·阅读" }) do
        ui.doc_props.display_title = text
        bar = open()
        assert(bar.title == text, "Meaningful title text must be retained")
        bar:close()
    end
    ui.doc_props.display_title = "A Quiet Morning  ·  阅读  "
    bar = open()
    assert(bar.title == "A Quiet Morning")
    bar:close()
    ui.doc_props.display_title = title
    local counts = {}
    local hooks = {
        { "toc", ui.toc, "onShowToc" }, { "bookmarks", ui.bookmark, "onShowBookmark" },
        { "search", ui.search, "onShowFulltextSearchInput" }, { "appearance", ui.config, "onShowConfigMenu" },
        { "more", ui.menu, "onShowMenu" },
    }
    for _, hook in ipairs(hooks) do
        local key, target, method = hook[1], hook[2], hook[3]
        local upstream = assert(target[method])
        target[method] = function(self, ...)
            counts[key] = (counts[key] or 0) + 1
            return upstream(self, ...)
        end
        bar = open()
        tap(bar, bar.actions[key])
        assert(counts[key] == 1 and not ui._kindlespouse_reader_bar.overlay)
        if key == "more" then
            assert(ui.menu.menu_container and ui.menu.menu_container[1])
            paint(ui.menu.menu_container, "reader-stock-more")
        end
        closeAbove(ui)
        target[method] = upstream
    end
    bar = open()
    local rectangle = assert(bar.scrubber.dimen)
    local function scrub(kind, ratio)
        bar:handleEvent(Event:new("Gesture", { ges = kind, pos = Geom:new { x = rectangle.x + rectangle.w * ratio, y = rectangle.y + rectangle.h / 2 } }))
    end
    local first = engine.current_page
    scrub("pan", 0.7)
    assert(engine.current_page == first, "Pan previews progress before committing")
    scrub("pan_release", 0.7)
    assert(engine.current_page > first)
    scrub("tap", 0.2)
    assert(math.abs(engine:getLastPercent() - 0.2) < 0.1)
    bar:close()
    bar = open()
    ui.menu:onSetDimensions(Screen:getSize())
    assert(bar.closed and not ui._kindlespouse_reader_bar.overlay)
    local rotation = Screen:getRotationMode()
    for _, mode in ipairs({ (rotation + 1) % 4, rotation }) do
        bar = open()
        ui.view:onSetRotationMode(mode)
        assert(bar.closed and not ui._kindlespouse_reader_bar.overlay, "Rotation must close the old viewport")
        closeAbove(ui)
        local page = engine.current_page
        local rotated_footer = ui.view.footer_visible
        bar = open()
        assert(bar.dimen.w == Screen:getWidth() and bar.dimen.h == Screen:getHeight())
        assert(bar.viewport_rect.y >= bar.body_rect.y and bar.viewport_rect.y + bar.viewport_rect.h <= bar.bottom_rect.y - 1)
        paint(bar, mode == rotation and "reader-portrait-restored" or "reader-landscape")
        bar:close()
        assert(engine.current_page == page and ui.view.footer_visible == rotated_footer)
    end
    bar = open()
    ReaderBar.uninstall(ui)
    assert(bar.closed and ui.view.dimen == dimensions and ui.view.footer_visible == footer_visible)
    assert(ui.menu.onTapShowMenu == original)
    G_reader_settings:saveSetting("kindlespouse_reader", { reader_bar = false })
    assert(not ReaderBar.install(ui))
    G_reader_settings:saveSetting("kindlespouse_reader", {})
    local Reader = require("reader/init")
    Reader.install(ui)
    assert(ui._kindlespouse_reader_bar and ui._kindlespouse_highlight_bar)
    G_reader_settings:saveSetting("kindlespouse_reader", { schema = 1, highlight_bar = false, reader_bar = true })
    Reader.install(ui)
    assert(ui._kindlespouse_reader_bar and not ui._kindlespouse_highlight_bar)
    G_reader_settings:saveSetting("kindlespouse_reader", { schema = 1, highlight_bar = true, reader_bar = false })
    Reader.install(ui)
    assert(not ui._kindlespouse_reader_bar and ui._kindlespouse_highlight_bar)
    G_reader_settings:saveSetting("kindlespouse_reader", true)
    Reader.install(ui)
    local back = ui.onHome
    local called = 0
    ui.onHome = function(self, ...) called = called + 1; return back(self, ...) end
    bar = open()
    tap(bar, bar.actions.library)
    assert(called == 1)
    assert(not ui._kindlespouse_reader_bar and not ui._kindlespouse_highlight_bar)
    for id in pairs(Patches.applied) do assert(not id:find("reader:" .. tostring(ui) .. ":", 1, true)) end
    print("READER CHECK bar: gesture condition, outside dismiss, real upstream hooks, drag/tap navigation and lifecycle restoration passed")
end

UIManager:tickAfterNext(function()
    UIManager:scheduleIn(2, function()
        local ok, error = xpcall(function()
            local ui = assert(ReaderUI.instance)
            assert(ui.document and (ui.rolling or ui.paging) and (ui.rolling or ui.paging).current_page > 0)
            assert(ui.document.info.number_of_pages > 3, "Fixture must load the generated multi-page EPUB, never an error document")
            if os.getenv("KINDLESPOUSE_TEST_INTEGRATED") == "1" then
                assert(ui._kindlespouse_highlight_bar, "Loaded plugin must install the highlight toolbar automatically")
                assert(ui._kindlespouse_reader_bar, "Loaded plugin must install the reader toolbar automatically")
                require("reader/init").uninstall(ui)
            end
            local filename = ui.document.file
            local expected
            if feature ~= "reader" then expected = highlights(ui) end
            if feature ~= "highlight" then readerBar(ui) end
            if feature == "highlight" then ui:onClose() end
            if feature ~= "reader" then
                local settings = require("docsettings"):open(filename)
                local saved = settings:readSetting("annotations")
                assert(type(saved) == "table" and #saved == #expected)
                for index, annotation in ipairs(saved) do
                    assert(annotation.color == expected[index].color and annotation.drawer == expected[index].drawer, "Persisted annotations must retain drawer and color")
                end
                assert(settings:readSetting("highlight_drawer") == "underscore" and settings:readSetting("highlight_color") == "green")
                print("READER CHECK persisted: " .. #saved .. " annotation drawers and colors plus document defaults passed")
            end
            print("READER CHECK PASSED " .. feature)
        end, debug.traceback)
        if not ok then print("READER CHECK FAILED " .. tostring(error)) end
        UIManager:quit(ok and 0 or 1)
    end)
end)
