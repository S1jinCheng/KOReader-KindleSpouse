local UIManager = require("ui/uimanager")
local FileManager = require("apps/filemanager/filemanager")
local Device = require("device")
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end
local Screen = Device.screen
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
local Home = require("home")
local original_init = FileManager.init
function FileManager:init()
    local original_setup = self.setupLayout
    local installed = false
    self.setupLayout = function(manager)
        if not installed then
            installed = true
            Home.install { ui = manager, notify = function() end }
        end
        return original_setup(manager)
    end
    original_init(self)
end
local function check(callback)
    local ok, failure = pcall(callback)
    if not ok then
        print("HOME ACCEPTANCE FAILED: " .. tostring(failure))
        UIManager:quit(1)
    end
end
local function capture(ui, filename)
    UIManager:widgetRepaint(ui, 0, 0)
    Screen:shot(filename)
end
local output = assert(os.getenv("KINDLESPOUSE_TEST_OUTPUT")) .. "/koreader-home-"
UIManager:scheduleIn(3, function() check(function()
    local ui = assert(FileManager.instance)
    assert(#ui.file_chooser.item_table == 8, "Nested books must be included and notebooks excluded")
    assert(ui.file_chooser.display_mode_type == "mosaic", "Real cover browser must be active")
    assert(ui.file_chooser.height == Screen:getHeight() - Home.navigationHeight())
    assert(ui[1]:getSize().h <= Screen:getHeight(), "Navigation must fit on screen")
    local navigation = ui.layout[#ui.layout]
    assert(#navigation == 2 and navigation[1].text == "Library" and navigation[2].text == "Notebook")
    assert(ui.title_bar.right_icon_tap_callback and ui.title_bar.left_icon_tap_callback)
    local FT = require("ffi/freetype")
    for _, filename in ipairs({ "NotoSerifCJKsc-Regular.otf", "NotoSansCJKsc-Regular.otf", "LXGWWenKai-Regular.ttf", "FandolFang-Regular.otf" }) do
        local face = FT.newFaceSize(assert(os.getenv("KINDLESPOUSE_TEST_FONTS")) .. "/" .. filename, 24)
        assert(face:getInfo().name ~= "")
        for _, codepoint in ipairs({ 0x4E66, 0x7B14, 0x8BB0, 0x9605, 0x3002 }) do assert(face:hasGlyph(codepoint), filename .. " lacks common Chinese glyphs") end
        face:done()
    end
    capture(ui, output .. "library.png")
    navigation[2].callback()
    UIManager:scheduleIn(0.5, function() check(function()
        assert(ui.kindlespouse_tab == "Notebook")
        assert(ui[1]:getSize().h <= Screen:getHeight(), "Notebook must fit on screen")
        assert(ui.title_bar.subtitle_widget.text == "Kindle Scribe")
        capture(ui, output .. "notebook.png")
        ui.layout[#ui.layout][1].callback()
        Screen:setRotationMode(1)
        ui:reinit(ui.file_chooser.path)
        UIManager:setDirty(ui, "full")
        UIManager:scheduleIn(0.5, function() check(function()
            assert(Screen:getWidth() > Screen:getHeight())
            assert(ui[1]:getSize().h <= Screen:getHeight(), "Landscape must fit on screen")
            capture(ui, output .. "landscape.png")
            Home.toggle { ui = ui }
            assert(not Home.enabled() and not ui.file_chooser.height)
            assert(G_reader_settings:readSetting("start_with") == "filemanager")
            Home.toggle { ui = ui }
            assert(Home.enabled() and #ui.file_chooser.item_table == 8)
            local closed, quit = false, false
            local original_kind, original_quit = Device.isKindle, UIManager.quit
            Device.isKindle = function() return true end
            UIManager.quit = function() quit = true end
            Home.returnToKindle { ui = { onClose = function() closed = true end } }
            Device.isKindle, UIManager.quit = original_kind, original_quit
            assert(closed and quit, "Native notebooks must use the normal save and exit path")
            print("KindleSpouse home acceptance passed")
            UIManager:quit()
        end) end)
    end) end)
end) end)
