local UIManager = require("ui/uimanager")
local FileManager = require("apps/filemanager/filemanager")
local Device = require("device")
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end
local Screen = Device.screen
require("ui/widget/menu").is_enable_shortcut = false
require("ui/widget/filechooser").is_enable_shortcut = false
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
local Home = require("home")
local Library = require("library")
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
    local navigation = ui.layout[#ui.layout]
    assert(navigation[1].dimen.y + navigation[1]:getSize().h <= Screen:getHeight(), "Bottom tabs must remain on screen")
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
    local manifest_file = assert(io.open(project .. "/kindlespouse/fonts.json", "r"))
    local font_manifest = require("json").decode(manifest_file:read("*a"))
    manifest_file:close()
    local font_count = 0
    for _, asset in ipairs(font_manifest.assets) do
        if asset.style then
        local filename = asset.filename
        local face = FT.newFaceSize(assert(os.getenv("KINDLESPOUSE_TEST_FONTS")) .. "/" .. filename, 24)
        assert(face:getInfo().name ~= "")
        for _, codepoint in ipairs({ 0x4E66, 0x7B14, 0x8BB0, 0x9605, 0x3002 }) do assert(face:hasGlyph(codepoint), filename .. " lacks common Chinese glyphs") end
        face:done()
        font_count = font_count + 1
        end
    end
    assert(font_count == 10)
    assert(ui.kindlespouse_toolbar and #ui.kindlespouse_toolbar[1] == 4 and #ui.kindlespouse_toolbar[2] == 6)
    local files = ui.kindlespouse_catalog
    local BookList = require("ui/widget/booklist")
    BookList.book_info_cache[files[1].path] = { been_opened = true, status = "reading", percent_finished = 0.42 }
    BookList.book_info_cache[files[2].path] = { been_opened = true, status = "complete", percent_finished = 1 }
    ui.kindlespouse_toolbar[2][2].callback()
    assert(#ui.file_chooser.item_table == 6 and Library.settings().shelf == "new")
    ui.kindlespouse_toolbar[2][3].callback()
    assert(#ui.file_chooser.item_table == 1 and ui.file_chooser.item_table[1].path == files[1].path)
    ui.kindlespouse_toolbar[2][4].callback()
    assert(#ui.file_chooser.item_table == 1 and ui.file_chooser.item_table[1].path == files[2].path)
    Library.refresh(ui, { shelf = "all", query = files[3].kindlespouse.title })
    assert(#ui.file_chooser.item_table == 1)
    Library.refresh(ui, { query = "不存在的书名" })
    assert(#ui.file_chooser.item_table == 0)
    Library.refresh(ui, { query = "", source = "nested" })
    assert(#ui.file_chooser.item_table == 4)
    Library.refresh(ui, { source = "", format = "pdf" })
    assert(#ui.file_chooser.item_table == 0)
    Library.refresh(ui, { format = "epub", author = "不存在的作者" })
    assert(#ui.file_chooser.item_table == 0)
    local author = files[1].kindlespouse.author
    Library.refresh(ui, { author = author })
    assert(#ui.file_chooser.item_table > 0)
    local ReadCollection = require("readcollection")
    local collection = "KindleSpouse 验收书集"
    if ReadCollection.coll[collection] then ReadCollection:removeCollection(collection) end
    ReadCollection:addCollection(collection)
    ReadCollection:addItem(files[1].path, collection)
    ReadCollection:addItem(files[3].path, collection)
    ReadCollection:addItem(files[1].path, ReadCollection.default_collection_name)
    ReadCollection:write()
    Library.refresh(ui, { author = "", format = "", collection = collection })
    assert(#ui.file_chooser.item_table == 2 and Library.settings().collection == collection)
    Library.refresh(ui, { collection = "", shelf = "favorites" })
    assert(#ui.file_chooser.item_table == 1)
    Library.refresh(ui, { shelf = "all", sort = "progress" })
    assert(ui.file_chooser.item_table[1].path == files[2].path)
    Library.refresh(ui, { sort = "title", view = "list" })
    assert(ui.file_chooser.display_mode_type == "list")
    assert(ui[1]:getSize().h <= Screen:getHeight())
    capture(ui, output .. "list.png")
    Library.refresh(ui, { sort = "recent", view = "grid" })
    assert(ui.file_chooser.display_mode_type == "mosaic" and #ui.file_chooser.item_table == 8)
    ReadCollection:removeItem(files[1].path, ReadCollection.default_collection_name)
    ReadCollection:removeCollection(collection)
    ReadCollection:write()
    capture(ui, output .. "library.png")
    ui.layout[#ui.layout][2].callback()
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
