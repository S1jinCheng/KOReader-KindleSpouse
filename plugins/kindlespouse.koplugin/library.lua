local BookList = require("ui/widget/booklist")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local Device = require("device")
local util = require("util")
local Screen = Device.screen
local Library = {}
local defaults = { query = "", shelf = "all", format = "", author = "", source = "", collection = "", sort = "recent", view = "grid" }
local shelves = { { "all", "全部" }, { "new", "未读" }, { "reading", "在读" }, { "complete", "已读" }, { "favorites", "收藏" } }
local sorts = { { "recent", "最近阅读" }, { "added", "最近添加" }, { "title", "书名" }, { "author", "作者" }, { "progress", "阅读进度" } }

function Library.settings()
    local saved = G_reader_settings:readSetting("kindlespouse_library", {})
    local settings = {}
    for name, value in pairs(defaults) do settings[name] = type(saved[name]) == "string" and saved[name] or value end
    return settings
end

function Library.save(settings)
    G_reader_settings:saveSetting("kindlespouse_library", settings)
end

function Library.normalize(text)
    return util.stringLower(tostring(text or "")):gsub("^%s+", ""):gsub("%s+$", "")
end

function Library.catalog()
    if not Library.store then
        Library.store = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/kindlespouse-library.lua")
        Library.cache = Library.store:readSetting("books", {})
    end
    return Library.cache
end

function Library.record(ui, item, root, history)
    local cache = Library.catalog()
    local previous = cache[item.path]
    local current = previous and previous.size == item.attr.size and previous.modified == item.attr.modification
    local props = ui.bookinfo:getDocProps(item.path, nil, true)
    local title = props.title or current and previous.title or props.display_title or item.text
    local author = props.authors or current and previous.author or ""
    local metadata = { title = title, author = author, size = item.attr.size, modified = item.attr.modification,
        added = previous and previous.added or item.attr.change or os.time() }
    if not current or previous.title ~= title or previous.author ~= author then cache[item.path] = metadata; Library.dirty = true end
    local info = BookList.getBookInfo(item.path)
    local relative = item.path:sub(#root + 2)
    local source = relative:match("^([^/]+)/") or "书籍根目录"
    item.kindlespouse = {
        title = title, author = author ~= "" and author or "未提供作者",
        format = item.path:lower():match("%.([^.]+)$") or "", source = source,
        status = info.been_opened and info.status or "new", progress = info.percent_finished or 0,
        recent = history[item.path] or 0, added = metadata.added,
    }
    return item
end

function Library.matches(item, settings)
    local data = item.kindlespouse
    local query = Library.normalize(settings.query)
    if query ~= "" and not Library.normalize(data.title .. " " .. data.author .. " " .. item.text):find(query, 1, true) then return false end
    if settings.format ~= "" and data.format ~= settings.format then return false end
    if settings.author ~= "" and data.author ~= settings.author then return false end
    if settings.source ~= "" and data.source ~= settings.source then return false end
    if settings.collection ~= "" and not ReadCollection:isFileInCollection(item.path, settings.collection) then return false end
    if settings.shelf == "favorites" then return ReadCollection:isFileInCollection(item.path, ReadCollection.default_collection_name) end
    if settings.shelf == "complete" then return data.status == "complete" or data.progress >= 0.98 end
    if settings.shelf == "reading" then return data.status == "reading" and data.progress < 0.98 end
    if settings.shelf == "new" then return data.status == "new" end
    return true
end

function Library.apply(items, settings)
    local result = {}
    for _, item in ipairs(items) do if Library.matches(item, settings) then result[#result + 1] = item end end
    local strcoll = require("ffi/util").strcoll
    table.sort(result, function(a, b)
        local left, right = a.kindlespouse, b.kindlespouse
        if settings.sort == "author" and left.author ~= right.author then return strcoll(left.author, right.author) end
        if settings.sort == "recent" and left.recent ~= right.recent then return left.recent > right.recent end
        if settings.sort == "added" and left.added ~= right.added then return left.added > right.added end
        if settings.sort == "progress" and left.progress ~= right.progress then return left.progress > right.progress end
        if left.title ~= right.title then return strcoll(left.title, right.title) end
        return a.path < b.path
    end)
    if Library.dirty then
        Library.store:saveSetting("books", Library.cache)
        Library.store:flush()
        Library.dirty = false
    end
    return result
end

function Library.refresh(ui, changes)
    local settings = Library.settings()
    for name, value in pairs(changes) do settings[name] = value end
    Library.save(settings)
    ui:reinit(ui.file_chooser.path)
    UIManager:setDirty(ui, "ui")
end

function Library.choose(ui, title, options, select)
    local dialog
    local items = {}
    for _, option in ipairs(options) do
        items[#items + 1] = { text = option[2], callback = function()
            select(option[1])
        end }
    end
    dialog = require("ui/widget/menu"):new {
        title = title, width = math.floor(Screen:getWidth() * 0.9), height = math.floor(Screen:getHeight() * 0.75),
        item_table = items, show_parent = ui,
        close_callback = function() UIManager:close(dialog) end,
    }
    UIManager:show(dialog)
    return dialog
end

function Library.search(ui)
    local dialog
    dialog = require("ui/widget/inputdialog"):new {
        title = "搜索书名或作者", input = Library.settings().query, input_hint = "输入书名、作者或文件名",
        buttons = { {
            { text = "取消", callback = function() UIManager:close(dialog) end },
            { text = "清除", callback = function() UIManager:close(dialog); Library.refresh(ui, { query = "" }) end },
            { text = "搜索", is_enter_default = true, callback = function()
                local query = dialog:getInputText()
                UIManager:close(dialog)
                Library.refresh(ui, { query = query })
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

function Library.facet(ui, field, title)
    local values = {}
    for _, item in ipairs(ui.kindlespouse_catalog or {}) do values[item.kindlespouse[field]] = true end
    local names = {}
    for name in pairs(values) do if name ~= "" then names[#names + 1] = name end end
    table.sort(names, require("ffi/util").strcoll)
    local options = { { "", "全部" } }
    for _, name in ipairs(names) do options[#options + 1] = { name, field == "format" and name:upper() or name } end
    return Library.choose(ui, title, options, function(value) Library.refresh(ui, { [field] = value }) end)
end

function Library.collections(ui)
    local options = { { "", "全部书集" } }
    local names = {}
    for name in pairs(ReadCollection.coll) do names[#names + 1] = name end
    table.sort(names, require("ffi/util").strcoll)
    for _, name in ipairs(names) do options[#options + 1] = { name, name == ReadCollection.default_collection_name and "收藏" or name } end
    options[#options + 1] = { false, "管理书集…" }
    return Library.choose(ui, "书集", options, function(value)
        if value == false then ui.collections:onShowCollList() else Library.refresh(ui, { collection = value }) end
    end)
end

function Library.filters(ui)
    local settings = Library.settings()
    return Library.choose(ui, "筛选书库", {
        { "format", "格式：" .. (settings.format ~= "" and settings.format:upper() or "全部") },
        { "author", "作者：" .. (settings.author ~= "" and settings.author or "全部") },
        { "source", "来源文件夹：" .. (settings.source ~= "" and settings.source or "全部") },
        { "collection", "书集：" .. (settings.collection ~= "" and settings.collection or "全部") },
        { "clear", "清除所有筛选" },
    }, function(field)
        if field == "clear" then Library.refresh(ui, { query = "", shelf = "all", format = "", author = "", source = "", collection = "" })
        elseif field == "collection" then Library.collections(ui)
        else Library.facet(ui, field, field == "format" and "格式" or field == "author" and "作者" or "来源文件夹") end
    end)
end

function Library.toolbar(ui)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local Button = require("ui/widget/button")
    local Blitbuffer = require("ffi/blitbuffer")
    local settings = Library.settings()
    local width, height = Screen:getWidth(), Screen:scaleBySize(28)
    local function button(text, size, callback, active)
        return Button:new { text = text, width = size, height = height, bordersize = 0, padding = 0,
            radius = 0, text_font_size = 12, text_font_bold = active or false, show_parent = ui,
            background = active and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE, callback = callback }
    end
    local sort_title = "最近阅读"
    for _, option in ipairs(sorts) do if option[1] == settings.sort then sort_title = option[2] end end
    local search_width = math.floor(width * 0.46)
    local small = math.floor((width - search_width) / 3)
    local tools = HorizontalGroup:new {
        button(settings.query ~= "" and "搜索：" .. settings.query or "搜索书名或作者", search_width, function() Library.search(ui) end),
        button("筛选", small, function() Library.filters(ui) end),
        button(sort_title, small, function() Library.choose(ui, "排序", sorts, function(value) Library.refresh(ui, { sort = value }) end) end),
        button(settings.view == "grid" and "列表" or "网格", width - search_width - small * 2,
            function() Library.refresh(ui, { view = settings.view == "grid" and "list" or "grid" }) end),
    }
    local tabs = HorizontalGroup:new {}
    local cell = math.floor(width / 6)
    for index, option in ipairs(shelves) do
        tabs[index] = button(option[2], cell, function() Library.refresh(ui, { shelf = option[1], collection = "" }) end,
            settings.shelf == option[1] and settings.collection == "")
    end
    tabs[6] = button(settings.collection ~= "" and settings.collection or "书集", width - cell * 5,
        function() Library.collections(ui) end, settings.collection ~= "")
    local toolbar = VerticalGroup:new { align = "left", tools, tabs }
    ui.kindlespouse_toolbar = toolbar
    return toolbar
end

return Library
