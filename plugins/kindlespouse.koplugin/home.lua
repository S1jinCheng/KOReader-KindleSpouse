local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen
local Home = {}
local Library = require("library")

function Home.enabled()
    return G_reader_settings:readSetting("kindlespouse_home") ~= false
end

function Home.navigationHeight()
    return Screen:scaleBySize(58)
end

function Home.books(chooser, root)
    local files, visited = {}, {}
    local collate = chooser:getCollate()
    local history = {}
    for _, item in ipairs(require("readhistory").hist) do history[item.file] = item.time end
    local function visit(directory)
        if visited[directory] then return end
        visited[directory] = true
        local ok, iterator, state = pcall(lfs.dir, directory)
        if not ok then return end
        for name in iterator, state do
            if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
                local filename = directory .. "/" .. name
                local attr = lfs.symlinkattributes(filename)
                if attr and attr.mode == "directory" and chooser:show_dir(name) then
                    visit(filename)
                elseif attr and attr.mode == "file" and require("document/documentregistry"):hasProvider(filename) then
                    files[#files + 1] = Library.record(chooser.ui, chooser:getListItem(directory, name, filename, attr, collate), root, history)
                end
            end
        end
    end
    visit(root)
    chooser.ui.kindlespouse_catalog = files
    return Library.apply(files, Library.settings())
end

local original_init = FileChooser.init
function FileChooser:init()
    if self.ui and self.ui.kindlespouse_home and Home.enabled() then
        self.height = Screen:getHeight() - Home.navigationHeight()
        self.genItemTableFromPath = function(chooser, root) return Home.books(chooser, root) end
    end
    original_init(self)
    if self.ui and self.ui.kindlespouse_home and Home.enabled() then
        local toolbar = Library.toolbar(self.ui)
        local height = toolbar:getSize().h
        local calculate = self._recalculateDimen
        self._recalculateDimen = function(chooser, ...)
            chooser.inner_dimen.h = chooser.inner_dimen.h - height
            calculate(chooser, ...)
            chooser.inner_dimen.h = chooser.inner_dimen.h + height
        end
        self.content_group[1] = require("ui/widget/verticalgroup"):new { align = "left", self.title_bar, toolbar }
        self.content_group:resetLayout()
        self:updateItems(1)
    end
end

function Home.returnToKindle(companion)
    if not Device:isKindle() then
        companion:notify("Scribe notebooks are available on the Kindle Scribe.")
        return
    end
    companion.ui:onClose()
    UIManager:quit()
end

function Home.notebook(companion, height)
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
            TextBoxWidget:new { text = "Scribe 手写笔记本", width = width,
                alignment = "center", face = Font:getFace("cfont", 28) },
            VerticalSpan:new { width = Screen:scaleBySize(24) },
            TextBoxWidget:new {
                text = "手写笔记本由 Kindle 系统打开和编辑。\n返回 Kindle 后，点击底部的“笔记本”继续书写。",
                width = width, alignment = "center", face = Font:getFace("cfont", 20),
            },
            VerticalSpan:new { width = Screen:scaleBySize(32) },
            Button:new { text = "返回 Kindle，打开手写笔记本", width = width,
                callback = function() Home.returnToKindle(companion) end },
        },
    }
end

function Home.layout(ui, companion)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local Button = require("ui/widget/button")
    local Blitbuffer = require("ffi/blitbuffer")
    local half = math.floor(Screen:getWidth() / 2)
    local selected = ui.kindlespouse_tab or "Library"
    local body = ui[1]
    local focus = ui.layout
    if selected == "Notebook" then
        local height = Screen:getHeight() - Home.navigationHeight() - ui.title_bar:getHeight()
        body = VerticalGroup:new { align = "left", ui.title_bar, Home.notebook(companion, height) }
        focus = {}
    end
    local navigation = HorizontalGroup:new { align = "center" }
    for index, tab in ipairs({ "Library", "Notebook" }) do
        navigation[index] = Button:new {
            text = tab, width = index == 1 and half or Screen:getWidth() - half,
            height = Home.navigationHeight(), bordersize = 0, padding = 0,
            text_font_size = 20, text_font_bold = selected == tab,
            background = selected == tab and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE,
            show_parent = ui,
            callback = function()
                if ui.kindlespouse_tab == tab then return end
                ui.kindlespouse_tab = tab
                ui:reinit(ui.file_chooser.path)
                UIManager:setDirty(ui, "ui")
            end,
        }
    end
    ui[1] = FrameContainer:new {
        padding = 0, margin = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new { align = "left",
            LeftContainer:new { dimen = require("ui/geometry"):new { w = Screen:getWidth(), h = Screen:getHeight() - Home.navigationHeight() }, body },
            navigation },
    }
    ui.layout = {}
    for _, row in ipairs(focus or {}) do ui.layout[#ui.layout + 1] = row end
    ui.layout[#ui.layout + 1] = { navigation[1], navigation[2] }
    ui.title_bar:setTitle(selected)
    ui.title_bar:setSubTitle(selected == "Library" and Home.count(ui) or "Kindle Scribe")
    ui:registerKeyEvents()
end

function Home.install(companion)
    local ui = companion.ui
    if Home.enabled() then Home.prepareStart() end
    if ui.document then return end
    ui.kindlespouse_home = true
    ui.kindlespouse_tab = "Library"
    local original_layout = ui.setupLayout
    ui.setupLayout = function(manager)
        if manager.file_chooser and manager.file_chooser.onCloseWidget then manager.file_chooser:onCloseWidget() end
        if manager.coverbrowser and (Home.enabled() or G_reader_settings:readSetting("kindlespouse_home_saved")) then
            if Home.enabled() then Home.prepare(manager) end
            local chooser = manager.file_chooser
            manager.file_chooser = nil
            local mode = G_reader_settings:readSetting("kindlespouse_home_previous_mode") or nil
            if Home.enabled() then mode = Library.settings().view == "list" and "list_image_meta" or "mosaic_image" end
            manager.coverbrowser:setDisplayMode(mode)
            manager.file_chooser = chooser
        end
        if Home.enabled() then manager.root_path = Home.root(manager) end
        original_layout(manager)
        if Home.enabled() then Home.layout(manager, companion) end
    end
    local original_home = ui.onHome
    ui.onHome = function(manager)
        if not Home.enabled() then return original_home(manager) end
        manager.kindlespouse_tab = "Library"
        manager:reinit(Home.root(manager))
        UIManager:setDirty(manager, "ui")
        return true
    end
    local original_path = ui.updateTitleBarPath
    ui.updateTitleBarPath = function(manager, path)
        if not Home.enabled() then return original_path(manager, path) end
        manager.title_bar:setSubTitle(manager.kindlespouse_tab == "Notebook" and "Kindle Scribe" or Home.count(manager))
    end
    ui.onPathChanged = ui.updateTitleBarPath
    ui:registerPostInitCallback(function()
        if Home.enabled() then
            Home.prepare(ui)
            ui:reinit(Home.root(ui))
        end
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
    return visible == total and string.format("%d 本图书", total) or string.format("%d / %d 本图书 · 已筛选", visible, total)
end

function Home.prepareStart()
    if not G_reader_settings:readSetting("kindlespouse_home_start_saved") then
        G_reader_settings:saveSetting("kindlespouse_home_previous_start", G_reader_settings:readSetting("start_with") or false)
        G_reader_settings:saveSetting("kindlespouse_home_start_saved", true)
    end
    G_reader_settings:saveSetting("start_with", "filemanager")
end

function Home.toggle(companion)
    local ui = companion.ui
    local enabled = not Home.enabled()
    G_reader_settings:saveSetting("kindlespouse_home", enabled)
    if enabled then
        Home.prepare(ui)
    elseif G_reader_settings:readSetting("kindlespouse_home_saved") then
        G_reader_settings:saveSetting("start_with", G_reader_settings:readSetting("kindlespouse_home_previous_start") or nil)
    end
    ui.kindlespouse_tab = "Library"
    ui:reinit(Home.root(ui))
    UIManager:setDirty(ui, "ui")
end

return Home
