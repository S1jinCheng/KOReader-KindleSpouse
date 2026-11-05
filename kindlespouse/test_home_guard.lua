local UIManager = require("ui/uimanager")
local FileManager = require("apps/filemanager/filemanager")
local FileChooser = require("ui/widget/filechooser")
local Device = require("device")
local Version = require("version")
local logger = require("logger")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local mode = assert(os.getenv("KINDLESPOUSE_GUARD_CASE"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;plugins/coverbrowser.koplugin/?.lua;" .. package.path
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end
require("ui/widget/menu").is_enable_shortcut = false
FileChooser.is_enable_shortcut = false
assert(Version:getNormalizedCurrentVersion() == 202607010000)
if mode == "unknown" then Version.getNormalizedCurrentVersion = function() return nil end end
local Patches = require("patches")
local Guard = require("version_guard")
local foreign = { hook = function() return "original" end }
Patches.wrap("thirdparty:proof", foreign, "hook", function() return "foreign" end)
local warnings, sync_ticks = 0, 0
local original_warn = logger.warn
logger.warn = function(...)
    if select(1, ...) == "KindleSpouse:" then warnings = warnings + 1 end
    return original_warn(...)
end
local chooser_calls, generator_calls, setup_calls = 0, 0, 0
local original_chooser, original_generator = FileChooser.init, FileChooser.genItemTableFromPath
FileChooser.init = function(chooser, ...)
    chooser_calls = chooser_calls + 1
    return original_chooser(chooser, ...)
end
FileChooser.genItemTableFromPath = function(chooser, ...)
    generator_calls = generator_calls + 1
    return original_generator(chooser, ...)
end
local chooser_spy = FileChooser.init
local Home = require("home")
local Library = require("library")
local Catalog = require("catalog")
assert(FileChooser.init == chooser_spy and not Patches.applied["home:filechooser"], "Requiring Home must never patch FileChooser")
if mode == "unknown" then assert(not Home.enabled()) end
if mode == "layout" or mode == "layout_missing" then
    local original_layout = Home.layout
    Home.layout = function(ui, companion)
        original_layout(ui, companion)
        if mode == "layout_missing" then Patches.wrap(Patches.scope(ui) .. "broken", {}, "missingMethod", function() end) end
        error("synthetic Home.layout failure")
    end
elseif mode == "postinit" then
    Home.layout = function() end
    Home.prepare = function() error("synthetic post-init failure") end
elseif mode == "books" then
    Home.books = function() error("synthetic catalog projection failure") end
elseif mode == "chooser" then
    local original_wrap = Patches.wrap
    Patches.wrap = function(id, ...)
        if id:match("items$") then error("synthetic chooser preparation failure") end
        return original_wrap(id, ...)
    end
end
local native
local original_setup = FileManager.setupLayout
FileManager.setupLayout = function(ui, ...)
    setup_calls = setup_calls + 1
    local result = original_setup(ui, ...)
    native = { widget = ui[1], layout = ui.layout, title_bar = ui.title_bar,
        title = ui.title_bar.title_widget.text, subtitle = ui.title_bar.subtitle_widget.text, cropping = ui.cropping_widget }
    return result
end
local original_restore, restorations = Home.restoreNative, 0
local owned_tasks, owned_widgets = {}, {}
Home.restoreNative = function(ui)
    local snapshot = ui.kindlespouse_native
    if ui.kindlespouse_catalog_task then owned_tasks[ui.kindlespouse_catalog_task] = true end
    if ui.kindlespouse_shelf then owned_widgets[ui.kindlespouse_shelf] = true end
    original_restore(ui)
    if snapshot then
        restorations = restorations + 1
        assert(ui[1] == snapshot.widget and ui.layout == snapshot.layout and ui.cropping_widget == snapshot.cropping)
        assert(ui.title_bar.title_widget.text == snapshot.title and ui.title_bar.subtitle_widget.text == snapshot.subtitle)
    end
end
local original_init = FileManager.init
FileManager.init = function(ui)
    local setup, installed = ui.setupLayout, false
    local entry
    entry = function(manager)
        if not installed then
            installed = true
            Guard.install(manager, function()
                if mode == "missing" then manager.copyRecursive = false end
                Home.install { ui = manager, notify = function() end }
            end)
            if mode == "missing" then manager.copyRecursive = nil end
            if manager.setupLayout ~= entry then return manager:setupLayout() end
        end
        return setup(manager)
    end
    ui.setupLayout = entry
    return original_init(ui)
end
local function check(callback)
    local ok, failure = xpcall(callback, debug.traceback)
    if not ok then print("HOME GUARD FAILED " .. mode .. " " .. tostring(failure)); UIManager:quit(1) end
end
local function after(delay, callback) UIManager:scheduleIn(delay, function() check(callback) end) end
UIManager:scheduleIn(0.1, function() sync_ticks = sync_ticks + 1 end)
local function restored(ui, expected_calls)
    assert(not Home.enabled() and Guard.status().disabled)
    assert(ui[1] == native.widget and ui.layout == native.layout and ui.cropping_widget == native.cropping)
    assert(ui.title_bar == native.title_bar and ui.title_bar.title_widget.text == native.title)
    if mode == "tab" or mode == "catalog" then
        assert(ui.title_bar.subtitle_widget.text == native.subtitle)
    end
    if mode == "layout" or mode == "layout_missing" or mode == "postinit" or mode == "tab" or mode == "catalog" then assert(restorations >= 1) end
    assert(not ui.file_chooser.height and chooser_calls == expected_calls and setup_calls == expected_calls, "Native init/setup must run exactly once per setup")
    assert(generator_calls == 1 and #ui.file_chooser.item_table > 0 and #ui.file_chooser.item_group > 0,
        "Fallback must generate native directory items once and render them")
    assert(not ui.kindlespouse_shelf and not ui.kindlespouse_content and not ui.kindlespouse_catalog_task)
    assert(not ui.kindlespouse_patched and not ui.kindlespouse_home and not Catalog.subscribers[ui])
    for id in pairs(Patches.applied) do assert(id == "thirdparty:proof", "Owned patch leaked: " .. id) end
    for _, state in pairs(Catalog.roots) do assert(not state.scan); owned_widgets[state] = true end
    for _, task in ipairs(UIManager._task_queue) do assert(not owned_tasks[task.action], "Catalog refresh timer leaked") end
    local Extractor = require("extractor")
    for _, request in pairs(Extractor.pending) do
        for owner in pairs(request.owners) do assert(not owned_widgets[owner], "Pending extraction owner leaked") end
    end
    for _, request in ipairs(Extractor.active and Extractor.active.requests or {}) do
        for owner in pairs(request.owners) do assert(not owned_widgets[owner], "Active extraction callback leaked") end
    end
    assert(Patches.applied["thirdparty:proof"] and foreign:hook() == "foreign")
    assert(G_reader_settings:readSetting("kindlespouse_home") == true)
    assert(G_reader_settings:readSetting("kindlespouse_sync_sentinel") == "unchanged")
    assert(sync_ticks == 1 and warnings == 1)
    local task_ran = false
    assert(not Home.safe(ui, function() task_ran = true end) and not task_ran and warnings == 1)
    UIManager:widgetRepaint(ui, 0, 0)
    Device.screen:shot(assert(os.getenv("KINDLESPOUSE_GUARD_OUTPUT")) .. "/" .. mode .. ".png")
    print("HOME GUARD PASSED " .. mode)
    UIManager:quit()
end
UIManager:tickAfterNext(function()
    after(2, function()
        local ui = assert(FileManager.instance)
        if mode == "supported" then
            assert(Home.enabled() and ui.kindlespouse_shelf and #ui.file_chooser.item_table == 8)
            assert(setup_calls == 1 and chooser_calls == 1 and generator_calls == 0 and warnings == 0)
            local shelf, chooser = ui.kindlespouse_shelf, ui.file_chooser
            ui.layout[#ui.layout][2].callback()
            ui.layout[#ui.layout][1].callback()
            assert(ui.kindlespouse_shelf == shelf and ui.file_chooser == chooser and setup_calls == 1)
            print("HOME GUARD PASSED supported")
            UIManager:quit()
        elseif mode == "tab" then
            Home.switchTab = function() error("synthetic delayed tab failure") end
            ui.layout[#ui.layout][2].callback()
            restored(ui, 1)
        elseif mode == "catalog" then
            Library.refresh = function() error("synthetic delayed catalog failure") end
            Catalog.subscribers[ui]({ scanning = false })
            after(0.1, function() restored(ui, 1) end)
        else
            if mode == "unknown" then
                assert(not G_reader_settings:readSetting("kindlespouse_home_saved") and not G_reader_settings:readSetting("kindlespouse_home_start_saved"))
                assert(not G_reader_settings:readSetting("kindlespouse_library"))
            end
            local expected = 1
            if mode == "books" or mode == "chooser" then assert(generator_calls == 1) end
            restored(ui, expected)
        end
    end)
end)
