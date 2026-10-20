local UIManager = require("ui/uimanager")
local FileManager = require("apps/filemanager/filemanager")
local Device = require("device")
local Screen = Device.screen
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_NOTEBOOK_TEST_ROOT"))
local output = os.getenv("KINDLESPOUSE_TEST_OUTPUT") or project .. "/artifacts"
local experiment = os.getenv("KINDLESPOUSE_NOTEBOOK_EXPERIMENT") or project .. "/experiments/notebook"
local engine_directory = os.getenv("KINDLESPOUSE_NOTEBOOK_ENGINE") or project .. "/native/tools/notebook-koplugin/lua"
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end
require("ui/widget/menu").is_enable_shortcut = false
require("ui/widget/filechooser").is_enable_shortcut = false
package.path = (os.getenv("KINDLESPOUSE_TEST_PLUGIN") or project .. "/native/companion/plugin") .. "/?.lua;" .. package.path
local Home = require("home")
local Embedded = assert(loadfile(experiment .. "/embedded.lua"))()
local Import = assert(loadfile(experiment .. "/import.lua"))()
local engine = Embedded.new(engine_directory)
engine:install(Home)
local Library, Document, Stroke = engine.load("library"), engine.load("document"), engine.load("stroke")
assert(Library.ensureDir(""))
local titles = { "日常随记", "阅读摘记", "灵感手账", "工作思考", "旅行计划", "我的草稿" }
for index, title in ipairs(titles) do
    local document = Document:new(Library.abs(title .. ".scribe"))
    document:setTemplate(index % 2 == 0 and "grid" or "ruled")
    document.page_size = { w = 1860, h = 2200 }
    document.content_origin = { x = 0, y = 160 }
    for line = 1, 7 do
        for word = 1, 3 do
            local stroke = Stroke:new { tool = "pen", width = 4 + index % 3 }
            for point = 0, 80 do
                stroke:addPoint(150 + (word - 1) * 450 + point * 4,
                    380 + line * 170 + math.sin(point * 0.55 + index) * 36 + math.sin(point * 0.16) * 15, 0.7 + math.sin(point) * 0.2)
            end
            document:addStroke(stroke)
        end
    end
    document:addPage()
    document:goToPage(1)
    assert(document:save())
end
local original_init = FileManager.init
function FileManager:init()
    local original_setup, installed = self.setupLayout, false
    self.setupLayout = function(manager)
        if not installed then
            installed = true
            Home.install { ui = manager, notify = function() end }
        end
        return original_setup(manager)
    end
    original_init(self)
end

local failed = false
local function check(callback)
    local ok, error = pcall(callback)
    if not ok then
        failed = true
        print("EMBEDDED NOTEBOOK FAILED: " .. tostring(error))
        UIManager:quit(1)
    end
end
local function shot(ui, name)
    UIManager:widgetRepaint(ui, 0, 0)
    Screen:shot(output .. "/notebook-embedded-" .. name .. ".png")
end
local ui, editor, original_count
local function findCard(widget, path)
    if widget.item and widget.item.path == path and widget.onTap then return widget end
    for _, child in ipairs(widget) do
        if type(child) == "table" then
            local found = findCard(child, path)
            if found then return found end
        end
    end
end
UIManager:scheduleIn(3, function() check(function()
    ui = assert(FileManager.instance)
    ui.layout[#ui.layout][2].callback()
    assert(ui.kindlespouse_tab == "Notebook" and engine.gallery)
    assert(#engine.gallery.items == 6)
end) end)
UIManager:scheduleIn(7, function() check(function()
    shot(ui, "gallery")
    local navigation = ui.layout[#ui.layout]
    assert(navigation[1].dimen.y + navigation[1]:getSize().h <= Screen:getHeight())
    engine.gallery.query = "阅读"
    engine.gallery:_rebuild()
    assert(#engine.gallery.items == 1 and engine.gallery.items[1].name == "阅读摘记")
    engine.gallery.query = ""
    engine.gallery:_rebuild()
    assert(#engine.gallery.items == 6)
    local card = assert(findCard(engine.gallery, engine.gallery.items[1].path))
    card:onTap()
    editor = assert(engine.editor)
    assert(editor.document:pageCount() == 2)
    original_count = #editor.document:getPage().strokes
    assert(original_count == 21)
    editor.canvas.draw_with_finger = true
    local y = editor.canvas.content.y + 170
    editor.canvas:onTouchStart(nil, { pos = { x = 230, y = y } })
    for point = 1, 40 do
        editor.canvas:onTouchPan(nil, { pos = { x = 230 + point * 14, y = y + math.sin(point * 0.3) * 36 } })
    end
    editor.canvas:onTouchRelease(nil, { pos = { x = 790, y = y } })
    assert(#editor.document:getPage().strokes == original_count + 1, "Touch input must add a saved vector stroke")
    editor.undo_button.callback()
    assert(#editor.document:getPage().strokes == original_count)
    editor.redo_button.callback()
    assert(#editor.document:getPage().strokes == original_count + 1)
    editor.canvas.tool = "eraser"
    editor.canvas.eraser_mode = "stroke"
    editor.canvas:onTouchStart(nil, { pos = { x = 230, y = y } })
    editor.canvas:onTouchRelease(nil, { pos = { x = 230, y = y } })
    assert(#editor.document:getPage().strokes == original_count, "Eraser input must remove a complete stroke")
    editor.undo_button.callback()
    assert(#editor.document:getPage().strokes == original_count + 1)
    editor.canvas.tool = "pen"
    editor:_turnPage(1)
    assert(editor.document.current_page == 2)
    editor:_turnPage(-1)
    assert(editor.document.current_page == 1)
    shot(editor, "editor")
    editor:_close()
    assert(engine.editor == nil)
    local saved = Document:new(editor.document.path)
    assert(saved:load() and #saved:getPage().strokes == original_count + 1)
    ui.layout[#ui.layout][1].callback()
    assert(ui.kindlespouse_tab == "Library" and not engine.gallery)
    ui.layout[#ui.layout][2].callback()
    assert(ui.kindlespouse_tab == "Notebook" and #engine.gallery.items == 6)
    assert(Library.ensureDir("项目"))
    engine.gallery:_goTo("项目")
    assert(engine.gallery.folder == "项目" and #engine.gallery.items == 0)
    engine.gallery:_goTo("")
    assert(engine.gallery.folder == "" and #engine.gallery.items == 7)
end) end)
UIManager:scheduleIn(10, function() check(function()
    local data_file = assert(io.open(root .. "/native-vectors.json", "r"))
    local data = require("json").decode(data_file:read("*a"))
    data_file:close()
    local imported, counts = Import.document(engine.load, data, Library.abs("原生笔画导入测试.scribe"), { x = 0, y = 160, w = 1860, h = 2200 })
    assert(counts.strokes == 2 and counts.points == 6 and counts.pages == 2)
    local original = imported:getPage().strokes[1]
    assert(original.n == 3)
    imported:removeStrokes { original }
    assert(#imported:getPage().strokes == 1, "Imported original ink must be editable")
    assert(imported:undo())
    assert(#imported:getPage().strokes == 2)
    assert(imported:save())
    local reopened = Document:new(imported.path)
    assert(reopened:load() and reopened:pageCount() == 2 and reopened:getPage().strokes[1].n == 3)
    ui:reinit(ui.file_chooser.path)
    shot(ui, "saved")
    Screen:setRotationMode(1)
    ui:reinit(ui.file_chooser.path)
    shot(ui, "landscape")
    local private_file = io.open(root .. "/private-native-vectors.json", "r")
    if private_file then
        local original_data = require("json").decode(private_file:read("*a"))
        private_file:close()
        local copy, native_counts = Import.document(engine.load, original_data, Library.abs("离线旧笔记兼容测试.scribe"), { x = 0, y = 160, w = 1860, h = 2200 })
        assert(native_counts.pages == #original_data.pages and native_counts.strokes > 0)
        local original_stroke = assert(copy.pages[1].strokes[1])
        local original_points = original_stroke.n
        copy:removeStrokes { original_stroke }
        assert(copy:undo())
        assert(copy.pages[1].strokes[1] == original_stroke)
        copy:removeStrokes { original_stroke }
        local addition = Stroke:new { tool = "pen", width = 4 }
        addition:addPoint(200, 300, 1)
        addition:addPoint(300, 400, 0.7)
        copy:addStroke(addition)
        assert(copy:save())
        local persisted = Document:new(copy.path)
        assert(persisted:load() and persisted:pageCount() == native_counts.pages)
        assert(#persisted.pages[1].strokes == #original_data.pages[1].strokes)
        assert(persisted.pages[1].strokes[#persisted.pages[1].strokes].n == 2)
        print(string.format("Offline native Notebook edit passed: %d pages, %d original strokes, %d points in edited original stroke; source retained; edited copy saved and reopened.", native_counts.pages, native_counts.strokes, original_points))
    end
    print("Embedded Notebook acceptance passed: same-process gallery and editor, touch ink, undo/redo, atomic save and reopen, two-tab return, editable imported vectors, page count, portrait and landscape.")
    if not failed then UIManager:quit(0) end
end) end)
