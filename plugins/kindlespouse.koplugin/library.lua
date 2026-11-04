local T = require("i18n").T
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local Device = require("device")
local util = require("util")
local Screen = Device.screen
local Library = {}
Library.fonts = { title = "cfont", ui = "cfont" }
local defaults = { query = "", shelf = "all", format = "", author = "", source = "", collection = "", sort = "recent", view = "list" }
local shelves = { { "all", T("all") }, { "new", T("unread") }, { "reading", T("reading") }, { "complete", T("complete") }, { "favorites", T("favorites") } }
local sorts = { { "recent", T("recent") }, { "added", T("added") }, { "title", T("title") }, { "author", T("author") }, { "progress", T("progress") } }

function Library.prepareFonts()
    if Library.fonts_ready then return end
    Library.fonts_ready = true
    for _, filename in ipairs(require("fontlist"):getFontList()) do
        local name = filename:match("([^/]+)$")
        if name == "NotoSerifCJKsc-Regular.otf" then Library.fonts.title = name end
        if name == "NotoSansCJKsc-Regular.otf" then Library.fonts.ui = name end
    end
end

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

function Library.matches(item, settings)
    local data = item.kindlespouse
    local query = Library.normalize(settings.query)
    if query ~= "" and not Library.normalize(data.title .. " " .. data.author .. " " .. item.text):find(query, 1, true) then return false end
    if settings.format ~= "" and data.format ~= settings.format then return false end
    if settings.author ~= "" and data.author ~= settings.author then return false end
    if settings.source ~= "" and data.source ~= settings.source then return false end
    if settings.collection ~= "" and (ReadCollection.coll[settings.collection] or {})[data.canonical or item.path] == nil then return false end
    if settings.shelf == "favorites" then return (ReadCollection.coll[ReadCollection.default_collection_name] or {})[data.canonical or item.path] ~= nil end
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
    return result
end

function Library.updateSearch(ui)
    if not ui.kindlespouse_search_label then return end
    local notebook = ui.kindlespouse_tab == "Notebook"
    local query = notebook and (ui.kindlespouse_notebook_query or "") or Library.settings().query
    ui.kindlespouse_search_label:setText(query ~= "" and query or (notebook and T("search_notebooks") or T("search_kindle")))
    UIManager:setDirty(ui, "ui", ui.kindlespouse_search.dimen)
end

function Library.updateToolbar(ui)
    local group = ui.kindlespouse_library_group
    if not group then return end
    local previous = group[2]
    local region = require("ui/geometry"):new { x = 0, y = group[1]:getSize().h, w = Screen:getWidth(), h = previous:getSize().h }
    group[2] = Library.toolbar(ui)
    group:resetLayout()
    previous:free()
    if ui.kindlespouse_tab ~= "Notebook" then UIManager:setDirty(ui, "ui", region) end
end

function Library.refresh(ui, changes)
    local settings = Library.settings()
    local old_view = settings.view
    for name, value in pairs(changes) do settings[name] = value end
    Library.save(settings)
    if settings.view ~= old_view then return require("home").rebuild(ui) end
    local chooser = ui.file_chooser
    local items = require("home").books(chooser, chooser.path)
    chooser.item_table = items
    if ui.kindlespouse_shelf then ui.kindlespouse_shelf:setItems(items) end
    Library.updateToolbar(ui)
    Library.updateSearch(ui)
    if ui.title_bar and ui.kindlespouse_tab ~= "Notebook" then ui.title_bar:setSubTitle(require("home").count(ui)) end
end

function Library.choose(ui, title, options, select)
    local dialog
    local items = {}
    for _, option in ipairs(options) do
        items[#items + 1] = { text = option[2], callback = function()
            return select(option[1])
        end }
    end
    dialog = require("ui/widget/menu"):new {
        title = title, width = math.floor(Screen:getWidth() * 0.9), height = math.floor(Screen:getHeight() * 0.75),
        title_face = require("ui/font"):getFace(Library.fonts.title, 18), items_font_size = 16,
        item_table = items, show_parent = ui,
        close_callback = function() UIManager:close(dialog) end,
    }
    UIManager:show(dialog)
    return dialog
end

function Library.search(ui)
    local dialog
    dialog = require("ui/widget/inputdialog"):new {
        title = T("search_title"), input = Library.settings().query, input_hint = T("search_hint"),
        buttons = { {
            { text = T("cancel"), callback = function() UIManager:close(dialog) end },
            { text = T("clear"), callback = function() UIManager:close(dialog); Library.refresh(ui, { query = "" }) end },
            { text = T("search"), is_enter_default = true, callback = function()
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
    local options = { { "", T("all") } }
    for _, name in ipairs(names) do options[#options + 1] = { name, field == "format" and name:upper() or name } end
    return Library.choose(ui, title, options, function(value) Library.refresh(ui, { [field] = value }) end)
end

function Library.collections(ui)
    local options = { { "", T("all_collections") } }
    local names = {}
    for name in pairs(ReadCollection.coll) do names[#names + 1] = name end
    table.sort(names, require("ffi/util").strcoll)
    for _, name in ipairs(names) do options[#options + 1] = { name, name == ReadCollection.default_collection_name and T("favorites") or name } end
    options[#options + 1] = { false, T("manage_collections") }
    return Library.choose(ui, T("collection"), options, function(value)
        if value == false then ui.collections:onShowCollList() else Library.refresh(ui, { collection = value }) end
    end)
end

function Library.filters(ui)
    local settings = Library.settings()
    local status, sorting = T("all"), T("recent")
    for _, option in ipairs(shelves) do if option[1] == settings.shelf then status = option[2] end end
    for _, option in ipairs(sorts) do if option[1] == settings.sort then sorting = option[2] end end
    return Library.choose(ui, T("filter_library"), {
        { "shelf", T("status_label") .. status },
        { "format", T("format_label") .. (settings.format ~= "" and settings.format:upper() or T("all")) },
        { "author", T("author_label") .. (settings.author ~= "" and settings.author or T("all")) },
        { "source", T("source_label") .. (settings.source ~= "" and settings.source or T("all")) },
        { "collection", T("collection_label") .. (settings.collection ~= "" and settings.collection or T("all")) },
        { "sort", T("sort_label") .. sorting },
        { "view", T("view_label") .. (settings.view == "grid" and T("grid") or T("list")) },
        { "clear", T("clear_filters") },
    }, function(field)
        if field == "clear" then Library.refresh(ui, { query = "", shelf = "all", format = "", author = "", source = "", collection = "" })
        elseif field == "shelf" then return Library.choose(ui, T("reading_status"), shelves, function(value) Library.refresh(ui, { shelf = value }) end)
        elseif field == "sort" then return Library.choose(ui, T("sort"), sorts, function(value) Library.refresh(ui, { sort = value }) end)
        elseif field == "view" then return Library.choose(ui, T("view"), { { "grid", T("grid") }, { "list", T("list") } },
            function(value) Library.refresh(ui, { view = value }) end)
        elseif field == "collection" then Library.collections(ui)
        else Library.facet(ui, field, field == "format" and T("format") or field == "author" and T("author") or T("source")) end
    end)
end

function Library.header(ui, companion)
    local Geom = require("ui/geometry")
    local Font = require("ui/font")
    local Button = require("ui/widget/button")
    local TextWidget = require("ui/widget/textwidget")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local width, pad = Screen:getWidth(), Screen:scaleBySize(16)
    local third = math.floor(width / 3)
    local status_height = Screen:scaleBySize(26)
    local profile_button = require("profile").button(companion, status_height)
    ui.kindlespouse_profile = profile_button
    local battery = ""
    if Device:isKindle() and Device:hasBattery() then
        local power = Device:getPowerDevice()
        local capacity = power:getCapacity()
        battery = tostring(capacity) .. "% " .. power:getBatterySymbol(false, power:isCharging(), capacity)
    end
    local status = HorizontalGroup:new { align = "center",
        require("ui/widget/container/leftcontainer"):new { dimen = Geom:new { w = third, h = status_height },
            FrameContainer:new { padding = 0, padding_left = pad, bordersize = 0,
                HorizontalGroup:new { align = "center", profile_button,
                    require("ui/widget/horizontalspan"):new { width = Screen:scaleBySize(8) },
                    TextWidget:new { text = os.date("%H:%M"), face = Font:getFace(Library.fonts.ui, 9) } } } },
        CenterContainer:new { dimen = Geom:new { w = third, h = status_height },
            require("ui/widget/iconbutton"):new { icon = "chevron.up", icon_rotation_angle = 180,
                width = Screen:scaleBySize(18), height = Screen:scaleBySize(18), padding = 0,
                callback = function() ui.menu:onShowMenu() end } },
        require("ui/widget/container/rightcontainer"):new { dimen = Geom:new { w = width - third * 2, h = status_height },
            FrameContainer:new { padding = 0, padding_right = pad, bordersize = 0,
                TextWidget:new { text = battery, face = Font:getFace(Library.fonts.ui, 9) } } },
    }
    local search_width = width - pad * 2 - Screen:scaleBySize(36)
    local query = ui.kindlespouse_tab == "Notebook" and (ui.kindlespouse_notebook_query or "") or Library.settings().query
    local search_label = TextWidget:new { text = query ~= "" and query or (ui.kindlespouse_tab == "Notebook" and T("search_notebooks") or T("search_kindle")),
        face = Font:getFace(Library.fonts.ui, 12), max_width = search_width - Screen:scaleBySize(48) }
    ui.kindlespouse_search_label = search_label
    local search = InputContainer:new {
        FrameContainer:new { width = search_width, padding = Screen:scaleBySize(6), padding_left = Screen:scaleBySize(12),
            margin = 0, bordersize = 1, radius = Screen:scaleBySize(20),
            HorizontalGroup:new { align = "center",
                require("ui/widget/iconwidget"):new { icon = "appbar.search", width = Screen:scaleBySize(14), height = Screen:scaleBySize(14) },
                require("ui/widget/horizontalspan"):new { width = Screen:scaleBySize(10) },
                search_label,
            } },
    }
    search.dimen = search[1]:getSize():copy()
    search.dimen.w = search_width
    search.ges_events = { Search = { require("ui/gesturerange"):new { ges = "tap", range = search.dimen } } }
    search.onSearch = function()
        if ui.kindlespouse_tab == "Notebook" then
            if ui.kindlespouse_notebook_search then return ui.kindlespouse_notebook_search() end
            companion:notify(T("notebook.disabled"))
            return true
        end
        return Library.search(ui)
    end
    ui.kindlespouse_search = search
    local actions = Button:new { text = "⋮", text_font_face = Library.fonts.ui, text_font_size = 18,
        width = Screen:scaleBySize(36), height = search:getSize().h, bordersize = 0, padding = 0,
        callback = function() ui:onShowPlusMenu() end }
    return VerticalGroup:new { align = "left", status,
        FrameContainer:new { padding = 0, padding_left = pad, padding_right = pad, bordersize = 0,
            HorizontalGroup:new { align = "center", search, actions } },
        require("ui/widget/verticalspan"):new { width = Screen:scaleBySize(8) },
    }
end

function Library.toolbar(ui)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local width, size, pad = Screen:getWidth(), Screen:scaleBySize(32), Screen:scaleBySize(12)
    local function button(kind, callback)
        local glyph = require("ui/widget/widget"):new { dimen = Geom:new { w = size, h = size } }
        glyph.paintTo = function(_, bb, x, y)
            local function rect(px, py, w, h)
                bb:paintRect(x + Screen:scaleBySize(px), y + Screen:scaleBySize(py),
                    math.max(1, Screen:scaleBySize(w)), math.max(1, Screen:scaleBySize(h)), Blitbuffer.COLOR_BLACK)
            end
            if kind == "filter" then
                for index, knob in ipairs({ 12, 21, 15 }) do
                    local line_y = 8 + (index - 1) * 7
                    rect(7, line_y, 19, 0.7)
                    rect(knob, line_y - 2, 2, 5)
                end
            else
                rect(12, 8, 0.8, 17)
                rect(21, 8, 0.8, 17)
                for step = 0, 4 do
                    rect(12 - step, 8 + step, 0.8, 0.8)
                    rect(12 + step, 8 + step, 0.8, 0.8)
                    rect(21 - step, 24 - step, 0.8, 0.8)
                    rect(21 + step, 24 - step, 0.8, 0.8)
                end
            end
        end
        local control = require("ui/widget/container/inputcontainer"):new { glyph }
        control.dimen = Geom:new { w = size, h = size }
        control.callback, control.kindlespouse_action = callback, kind
        control.ges_events = { Activate = { require("ui/gesturerange"):new { ges = "tap", range = control.dimen } } }
        control.onActivate = function() callback(); return true end
        return control
    end
    local controls = HorizontalGroup:new { align = "center",
        button("filter", function() return Library.filters(ui) end),
        require("ui/widget/horizontalspan"):new { width = width - pad * 2 - size * 2 },
        button("sort", function()
            return Library.choose(ui, T("sort_view"), {
                { "recent", T("recent") }, { "added", T("added") }, { "title", T("title") },
                { "author", T("author") }, { "progress", T("progress") }, { "grid", T("grid") }, { "list", T("list") },
            }, function(value)
                if value == "grid" or value == "list" then Library.refresh(ui, { view = value })
                else Library.refresh(ui, { sort = value }) end
            end)
        end),
    }
    ui.kindlespouse_toolbar = controls
    return require("ui/widget/container/underlinecontainer"):new { linesize = 1, padding = 0, color = Blitbuffer.COLOR_GRAY,
        FrameContainer:new { width = width, padding = 0, padding_left = pad, padding_right = pad, bordersize = 0, controls } }
end

return Library
