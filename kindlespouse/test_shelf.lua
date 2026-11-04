io.stdout:setvbuf("no")
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
local lfs = require("libs/libkoreader-lfs")
local Catalog = require("catalog")
local registry = require("document/documentregistry")
local time = require("ui/time")
local json = require("json")
local root = G_reader_settings:readSetting("home_dir")
local scans, opens, rebuilds, resolutions = 0, 0, 0, 0
local ffiUtil = require("ffi/util")
local realpath = ffiUtil.realpath
ffiUtil.realpath = function(...) resolutions = resolutions + 1; return realpath(...) end
local sidecar_scans = 0
local directory = lfs.dir
lfs.dir = function(path, ...)
    if path:sub(1, #root) == root then
        if path:find("%.sdr[/]?") then sidecar_scans = sidecar_scans + 1 else scans = scans + 1 end
    end
    return directory(path, ...)
end
local original_open = registry.openDocument
registry.openDocument = function(self, ...)
    opens = opens + 1
    return original_open(self, ...)
end
local function check(fn)
    local ok, error = pcall(fn)
    if not ok then print("SHELF ACCEPTANCE FAILED: " .. tostring(error)); UIManager:quit(1) end
end
local attempts = 0
local function ready()
    check(function()
        attempts = attempts + 1
        assert(attempts < 1600, "Catalog did not become ready")
        local state = Catalog.roots[root]
        if attempts % 20 == 0 then print("Shelf wait", attempts, state and state.scanning, #Catalog.records(root), require("extractor").isBusy()) end
        if not state or state.scanning or #Catalog.records(root) ~= 500 or require("extractor").isBusy() then
            UIManager:scheduleIn(0.1, ready)
            return
        end
        local ui = assert(FileManager.instance)
        local shelf = assert(ui.kindlespouse_shelf)
        local old_reinit = ui.reinit
        ui.reinit = function(manager, ...) rebuilds = rebuilds + 1; return old_reinit(manager, ...) end
        scans, opens, resolutions = 0, 0, 0
        local samples = {}
        local function refresh(changes)
            local begin = time.now()
            Library.refresh(ui, changes)
            local elapsed = time.to_ms(time.now() - begin)
            assert(ui.kindlespouse_shelf == shelf and shelf.items == ui.file_chooser.item_table)
            local expected = Library.apply(Catalog.items(ui.file_chooser), Library.settings())
            assert(#expected == #shelf.items)
            for index, item in ipairs(expected) do assert(item.path == shelf.items[index].path) end
            samples[#samples+1] = elapsed
        end
        for _ = 1, 5 do
            for _, filter in ipairs({"all", "new", "reading", "complete", "favorites"}) do refresh({shelf=filter}) end
            refresh({shelf="all"})
            for _, sort in ipairs({"title", "author", "added"}) do refresh({sort=sort}) end
            refresh({query="Fixture Book 42"})
            assert(#shelf.items > 0 and #shelf.items < 500)
            refresh({query="", shelf="all", sort="recent"})
            assert(#shelf.items == 500)
        end
        shelf:setScrolledOffset({y=shelf.row_h * 2})
        refresh({sort="title"})
        assert(shelf:getScrolledOffset().y == shelf.row_h * 2)
        refresh({query="no such book"})
        assert(#shelf.items == 0 and shelf:getScrolledOffset().y == 0)
        refresh({query=""})
        assert(scans == 0 and opens == 0 and rebuilds == 0 and resolutions == 0, "Hot actions must not scan, open documents or rebuild")
        print("KindleSpouse shelf observations " .. json.encode({books=500, refreshMilliseconds=samples,
            hotDirectoryScans=scans, hotDocumentOpens=opens, hotRebuilds=rebuilds, hotPathResolutions=resolutions, runs=5}))
        UIManager:widgetRepaint(ui, 0, 0)
        Screen:shot(assert(os.getenv("KINDLESPOUSE_TEST_OUTPUT")) .. "/catalog-500.png")
        local book = shelf.items[1].path
        Home.uninstall(ui)
        registry.openDocument = original_open
        require("apps/reader/readerui"):showReader(book, nil, nil, nil, function(reader)
            assert(reader.document:getPageCount() >= 1)
            UIManager:scheduleIn(0.1, function() check(function()
                scans, opens, sidecar_scans = 0, 0, 0
                registry.openDocument = function(self, ...) opens = opens + 1; return original_open(self, ...) end
                reader:onHome()
                UIManager:scheduleIn(0.2, function() check(function()
                    assert(FileManager.instance and #FileManager.instance.file_chooser.item_table == 500)
                    print("Reader return counters", scans, opens, "upstream custom-cover sidecar lookups", sidecar_scans)
                    assert(scans == 0 and opens == 0, "Reader return must reuse the catalog")
                    registry.openDocument = original_open
                    print("KindleSpouse home acceptance passed: 500-book local shelf and real reader return")
                    UIManager:quit()
                end) end)
            end) end)
        end)
    end)
end
UIManager:tickAfterNext(function() UIManager:scheduleIn(0.1, ready) end)
