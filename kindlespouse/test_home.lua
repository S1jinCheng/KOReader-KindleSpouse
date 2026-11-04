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
G_reader_settings:saveSetting("kindlespouse_library", { sort = "title" })
G_reader_settings:delSetting("kindlespouse_native_library")
if os.getenv("KINDLESPOUSE_TEST_INTEGRATED") ~= "1" then
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
UIManager:tickAfterNext(function()
UIManager:scheduleIn(3, function() check(function()
    local ui = assert(FileManager.instance)
    assert(Library.fonts.title == "NotoSerifCJKsc-Regular.otf" and Library.fonts.ui == "NotoSansCJKsc-Regular.otf")
    assert(#ui.file_chooser.item_table == 8, "Nested books must be included and notebooks excluded")
    assert(ui.kindlespouse_shelf and ui.kindlespouse_shelf.list_view, "Scrollable cover shelf must be active")
    assert(ui.file_chooser.height == Screen:getHeight() - Home.navigationHeight())
    assert(ui[1]:getSize().h <= Screen:getHeight(), "Navigation must fit on screen")
    local navigation = ui.layout[#ui.layout]
    assert(#navigation == 2 and navigation[1].text == require("i18n").T("library_tab") and navigation[2].text == require("i18n").T("notebook_tab"))
    assert(ui.title_bar.right_icon_tap_callback and ui.title_bar.left_icon_tap_callback)
    local FileChooser = require("ui/widget/filechooser")
    local original_shelf = ui.kindlespouse_shelf
    local original_reinit, rebuilds = ui.reinit, 0
    ui.reinit = function(manager, ...) rebuilds = rebuilds + 1; return original_reinit(manager, ...) end
    local previous_filter = FileChooser.show_filter
    FileChooser.show_filter = { status = { reading = true } }
    Library.refresh(ui, { shelf = "all" })
    assert(#ui.file_chooser.item_table == 8, "Library All must not inherit a hidden native file-browser status filter")
    FileChooser.show_filter = previous_filter
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
    assert(ui.kindlespouse_header and ui.kindlespouse_search)
    assert(ui.kindlespouse_toolbar[1].kindlespouse_action == "filter" and ui.kindlespouse_toolbar[3].kindlespouse_action == "sort")
    assert(Library.settings().sort == "recent" and Library.settings().view == "list", "Native layout must default to recent reading and list view after upgrading")
    capture(ui, output .. "native.png")
    local function status(index)
        local dialog = ui.kindlespouse_toolbar[1].callback()
        local options = dialog.item_table[1].callback()
        UIManager:close(dialog)
        options:onMenuSelect(options.item_table[index])
    end
    local files = ui.kindlespouse_catalog
    local BookList = require("ui/widget/booklist")
    BookList.book_info_cache[files[1].path] = { been_opened = true, status = "reading", percent_finished = 0.42 }
    BookList.book_info_cache[files[2].path] = { been_opened = true, status = "complete", percent_finished = 1 }
    Library.refresh(ui, {})
    capture(ui, output .. "native.png")
    status(2)
    assert(#ui.file_chooser.item_table == 6 and Library.settings().shelf == "new")
    status(3)
    assert(#ui.file_chooser.item_table == 1 and ui.file_chooser.item_table[1].path == files[1].path)
    status(4)
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
    Library.refresh(ui, { collection = "" })
    status(5)
    assert(#ui.file_chooser.item_table == 1)
    status(1)
    assert(#ui.file_chooser.item_table == 8 and Library.settings().shelf == "all")
    Library.refresh(ui, { shelf = "all", sort = "progress" })
    assert(ui.file_chooser.item_table[1].path == files[2].path)
    assert(rebuilds == 0 and ui.kindlespouse_shelf == original_shelf, "Filtering and sorting must preserve the shelf without reinit")
    Library.refresh(ui, { sort = "title", view = "list" })
    assert(ui.kindlespouse_shelf.list_view and ui.kindlespouse_shelf.columns == 1)
    assert(ui[1]:getSize().h <= Screen:getHeight())
    capture(ui, output .. "list.png")
    Library.refresh(ui, { sort = "recent", view = "grid" })
    assert(not ui.kindlespouse_shelf.list_view and #ui.file_chooser.item_table == 8)
    local history = require("readhistory")
    local previous_history = history.hist
    history.hist = { { file = files[4].path, time = 100 }, { file = files[3].path, time = 200 } }
    Library.refresh(ui, {})
    assert(ui.file_chooser.item_table[1].path == files[3].path and ui.file_chooser.item_table[2].path == files[4].path)
    history.hist = previous_history
    ReadCollection:removeItem(files[1].path, ReadCollection.default_collection_name)
    ReadCollection:removeCollection(collection)
    ReadCollection:write()
    capture(ui, output .. "library.png")
    local chooser, shelf = ui.file_chooser, ui.kindlespouse_shelf
    local header, content, library = ui.kindlespouse_header, ui.kindlespouse_content, ui.kindlespouse_library_group
    local frame, navigation = ui[1], ui.kindlespouse_navigation
    local original_notebook = Home.notebook
    local notebook_creations, notebook_pauses, notebook_resumes, notebook_frees, header_frees = 0, 0, 0, 0, 0
    Home.notebook = function(...)
        notebook_creations = notebook_creations + 1
        local body = original_notebook(...)
        local original_free = body.free
        body.onCloseWidget = function(widget) notebook_pauses = notebook_pauses + 1; widget.closed = true end
        body.refresh = function(widget) notebook_resumes = notebook_resumes + 1; widget.closed = false end
        body.free = function(widget, ...)
            notebook_frees = notebook_frees + 1
            return original_free(widget, ...)
        end
        return body
    end
    local header_free = header.free
    header.free = function(widget, ...)
        header_frees = header_frees + 1
        return header_free(widget, ...)
    end
    shelf:setScrolledOffset({ y = Screen:scaleBySize(60) })
    local scroll = shelf:getScrolledOffset().y
    assert(scroll > 0, "Eight-book grid fixture must exercise a nonzero scroll offset")
    local lfs = require("libs/libkoreader-lfs")
    local original_dir, scans, before = lfs.dir, 0, rebuilds
    lfs.dir = function(path, ...)
        if path == chooser.path then scans = scans + 1 end
        return original_dir(path, ...)
    end
    for index = 1, 20 do
        ui.layout[#ui.layout][2].callback()
        assert(ui.kindlespouse_content == content and content[1] == ui.kindlespouse_notebook_group)
        assert(ui.kindlespouse_search_label.text == require("i18n").T("search_notebooks"))
        assert(not ui.cropping_widget and not shelf.closed and not shelf.queued)
        assert(ui.title_bar.subtitle_widget.text == "Kindle Scribe")
        Library.refresh(ui, {})
        assert(ui.title_bar.subtitle_widget.text == "Kindle Scribe", "Background library updates must preserve the notebook title")
        UIManager:widgetRepaint(ui, 0, 0)
        ui.layout[#ui.layout][1].callback()
        assert(content[1] == library and ui.cropping_widget == shelf)
        assert(ui.kindlespouse_search_label.text == require("i18n").T("search_kindle"))
        assert(ui.file_chooser == chooser and ui.kindlespouse_shelf == shelf and ui.kindlespouse_header == header)
        assert(ui[1] == frame and ui.kindlespouse_navigation == navigation)
        assert(shelf:getScrolledOffset().y == scroll, "Tab changes must preserve the scrolled shelf")
        UIManager:widgetRepaint(ui, 0, 0)
    end
    ui.layout[#ui.layout][2].callback()
    ui:onHome()
    assert(ui.kindlespouse_tab == "Library" and ui.file_chooser == chooser and ui.kindlespouse_shelf == shelf)
    assert(shelf:getScrolledOffset().y == scroll and rebuilds == before and scans == 0)
    assert(notebook_creations == 1 and notebook_pauses == 21 and notebook_resumes == 20)
    assert(header_frees == 0 and notebook_frees == 0, "Cached bodies must not free the shared header")
    lfs.dir = original_dir
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
            assert(ui.file_chooser ~= chooser and ui.kindlespouse_shelf ~= shelf and shelf.closed)
            assert(header_frees == 1 and notebook_frees == 1, "Rotation must dispose both cached bodies and the shared header once")
            Home.notebook = original_notebook
            assert(ui[1]:getSize().h <= Screen:getHeight(), "Landscape must fit on screen")
            capture(ui, output .. "landscape.png")
            ui.layout[#ui.layout][2].callback()
            local hidden_shelf = ui.kindlespouse_shelf
            Home.toggle { ui = ui }
            assert(hidden_shelf.closed and not ui.kindlespouse_notebook_body and not ui.kindlespouse_content)
            assert(not Home.enabled() and not ui.file_chooser.height)
            assert(not ui.kindlespouse_shelf and not ui.cropping_widget)
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
            local final_shelf, final_header = ui.kindlespouse_shelf, ui.kindlespouse_header
            ui.layout[#ui.layout][2].callback()
            local final_body = ui.kindlespouse_notebook_body
            local body_closes, final_header_frees = 0, 0
            final_body.onCloseWidget = function(widget) body_closes = body_closes + 1; widget.closed = true end
            local final_free = final_header.free
            final_header.free = function(widget, ...)
                final_header_frees = final_header_frees + 1
                return final_free(widget, ...)
            end
            UIManager:close(ui)
            assert(final_shelf.closed and body_closes == 1 and final_header_frees == 1)
            assert(not ui.kindlespouse_content and not ui.kindlespouse_notebook_body)
            assert(not require("catalog").subscribers[ui], "Closing must detach catalog refresh callbacks")
            print("KindleSpouse body-only tab acceptance passed: 20 round trips, cached Home, zero rebuilds/scans, nonzero scroll and cleanup")
            print("KindleSpouse home acceptance passed")
            UIManager:quit()
        end) end)
    end) end)
end) end)
end)
