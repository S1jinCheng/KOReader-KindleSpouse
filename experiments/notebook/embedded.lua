local Device = require("device")
local UIManager = require("ui/uimanager")
local Geom = require("ui/geometry")
local Embedded = {}

function Embedded.new(directory)
    local load = assert(loadfile(directory .. "/loader.lua"))()(directory)
    load("pluginicons")()
    return setmetatable({ load = load }, { __index = Embedded })
end

function Embedded:open(name, folder, template, companion)
    if self.editor and not self.editor.closed then return self.editor end
    local Library = self.load("library")
    local Document = self.load("document")
    local Notebook = self.load("notebook")
    local filename = Library.abs((folder ~= "" and folder .. "/" or "") .. name .. ".scribe")
    local document = Document:new(filename)
    if require("libs/libkoreader-lfs").attributes(filename, "mode") == "file" then
        assert(document:load(), "Notebook cannot be decoded")
    elseif template then
        document:setTemplate(template)
    end
    local editor
    editor = Notebook:new {
        document = document,
        title = name,
        on_request = function(_, kind)
            if kind == "library" then editor:_close() end
        end,
        on_closed = function()
            self.editor = nil
            if self.gallery and not self.gallery.closed then self.gallery:_rebuild() end
            UIManager:setDirty(companion.ui, "full")
        end,
    }
    self.editor = editor
    UIManager:show(editor, "full")
    return editor
end

function Embedded:body(companion, height)
    self.load("library").ensureDir("")
    local gallery = self.load("gallery"):new {
        folder = self.folder or "",
        query = self.query,
        on_open = function(name, folder, template) self:open(name, folder, template, companion) end,
    }
    gallery.dimen = Geom:new { x = 0, y = companion.ui.title_bar:getHeight(), w = Device.screen:getWidth(), h = height }
    gallery.covers_fullscreen = false
    local original_header = gallery._buildHeader
    gallery._buildHeader = function(current)
        if current.selection then return original_header(current) end
        local width = current.dimen.w - Device.screen:scaleBySize(24)
        return require("ui/widget/buttontable"):new {
            width = width,
            buttons = { {
                { text = "搜索", callback = function()
                    local dialog
                    dialog = require("ui/widget/inputdialog"):new {
                        title = "搜索笔记本", input = current.query or "",
                        buttons = { {
                            { text = "取消", callback = function() UIManager:close(dialog) end },
                            { text = "搜索", callback = function()
                                current.query = dialog:getInputText()
                                UIManager:close(dialog)
                                current:_rebuild()
                            end },
                        } },
                    }
                    UIManager:show(dialog)
                    dialog:onShowKeyboard()
                end },
                { text = "新建笔记", callback = function() current:_createNotebook() end },
                { text = current.folder == "" and "文件夹" or "返回上层", callback = function()
                    if current.folder == "" then current:_createFolder()
                    else current:_goTo(current.folder:match("^(.*)/[^/]+$") or "") end
                end },
                { text = "排序", callback = function() current:_chooseOrder() end },
            } },
        }
    end
    gallery._footerHeight = function() return Device.screen:scaleBySize(48) end
    gallery._buildFooter = function(current)
        return require("ui/widget/buttontable"):new {
            width = current.dimen.w - Device.screen:scaleBySize(24),
            buttons = { {
                { text = "上一页", enabled = current.page > 1, callback = function() current:_turnPage(-1) end },
                { text = string.format("%d / %d", current.page, current.page_count), callback = function() end },
                { text = "下一页", enabled = current.page < current.page_count, callback = function() current:_turnPage(1) end },
            } },
        }
    end
    local original_layout = gallery._layout
    gallery._layout = function(current)
        if current.query and current.query ~= "" then
            local filtered = {}
            for _, item in ipairs(current.items) do
                if item.name:find(current.query, 1, true) then filtered[#filtered + 1] = item end
            end
            current.items = filtered
        end
        original_layout(current)
        companion.ui.title_bar:setSubTitle(string.format("%d 本笔记", #current.items))
    end
    gallery._repaint = function() UIManager:setDirty(companion.ui, "ui") end
    gallery.onClose = function()
        companion.ui.kindlespouse_tab = "Library"
        companion.ui:reinit(companion.ui.file_chooser.path)
        UIManager:setDirty(companion.ui, "full")
        return true
    end
    gallery:_recalculateDimen()
    self.gallery = gallery
    return gallery
end

function Embedded:install(Home)
    local instance = self
    Home.notebook = function(companion, height) return instance:body(companion, height) end
    local original_layout = Home.layout
    Home.layout = function(ui, companion)
        if instance.gallery then
            instance.folder = instance.gallery.folder
            instance.query = instance.gallery.query
            if not instance.gallery.closed then instance.gallery:onCloseWidget() end
            instance.gallery = nil
        end
        original_layout(ui, companion)
        if instance.gallery then ui.title_bar:setSubTitle(string.format("%d 本笔记", #instance.gallery.items)) end
    end
    local original_toggle = Home.toggle
    Home.toggle = function(companion)
        if instance.gallery and not instance.gallery.closed then instance.gallery:onCloseWidget() end
        instance.gallery = nil
        return original_toggle(companion)
    end
end

return Embedded
