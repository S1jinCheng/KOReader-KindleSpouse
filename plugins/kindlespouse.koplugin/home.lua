local T = require("i18n").T
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen
local Home = {}
local Library = require("library")
local Patches = require("patches")
local Catalog = require("catalog")
local Guard = require("version_guard")
local logger = require("logger")

function Home.enabled()
    local status = Guard.status()
    return status.supported and not status.disabled and G_reader_settings:readSetting("kindlespouse_home") ~= false
end

local function cleanup(callback, ...)
    local ok, failure = pcall(callback, ...)
    if not ok then logger.err("KindleSpouse:", "cannot clean up Home interface", tostring(failure)) end
end

function Home.captureNative(ui)
    local title = ui.title_bar
    local keys = {}
    for key, value in pairs(ui.key_events or {}) do keys[key] = value end
    ui.kindlespouse_native = { widget = ui[1], layout = ui.layout, cropping = ui.cropping_widget,
        title_bar = title, title = title and title.title_widget and title.title_widget.text,
        subtitle = title and title.subtitle_widget and title.subtitle_widget.text,
        chooser = ui.file_chooser, height = ui.file_chooser and ui.file_chooser.height, keys = keys,
        update_items = ui.file_chooser and ui.file_chooser.updateItems }
end

function Home.restoreNative(ui)
    local snapshot = ui.kindlespouse_native
    local shelf = ui.kindlespouse_shelf
    if shelf and shelf.on_close then cleanup(shelf.on_close, shelf) end
    cleanup(Home.uninstall, ui)
    cleanup(Catalog.unsubscribe, ui)
    if not next(Catalog.subscribers) and Catalog.root then cleanup(Catalog.cancel, Catalog.root) end
    if ui.kindlespouse_catalog_task then UIManager:unschedule(ui.kindlespouse_catalog_task); ui.kindlespouse_catalog_task = nil end
    cleanup(Patches.revertPrefix, Patches.scope(ui))
    cleanup(Patches.revert, "home:filechooser")
    ui.kindlespouse_patched, ui.kindlespouse_home = nil, nil
    if snapshot then
        ui[1], ui.layout, ui.cropping_widget = snapshot.widget, snapshot.layout, snapshot.cropping
        ui.title_bar, ui.file_chooser, ui.key_events = snapshot.title_bar, snapshot.chooser, snapshot.keys
        if ui.file_chooser then
            local chooser = ui.file_chooser
            chooser.height = snapshot.height
            if chooser.kindlespouse_native_generator and not chooser.kindlespouse_native_items then
                local ok, items = pcall(chooser.kindlespouse_native_generator, chooser, chooser.path)
                if ok then chooser.item_table = items; chooser.kindlespouse_native_items = true
                else logger.err("KindleSpouse:", "cannot restore native directory items", tostring(items)) end
            end
            if snapshot.update_items then cleanup(snapshot.update_items, chooser) end
            if snapshot.layout and chooser.layout ~= snapshot.layout then
                for index = #snapshot.layout, 1, -1 do snapshot.layout[index] = nil end
                for index, row in ipairs(chooser.layout) do snapshot.layout[index] = row end
                chooser.layout = snapshot.layout
            end
        end
        if snapshot.title ~= nil then cleanup(ui.title_bar.setTitle, ui.title_bar, snapshot.title, true) end
        if snapshot.subtitle ~= nil then cleanup(ui.title_bar.setSubTitle, ui.title_bar, snapshot.subtitle, true) end
        UIManager:setDirty(ui, "ui", ui.dimen)
    end
end

function Home.safe(ui, callback, ...)
    local function results(...) return { n = select("#", ...), ... } end
    local result = results(Guard.run(callback, ...))
    if not result[1] or Guard.status().disabled then
        Home.restoreNative(ui)
        return false, Guard.status().reason
    end
    return unpack(result, 1, result.n)
end

function Home.navigationHeight()
    return Screen:scaleBySize(40)
end

function Home.books(chooser, root)
    root = Home.root(chooser.ui) or root
    chooser.path = root
    Catalog.attachBookInfo(chooser.ui.bookinfo)
    Catalog.ensure(root)
    local items = Catalog.items(chooser)
    chooser.ui.kindlespouse_catalog = items
    return Library.apply(items, Library.settings())
end

function Home.observeCatalog(ui)
    if ui.kindlespouse_catalog_task then return end
    ui.kindlespouse_catalog_task = function()
        Home.safe(ui, function()
            if ui.kindlespouse_patched and Home.enabled() and ui.file_chooser then
                if ui.kindlespouse_tab == "Notebook" then ui.kindlespouse_catalog_dirty = true; return end
                if ui.kindlespouse_shelf then ui.kindlespouse_shelf:setScanning(nil) end
                Library.refresh(ui, {})
            end
        end)
    end
    Catalog.attachBookInfo(ui.bookinfo)
    Catalog.subscribe(ui, function(event)
        Home.safe(ui, function()
            if not ui.kindlespouse_patched or not Home.enabled() then return end
            if event.scanning then
                if ui.kindlespouse_shelf then ui.kindlespouse_shelf:setScanning(event.count or 0) end
                if ui.title_bar and ui.kindlespouse_tab ~= "Notebook" then
                    ui.title_bar:setSubTitle(string.format(T("catalog_scanning"), event.count or 0))
                end
                return
            end
            UIManager:unschedule(ui.kindlespouse_catalog_task)
            UIManager:scheduleIn(0.01, ui.kindlespouse_catalog_task)
        end)
    end)
end

function Home.patchChooser()
    if Patches.applied["home:filechooser"] then return end
    Patches.wrap("home:filechooser", FileChooser, "init", function(original, chooser, ...)
        if chooser.ui and chooser.ui.kindlespouse_home and Home.enabled() then
            chooser.kindlespouse_native_generator = chooser.genItemTableFromPath
            Home.safe(chooser.ui, function()
                chooser.kindlespouse_patch = Patches.scope(chooser) .. "items"
                Patches.wrap(chooser.kindlespouse_patch, chooser, "genItemTableFromPath", function(native, current, root)
                    local ok, items = Home.safe(current.ui, Home.books, current, root)
                    if ok then return items end
                    Home.releaseChooser(current)
                    local native_items = native(current, root)
                    current.kindlespouse_native_items = true
                    return native_items
                end)
            end)
        end
        local result = original(chooser, ...)
        if chooser.kindlespouse_native_generator and not Home.enabled() then chooser.kindlespouse_native_items = true end
        return result
    end)
end

function Home.releaseChooser(chooser)
    if chooser and chooser.kindlespouse_patch then Patches.revert(chooser.kindlespouse_patch) end
end

function Home.returnToKindle(companion)
    if not Device:isKindle() then
        companion:notify(T("scribe_available"))
        return
    end
    companion.ui:onClose()
    UIManager:quit()
end

function Home.nativeNotebook(companion, height)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local width = Screen:getWidth() - Screen:scaleBySize(64)
    return CenterContainer:new {
        dimen = require("ui/geometry"):new { w = Screen:getWidth(), h = height },
        VerticalGroup:new {
            align = "center",
            TextBoxWidget:new { text = T("scribe_notebooks"), width = width,
                alignment = "center", face = Font:getFace(Library.fonts.title, 28) },
            VerticalSpan:new { width = Screen:scaleBySize(24) },
            TextBoxWidget:new {
                text = T("scribe_instructions"),
                width = width, alignment = "center", face = Font:getFace(Library.fonts.ui, 20),
            },
            VerticalSpan:new { width = Screen:scaleBySize(32) },
            Button:new { text = T("return_kindle"), width = width,
                callback = function() Home.returnToKindle(companion) end },
        },
    }
end

function Home.notebook(companion, height)
    if not require("notebook/settings").enabled() then return Home.nativeNotebook(companion, height) end
    local ui = companion.ui
    local padding = math.max(0, Screen:scaleBySize(64) - Home.navigationHeight()) + Screen:scaleBySize(4)
    local panel = require("notebook/view").open(companion, height - padding, { root = Home.root(ui), catalog = Catalog })
    panel.kindlespouse_bottom_padding = padding
    Patches.wrap(Patches.scope(ui) .. "notebook:search", panel, "search", function(original, widget, query)
        if widget.closed then return end
        local ok, result = Home.safe(ui, original, widget, query)
        if not ok then return end
        if query ~= nil and not widget.closed then
            ui.kindlespouse_notebook_query = widget.query
            if ui.kindlespouse_tab == "Notebook" then Library.updateSearch(ui) end
        end
        return result
    end)
    for _, name in ipairs({ "render", "refresh" }) do
        Patches.wrap(Patches.scope(ui) .. "notebook:" .. name, panel, name, function(original, widget, ...)
            local ok, result = Home.safe(ui, original, widget, ...)
            if ok then return result end
        end)
    end
    panel:search(ui.kindlespouse_notebook_query or "")
    return panel
end

function Home.clearCachedNotebook(ui, companion)
    local body = ui.kindlespouse_notebook_body
    if body then
        if body.onCloseWidget and not body.closed then body:onCloseWidget() end
        if ui.kindlespouse_content and ui.kindlespouse_content[1] == ui.kindlespouse_notebook_group then
            ui.kindlespouse_content[1] = ui.kindlespouse_library_group
        end
        body:free()
    end
    Patches.revertPrefix(Patches.scope(ui) .. "notebook:")
    ui.kindlespouse_notebook_body = nil
    ui.kindlespouse_notebook_group = nil
    ui.kindlespouse_notebook_paused = nil
    ui.kindlespouse_notebook_search = nil
    ui.kindlespouse_notebook_query = nil
    if companion and ui.kindlespouse_tab == "Notebook" then Home.switchTab(ui, companion, "Notebook") end
end

function Home.lastBook()
    local registry = require("document/documentregistry")
    local latest, when
    for _, item in ipairs(require("readhistory").hist) do
        if type(item.file) == "string" and lfs.attributes(item.file, "mode") == "file" and registry:hasProvider(item.file) then
            local time = tonumber(item.time) or 0
            if not latest or time > when then latest, when = item.file, time end
        end
    end
    local previous = G_reader_settings:readSetting("lastfile")
    if not latest and type(previous) == "string" and lfs.attributes(previous, "mode") == "file" and registry:hasProvider(previous) then latest = previous end
    return latest
end

function Home.openRecent(companion, filename)
    if not filename then companion:notify(T("no_reading_history")); return end
    if lfs.attributes(filename, "mode") ~= "file" then
        companion:notify(T("recent_book_missing"))
        companion.ui:reinit(companion.ui.file_chooser.path)
        return
    end
    require("apps/reader/readerui"):showReader(filename)
end

function Home.recentButton(companion, width)
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local file = Home.lastBook()
    local cover_w, cover_h = Screen:scaleBySize(44), Screen:scaleBySize(64)
    local protrude = cover_h - Home.navigationHeight()
    local info = file and require("bookinfomanager"):getBookInfo(file, true) or nil
    local picture
    if info and info.cover_bb then
        local bb = info.cover_bb
        picture = require("ui/widget/imagewidget"):new { image = bb, scale_factor = math.min(cover_w / bb:getWidth(), cover_h / bb:getHeight()) }
    else
        picture = require("ui/widget/iconwidget"):new { icon = "book.opened", width = cover_w - 12, height = cover_h - 12 }
    end
    local title = info and info.title or file and file:match("([^/]+)$") or T("continue_reading")
    local button = InputContainer:new { file = file, title = title, cover_loaded = info and info.cover_bb ~= nil,
        dimen = Geom:new { w = width, h = cover_h },
        require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = width, h = cover_h },
            require("ui/widget/container/framecontainer"):new { padding = 0, margin = 0, bordersize = 1,
                require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = cover_w - 2, h = cover_h - 2 }, picture } } } }
    button.getSize = function() return Geom:new { w = width, h = Home.navigationHeight() } end
    button.paintTo = function(widget, bb, x, y)
        widget.dimen.x, widget.dimen.y = x, y - protrude
        widget[1]:paintTo(bb, x, y - protrude)
    end
    button.callback = function() Home.openRecent(companion, file) end
    button.updateCover = function(widget)
        if not file or widget.cover_loaded then return end
        local cached = require("bookinfomanager"):getBookInfo(file, true)
        if not cached or not cached.cover_bb then return end
        local bb = cached.cover_bb
        widget[1]:free()
        widget[1] = require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = width, h = cover_h },
            require("ui/widget/container/framecontainer"):new { padding = 0, margin = 0, bordersize = 1,
                require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = cover_w - 2, h = cover_h - 2 },
                    require("ui/widget/imagewidget"):new { image = bb, scale_factor = math.min((cover_w - 2) / bb:getWidth(), (cover_h - 2) / bb:getHeight()) } } } }
        widget.cover_loaded, widget.title = true, cached.title or widget.title
    end
    button.ges_events = {
        Recent = { require("ui/gesturerange"):new { ges = "tap", range = button.dimen } },
        RecentTitle = { require("ui/gesturerange"):new { ges = "hold", range = button.dimen } },
    }
    button.onRecent = function() button.callback(); return true end
    button.onRecentTitle = function(widget) companion:notify(widget.title); return true end
    return button
end

function Home.pauseBody(ui)
    if ui.kindlespouse_tab == "Notebook" then
        local notebook = ui.kindlespouse_notebook_body
        if notebook and not ui.kindlespouse_notebook_paused then
            if notebook.onCloseWidget and not notebook.closed then notebook:onCloseWidget() end
            ui.kindlespouse_notebook_paused = true
        end
        ui.kindlespouse_notebook_search = nil
    elseif ui.kindlespouse_shelf then
        local shelf = ui.kindlespouse_shelf
        if shelf.on_close then shelf:on_close() end
        shelf.queued = false
        shelf[1]:free()
        require("ui/widget/container/scrollablecontainer").onCloseWidget(shelf)
    end
end

function Home.releaseLayout(ui)
    cleanup(Home.pauseBody, ui)
    if ui.kindlespouse_shelf then cleanup(ui.kindlespouse_shelf.onCloseWidget, ui.kindlespouse_shelf) end
    local toolbar = ui.kindlespouse_library_group and ui.kindlespouse_library_group[2]
    if toolbar then cleanup(toolbar.free, toolbar) end
    cleanup(Home.clearCachedNotebook, ui)
    if ui.kindlespouse_header then cleanup(ui.kindlespouse_header.free, ui.kindlespouse_header) end
    if ui.kindlespouse_recent then cleanup(ui.kindlespouse_recent.free, ui.kindlespouse_recent) end
    if ui.kindlespouse_navigation then
        for _, index in ipairs({ 1, 3 }) do
            local button = ui.kindlespouse_navigation[index]
            if button then cleanup(button.free, button) end
        end
    end
    for _, name in ipairs({ "shelf", "library_group", "notebook_group", "notebook_body", "notebook_paused",
            "notebook_search", "header", "recent", "navigation", "content", "search", "search_label", "toolbar", "profile" }) do
        ui["kindlespouse_" .. name] = nil
    end
    ui.cropping_widget = nil
end

function Home.switchTab(ui, companion, tab)
    if not ui.kindlespouse_content then return false end
    local changed = ui.kindlespouse_tab ~= tab
    if changed then Home.pauseBody(ui) end
    ui.kindlespouse_tab = tab
    if tab == "Notebook" then
        if not ui.kindlespouse_notebook_body then
            local height = Screen:getHeight() - Home.navigationHeight() - ui.kindlespouse_header:getSize().h
            local body = Home.notebook(companion, height)
            ui.kindlespouse_notebook_body = body
            local group = { align = "left", ui.kindlespouse_header, body }
            if body.kindlespouse_bottom_padding then
                group[3] = require("ui/widget/verticalspan"):new { width = body.kindlespouse_bottom_padding }
            end
            ui.kindlespouse_notebook_group = require("ui/widget/verticalgroup"):new(group)
        elseif ui.kindlespouse_notebook_paused then
            if ui.kindlespouse_notebook_body.refresh then ui.kindlespouse_notebook_body:refresh() end
        end
        ui.kindlespouse_notebook_paused = nil
        local body = ui.kindlespouse_notebook_body
        if body.search and require("notebook/settings").enabled() then
            ui.kindlespouse_notebook_search = function() return body:search() end
        end
        ui.kindlespouse_content[1] = ui.kindlespouse_notebook_group
        ui.cropping_widget = nil
    else
        ui.kindlespouse_content[1] = ui.kindlespouse_library_group
        ui.cropping_widget = ui.kindlespouse_shelf
        if ui.kindlespouse_catalog_dirty then
            ui.kindlespouse_catalog_dirty = nil
            Library.refresh(ui, {})
        end
    end
    Library.updateSearch(ui)
    ui.title_bar:setTitle(T(tab == "Notebook" and "notebook_tab" or "library_tab"))
    ui.title_bar:setSubTitle(tab == "Library" and Home.count(ui) or T("brand_scribe"))
    UIManager:setDirty(ui, changed and "flashui" or "ui", ui.dimen)
    return true
end

function Home.layout(ui, companion)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local Button = require("ui/widget/button")
    local Blitbuffer = require("ffi/blitbuffer")
    local center_width = Screen:scaleBySize(88)
    local side_width = math.floor((Screen:getWidth() - center_width) / 2)
    Patches.revertPrefix(Patches.scope(ui) .. "render:")
    local selected = ui.kindlespouse_tab or "Library"
    Home.releaseLayout(ui)
    local header = Library.header(ui, companion)
    ui.kindlespouse_header = header
    local toolbar = Library.toolbar(ui)
    local height = Screen:getHeight() - Home.navigationHeight() - header:getSize().h - toolbar:getSize().h
    ui.kindlespouse_shelf = require("shelf").library(ui, height)
    ui.kindlespouse_library_group = VerticalGroup:new { align = "left", header, toolbar, ui.kindlespouse_shelf }
    local navigation = HorizontalGroup:new { align = "center" }
    for index, tab in ipairs({ "Library", "Notebook" }) do
        navigation[index == 1 and 1 or 3] = Button:new {
            text = T(tab == "Notebook" and "notebook_tab" or "library_tab"), width = index == 1 and side_width or Screen:getWidth() - side_width - center_width,
            height = Home.navigationHeight(), bordersize = 0, padding = 0,
            text_font_face = Library.fonts.ui, text_font_size = 12, text_font_bold = false, radius = 0,
            background = Blitbuffer.COLOR_WHITE,
            show_parent = ui,
            callback = function()
                if ui.kindlespouse_tab == tab then return end
                Home.safe(ui, Home.switchTab, ui, companion, tab)
            end,
        }
    end
    navigation[2] = Home.recentButton(companion, center_width)
    ui.kindlespouse_recent = navigation[2]
    for index, tab in ipairs({ "Library", "Notebook" }) do
        local button = navigation[index == 1 and 1 or 3]
        Patches.wrap(Patches.scope(ui) .. "render:tab" .. index, button, "paintTo", function(original, widget, bb, x, y)
            original(widget, bb, x, y)
            if ui.kindlespouse_tab == tab then
                local label = widget.label_widget:getSize()
                bb:paintRect(x + math.floor((widget.width - label.w) / 2),
                    y + math.floor((widget.height + label.h) / 2) + Screen:scaleBySize(3), label.w, 2, Blitbuffer.COLOR_BLACK)
            end
        end)
    end
    Patches.wrap(Patches.scope(ui) .. "render:navigation", navigation, "paintTo", function(original, widget, bb, x, y)
        original(widget, bb, x, y)
        local gap = Screen:scaleBySize(46)
        local left = math.floor((Screen:getWidth() - gap) / 2)
        bb:paintRect(x, y, left, 1, Blitbuffer.COLOR_GRAY)
        bb:paintRect(x + left + gap, y, Screen:getWidth() - left - gap, 1, Blitbuffer.COLOR_GRAY)
    end)
    ui.kindlespouse_navigation = navigation
    ui.kindlespouse_content = LeftContainer:new {
        dimen = require("ui/geometry"):new { w = Screen:getWidth(), h = Screen:getHeight() - Home.navigationHeight() },
        ui.kindlespouse_library_group,
    }
    ui[1] = FrameContainer:new {
        padding = 0, margin = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new { align = "left",
            ui.kindlespouse_content,
            navigation },
    }
    Patches.wrap(Patches.scope(ui) .. "render:events", ui[1], "propagateEvent", function(original, widget, event)
        local gesture = event.handler == "onGesture" and event.args and event.args[1]
        if gesture and gesture.pos and (gesture.ges == "tap" or gesture.ges == "hold")
            and gesture.pos:intersectWith(ui.kindlespouse_recent.dimen) and ui.kindlespouse_recent:handleEvent(event) then return true end
        return original(widget, event)
    end)
    ui.layout = {}
    ui.layout[#ui.layout + 1] = { navigation[1], navigation[3] }
    Home.switchTab(ui, companion, selected)
    ui:registerKeyEvents()
end

local function install(companion)
    local ui = companion.ui
    if not Home.enabled() or ui.document then return end
    Home.prepareStart()
    ui.kindlespouse_home = true
    ui.kindlespouse_tab = "Library"
    if ui.kindlespouse_patched then return end
    ui.kindlespouse_patched = true
    Home.observeCatalog(ui)
    Home.trackFiles(ui)
    Home.patchChooser()
    Patches.wrap(Patches.scope(ui) .. "layout", ui, "setupLayout", function(original, manager)
        Home.safe(manager, function()
            Home.releaseChooser(manager.file_chooser)
            if manager.file_chooser and manager.file_chooser.onCloseWidget then manager.file_chooser:onCloseWidget() end
            if manager.coverbrowser and (Home.enabled() or G_reader_settings:readSetting("kindlespouse_home_saved")) then
                if Home.enabled() then Home.prepare(manager) end
                local chooser = manager.file_chooser
                local mode = G_reader_settings:readSetting("kindlespouse_home_previous_mode") or nil
                if Home.enabled() then mode = nil end
                if require("bookinfomanager"):getSetting("filemanager_display_mode") ~= mode then
                    manager.file_chooser = nil
                    local ok, failure = pcall(manager.coverbrowser.setDisplayMode, manager.coverbrowser, mode)
                    manager.file_chooser = chooser
                    if not ok then error(failure) end
                end
            end
            if Home.enabled() then manager.root_path = Home.root(manager) end
        end)
        original(manager)
        Home.captureNative(manager)
        Home.safe(manager, function()
            if Home.enabled() then
                Home.layout(manager, companion)
                manager.file_chooser.height = Screen:getHeight() - Home.navigationHeight()
            end
        end)
    end)
    Patches.wrap(Patches.scope(ui) .. "home", ui, "onHome", function(original, manager)
        if not Home.enabled() then return original(manager) end
        Home.safe(manager, function()
            if Home.switchTab(manager, companion, "Library") then Library.refresh(manager, {})
            else manager:reinit(Home.root(manager)) end
        end)
        return true
    end)
    Patches.wrap(Patches.scope(ui) .. "close", ui, "onCloseWidget", function(original, manager, ...)
        Home.safe(manager, Home.uninstall, manager)
        return original(manager, ...)
    end)
    Patches.wrap(Patches.scope(ui) .. "title", ui, "updateTitleBarPath", function(original, manager, path)
        if not Home.enabled() then return original(manager, path) end
        Home.safe(manager, function()
            manager.title_bar:setSubTitle(manager.kindlespouse_tab == "Notebook" and T("brand_scribe") or Home.count(manager))
        end)
    end)
    Patches.wrap(Patches.scope(ui) .. "path", ui, "onPathChanged", function(original, manager, path)
        if not Home.enabled() then return original(manager, path) end
        Home.safe(manager, function() manager:updateTitleBarPath(path) end)
    end)
    if ui.kindlespouse_post_init_registered then return end
    ui.kindlespouse_post_init_registered = true
    ui.kindlespouse_post_init_callback = function()
        ui.kindlespouse_post_init_running = true
        Home.safe(ui, function()
            if Home.enabled() then Home.prepare(ui); ui:reinit(Home.root(ui)) end
        end)
        ui.kindlespouse_post_init_running = nil
        ui.kindlespouse_post_init_callback = nil
    end
    ui:registerPostInitCallback(ui.kindlespouse_post_init_callback)
end

function Home.install(companion)
    local ok, failure = pcall(install, companion)
    if not ok then
        Home.restoreNative(companion.ui)
        error(failure)
    end
end

function Home.rebuild(ui)
    return Home.safe(ui, function()
        ui:reinit(ui.file_chooser.path)
        UIManager:setDirty(ui, "ui", ui.dimen)
    end)
end

function Home.refreshFiles(ui)
    return Home.safe(ui, function() return Catalog.rescan(Home.root(ui)) end)
end

function Home.trackFiles(ui)
    for _, name in ipairs({ "moveFile", "copyFileFromTo", "copyRecursive" }) do
        Patches.wrap(Patches.scope(ui) .. "file:" .. name, ui, name, function(original, manager, from, to)
            local mode = lfs.attributes(from, "mode")
            local ok = original(manager, from, to)
            if ok then
                if mode == "directory" then Home.refreshFiles(manager)
                else
                    if name == "moveFile" then Catalog.remove(from) end
                    Catalog.add(to)
                end
            end
            return ok
        end)
    end
    Patches.wrap(Patches.scope(ui) .. "file:delete", ui, "deleteFile", function(original, manager, file, is_file)
        local ok = original(manager, file, is_file)
        if ok then
            if is_file then Catalog.remove(file) else Home.refreshFiles(manager) end
        end
        return ok
    end)
    Patches.wrap(Patches.scope(ui) .. "file:deleteSelected", ui, "deleteSelectedFiles", function(original, manager, ...)
        local files = {}
        for file in pairs(manager.selected_files or {}) do files[#files+1] = file end
        local result = original(manager, ...)
        for _, file in ipairs(files) do if not lfs.attributes(file, "mode") then Catalog.remove(file) end end
        return result
    end)
end

function Home.root(ui)
    local folder = G_reader_settings:readSetting("home_dir")
    if folder and lfs.attributes(folder, "mode") == "directory" and folder ~= "/mnt/us" then return folder end
    if lfs.attributes("/mnt/us/documents", "mode") == "directory" then return "/mnt/us/documents" end
    return ui.root_path
end

function Home.prepare(ui)
    Home.prepareStart()
    if not G_reader_settings:readSetting("kindlespouse_home_saved") then
        if ui.coverbrowser then
            G_reader_settings:saveSetting("kindlespouse_home_previous_mode", require("bookinfomanager"):getSetting("filemanager_display_mode") or false)
        end
        G_reader_settings:saveSetting("kindlespouse_home_saved", true)
    end
end

function Home.count(ui)
    local total, visible = #(ui.kindlespouse_catalog or {}), #ui.file_chooser.item_table
    return visible == total and string.format(T("library_count"), total) or string.format(T("library_filtered_count"), visible, total)
end

function Home.prepareStart()
    Library.prepareFonts()
    if not G_reader_settings:isTrue("kindlespouse_native_library") then
        local settings = Library.settings()
        settings.sort = "recent"
        settings.view = "list"
        Library.save(settings)
        G_reader_settings:saveSetting("kindlespouse_native_library", true)
    end
    if not G_reader_settings:readSetting("kindlespouse_home_start_saved") then
        G_reader_settings:saveSetting("kindlespouse_home_previous_start", G_reader_settings:readSetting("start_with") or false)
        G_reader_settings:saveSetting("kindlespouse_home_start_saved", true)
    end
    G_reader_settings:saveSetting("start_with", "filemanager")
end

function Home.uninstall(ui)
    local callback = ui.kindlespouse_post_init_callback
    if callback and ui.postInitCallback and not ui.kindlespouse_post_init_running then
        for index = #ui.postInitCallback, 1, -1 do
            if ui.postInitCallback[index] == callback then table.remove(ui.postInitCallback, index) end
        end
        ui.kindlespouse_post_init_callback = nil
    end
    Home.releaseLayout(ui)
    Catalog.unsubscribe(ui)
    if not next(Catalog.subscribers) and Catalog.root then Catalog.cancel(Catalog.root) end
    if ui.kindlespouse_catalog_task then UIManager:unschedule(ui.kindlespouse_catalog_task); ui.kindlespouse_catalog_task = nil end
    Home.releaseChooser(ui.file_chooser)
    Patches.revertPrefix(Patches.scope(ui))
    ui.kindlespouse_patched = nil
    ui.kindlespouse_home = nil
    ui.kindlespouse_native = nil
end

function Home.toggle(companion)
    local status = Guard.status()
    if not status.supported or status.disabled then return false end
    local ui = companion.ui
    local enabled = not Home.enabled()
    G_reader_settings:saveSetting("kindlespouse_home", enabled)
    if enabled then
        Home.prepare(ui)
        Home.install(companion)
    else
        Home.uninstall(ui)
        Patches.revert("home:filechooser")
        if ui.coverbrowser then
            local chooser = ui.file_chooser
            ui.file_chooser = nil
            ui.coverbrowser:setDisplayMode(G_reader_settings:readSetting("kindlespouse_home_previous_mode") or nil)
            ui.file_chooser = chooser
        end
        if G_reader_settings:readSetting("kindlespouse_home_saved") then
            G_reader_settings:saveSetting("start_with", G_reader_settings:readSetting("kindlespouse_home_previous_start") or nil)
        end
    end
    ui.kindlespouse_tab = "Library"
    ui:reinit(Home.root(ui))
    UIManager:setDirty(ui, "ui")
end

return Home
