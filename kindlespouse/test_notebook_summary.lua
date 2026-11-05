local UIManager = require("ui/uimanager")
local ReaderUI = require("apps/reader/readerui")
local Registry = require("document/documentregistry")
local Device = require("device")
local Geom = require("ui/geometry")
local DocSettings = require("docsettings")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local root = assert(os.getenv("KINDLESPOUSE_TEST_SANDBOX"))
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;" .. package.path
if not pcall(require, "i18n") then
    local labels = {
        ["notebook.summary"] = "Notes & highlights", ["notebook.books"] = "← Books",
        ["notebook.counts"] = "%1 highlights · %2 notes", ["notebook.page"] = "Page %1",
        ["notebook.loading"] = "Reading annotations…", ["notebook.empty"] = "No matching notes or highlights",
        ["notebook.search"] = "Search notes", ["notebook.cancel"] = "Cancel",
        ["notebook.refresh"] = "Refresh", ["notebook.native"] = "Kindle notebooks",
        ["notebook.note"] = "Note: %1", ["notebook.location_unavailable"] = "This annotation position is no longer available.",
    }
    package.loaded.i18n = { T = function(key, ...)
        local values = { ... }
        return (labels[key] or key):gsub("%%(%d+)", function(index) return tostring(values[tonumber(index)]) end)
    end }
end
local Index = require("notebook/index")
local View = require("notebook/view")
local Menu = require("ui/widget/menu")
local menu_update, menu_heights = Menu.updateItems, Menu.setupItemHeights
local function write(filename, bytes)
    local stream = assert(io.open(filename, "wb"))
    assert(stream:write(bytes)); assert(stream:close())
end
local function read(filename)
    local stream = assert(io.open(filename, "rb")); local bytes = stream:read("*a"); stream:close(); return bytes
end
local function check(callback)
    local ok, error = xpcall(callback, debug.traceback)
    if not ok then print("NOTEBOOK SUMMARY CHECK FAILED " .. tostring(error)); UIManager:quit(1) end
end
local function after(delay, callback) UIManager:scheduleIn(delay, function() check(callback) end) end
local function ready(index, callback, attempts)
    after(0.02, function()
        if index.pending then
            assert((attempts or 0) < 200, "Summary refresh did not complete")
            return ready(index, callback, (attempts or 0) + 1)
        end
        callback()
    end)
end
local function item(number, note)
    return { page = "/body/DocFragment[1]/body/p[" .. number .. "]", pos0 = "/body/DocFragment[1]/body/p[" .. number .. "]",
        pos1 = "/body/DocFragment[1]/body/p[" .. number .. "]/text().1", text = "Synthetic quotation " .. number,
        note = note, drawer = "lighten", color = "yellow", datetime = "2026-11-04 10:00:00" }
end

UIManager:tickAfterNext(function()
    after(2, function()
        local ui = assert(ReaderUI.instance)
        assert(ui.document.info.number_of_pages > 3)
        Device.hasKeyboard = function() return false end
        Device.hasKeys = function() return false end
        local files = root .. "/books"
        util.makePath(files)
        util.makePath(root .. "/.notebooks")
        write(root .. "/.notebooks/nbk", "Untouched synthetic native notebook")
        local records = {}
        local first
        for number = 1, 120 do
            local filename = files .. "/fixture-" .. number .. ".txt"
            write(filename, "Generated annotation fixture")
            records[#records + 1] = { path = filename, name = "Fixture " .. number, title = "Fixture " .. number, author = "Synthetic author", recent = number, status = "reading" }
            local settings = DocSettings:open(filename)
            if number == 1 then
                first = filename
                records[#records].title = "山间来信 · A Quiet Morning"
                settings:saveSetting("annotations", { item(10, "Searchable thoughtful note"), item(2, "Earlier note") })
                local stale = item(2, "Stale alternate note")
                stale.text, stale.datetime = "Stale alternate quotation", "2026-11-05 10:00:00"
                settings:saveSetting("annotations_rolling", { stale })
            elseif number == 2 then
                settings:saveSetting("annotations", { { page = 7, note = "Only a note", datetime = "2026-11-04" } })
            elseif number == 3 then settings:saveSetting("annotations", { item(1) })
            elseif number == 4 then settings:saveSetting("annotations", { { page = 5, text = "Plain bookmark" } })
            elseif number == 6 then
                settings:saveSetting("annotations", {})
                settings:saveSetting("annotations_rolling", { item(6, "Deleted primary must stay deleted") })
            elseif number == 7 then
                settings:saveSetting("annotations_rolling", { item(7, "Absent primary must stay absent") })
                settings:saveSetting("annotations_paging", { { page = 7, note = "Other engine backup" } })
            end
            assert(settings:flush(nil, true))
        end
        local alternate_path = DocSettings:getSidecarDir(records[3].path, "dir")
        util.makePath(alternate_path)
        local alternate = require("luasettings"):open(alternate_path .. "/" .. DocSettings.getSidecarFilename(records[3].path))
        alternate:saveSetting("annotations", { item(8, "Newest location note") })
        alternate:flush()
        assert(lfs.touch(alternate.file, os.time() + 2, os.time() + 2))
        local corrupt = DocSettings:findSidecarFile(records[5].path)
        write(corrupt, "return 17")
        local corrupt_bytes = read(corrupt)
        local pointer
        for y = 120, 600, 40 do
            local word = ui.document:getWordFromPosition(Geom:new { x = 300, y = y }, true)
            if word and word.pos0 then pointer = word.pos0; break end
        end
        assert(pointer)
        ui.annotation.annotations = { { page = pointer, pos0 = pointer, pos1 = pointer, text = "Unsaved quotation", note = "Memory-only note", drawer = "lighten", datetime = "2026-11-04 12:00:00" } }
        ui.doc_settings:saveSetting("annotations_rolling", { item(12, "Stale live-reader alternate") })
        ui.doc_settings:saveSetting("annotations_paging", { { page = 12, note = "Stale live-reader paging alternate" } })
        records[#records + 1] = { path = ui.document.file, title = "Currently open book", recent = 999, status = "reading" }
        local new_record = { path = files .. "/new.txt", title = "Unopened book", status = "new" }
        write(new_record.path, "Generated unopened fixture")
        local unopened = DocSettings:open(new_record.path)
        unopened:saveSetting("annotations", { item(99, "Must skip unopened book") })
        assert(unopened:flush(nil, true))
        records[#records + 1] = new_record
        local oversized_record = { path = files .. "/oversized.txt", status = "reading" }
        write(oversized_record.path, "Generated oversized fixture")
        local oversized = DocSettings:open(oversized_record.path)
        oversized:saveSetting("annotations", { item(98, "Must not load oversized metadata") })
        assert(oversized:flush(nil, true))
        write(DocSettings:findSidecarFile(oversized_record.path), "return {}" .. string.rep(" ", 10 * 1024 * 1024))
        local catalog_calls = 0
        local catalog = { records = function() catalog_calls = catalog_calls + 1; return records end }
        local old_dir = lfs.dir
        lfs.dir = function(path, ...) assert(path ~= files, "Summary must not enumerate book folders"); return old_dir(path, ...) end
        local old_open = Registry.openDocument
        Registry.openDocument = function() error("Summary must never open a document") end
        local old_full_open = DocSettings.open
        DocSettings.open = function() error("Summary must not call mutating DocSettings.open") end
        local old_read, reads = DocSettings.openSettingsFile, 0
        DocSettings.openSettingsFile = function(...) reads = reads + 1; return old_read(...) end
        local old_find, lookups = DocSettings.findSidecarFile, 0
        DocSettings.findSidecarFile = function(self, filename, ...)
            lookups = lookups + 1
            assert(filename ~= new_record.path, "New books must not perform sidecar lookup")
            return old_find(self, filename, ...)
        end
        local old_attributes, stats = lfs.attributes, 0
        lfs.attributes = function(...) stats = stats + 1; return old_attributes(...) end
        local index = Index.new({ catalog = catalog })
        local prior_reads, prior_lookups, prior_stats = reads, lookups, stats
        assert(#index:read(new_record) == 0)
        assert(reads == prior_reads and lookups == prior_lookups and stats == prior_stats,
            "New status must skip sidecar lookup, stat and open")
        assert(#index:read(oversized_record) == 0 and reads == prior_reads,
            "Oversized sidecars must not be opened")
        G_reader_settings:saveSetting("document_metadata_folder", "doc")
        assert(index:read(records[3])[1].note == "", "Summary must use the API's preferred document location")
        G_reader_settings:saveSetting("document_metadata_folder", "dir")
        assert(index:read(records[3])[1].note == "Newest location note", "Summary must follow the API's configured directory location")
        local batches = {}
        index:refresh(function(_, complete)
            batches[#batches + 1] = index.processed
            if not complete then return end
            check(function()
                assert(#batches == 3 and batches[1] == 50 and batches[2] == 100 and batches[3] == 121)
                assert(index.delay > 0 and index.batch_size == 50 and #index.books == 4)
                assert(lookups >= 120 and index.books[1].path == ui.document.file)
                assert(#index:search("Must skip unopened") == 0)
                assert(#index:search("Newest location note") == 1, "Summary must use the API-selected configured sidecar location")
                local found = index:search("thoughtful")
                assert(#found == 1 and found[1].highlights == 2 and found[1].notes == 2)
                local annotations = index:search("", first)
                assert(#annotations == 2 and annotations[1].position:find("p[2]", 1, true))
                assert(#index:search("Earlier", first) == 1 and #index:search("memory-only") == 1)
                assert(#index:search("Stale") == 0 and #index:read(records[6]) == 0 and #index:read(records[7]) == 0,
                    "Engine alternates must not duplicate, resurrect or supply missing primary annotations")
                local live = ui.annotation.annotations
                ui.annotation.annotations = {}
                assert(#index:read(records[#records - 1]) == 0, "An empty live primary must override saved engine alternates")
                ui.annotation.annotations = live
                local no_highlight = index:search("Only a note")
                assert(#no_highlight == 1 and no_highlight[1].highlights == 0 and no_highlight[1].notes == 1)
                assert(read(corrupt) == corrupt_bytes)
                local initial_reads = reads
                index:refresh(function(_, done)
                    if not done then return end
                    check(function()
                        assert(reads == initial_reads, "Unchanged sidecars must use the cache")
                        local settings = old_full_open(DocSettings, first)
                        local changed_items = { item(3, "Changed note after refresh · 留下完整的思考，不省略正文。") }
                        changed_items[1].text = "清晨读到这里，窗外的河水缓缓流过。The complete quotation remains visible across wrapped lines."
                        changed_items[1].chapter = "第一章 · 清晨"
                        for number = 4, 24 do
                            local entry = item(number, "Thoughtful note " .. number)
                            entry.chapter = "Generated chapter " .. number
                            changed_items[#changed_items + 1] = entry
                        end
                        local long_entry = item(25, string.rep("A long reflective note. ", 160))
                        long_entry.text = "Oversized row " .. string.rep("A complete stored quotation. ", 160)
                        long_entry.chapter = "A long annotation"
                        changed_items[#changed_items + 1] = long_entry
                        settings:saveSetting("annotations", changed_items)
                        settings:delSetting("annotations_rolling")
                        assert(settings:flush(nil, true))
                        local sidecar = DocSettings:findSidecarFile(first)
                        assert(lfs.touch(sidecar, os.time() + 5, os.time() + 5))
                        index:refresh(function(_, changed)
                            if not changed then return end
                            check(function()
                                assert(reads == initial_reads + 1)
                                assert(#index:search("Changed note") == 1)
                                local before = #UIManager._window_stack
                                local companion = { ui = ui, notify = function() end }
                                local panel = View.open(companion, Device.screen:getHeight() - 150, { index = index, catalog = catalog })
                                assert(#UIManager._window_stack == before, "Embedding must not show a global menu")
                                UIManager:show(panel)
                                ready(index, function()
                                    assert(#panel.menu.item_table == 4)
                                    assert(panel:getSize().h <= Device.screen:getHeight() - 150)
                                    panel:search("Changed note")
                                    assert(#panel.menu.item_table == 1 and panel.menu.item_table[1].book.path == first)
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    local book_row = panel.menu.item_group[1]
                                    book_row:onTapSelect(nil, { pos = Geom:new { x = book_row[1].dimen.x + 10, y = book_row[1].dimen.y + 10 } })
                                    assert(panel.book.path == first and #panel.menu.item_table == 1)
                                    assert(panel.title.text == records[1].title and not panel.title.text:find("fixture-1.txt", 1, true))
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    local row = panel.menu.item_group[1]
                                    local rich = assert(row.rich)
                                    assert(rich.quote.text == changed_items[1].text and rich.note.text == require("i18n").T("notebook.note", changed_items[1].note))
                                    assert(rich.metadata.text == "第一章 · 清晨 · 2026-11-04")
                                    assert(rich.quote.face.orig_size == 18 and rich.note.face.orig_size == 18 and rich.metadata.face.orig_size == 13)
                                    assert(rich.metadata.fgcolor == require("ffi/blitbuffer").COLOR_DARK_GRAY)
                                    assert(rich.note.dimen.x > rich.quote.dimen.x and rich.note.dimen.y > rich.quote.dimen.y and rich.metadata.dimen.y > rich.note.dimen.y)
                                    assert(row._underline_container.linesize > 0 and row._underline_container.color == require("ffi/blitbuffer").COLOR_LIGHT_GRAY)
                                    assert(#rich.quote.vertical_string_list > 1 and not rich.quote.line_with_ellipsis and not rich.note.line_with_ellipsis)
                                    Device.screen:shot(root .. "/notebook-summary.png")
                                    panel:search("")
                                    assert(#panel.menu.item_table == 23 and panel.menu.page_num > 1)
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    assert(#panel.menu.item_group > 1)
                                    Device.screen:shot(root .. "/notebook-detail-layers.png")
                                    panel.menu:onNextPage()
                                    assert(panel.menu.page == 2 and panel.menu.item_group[1].rich)
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    Device.screen:shot(root .. "/notebook-detail-page2.png")
                                    panel.menu:onPrevPage()
                                    assert(panel.menu.page == 1)
                                    panel:search("Oversized row")
                                    assert(panel.menu.item_table[1].height <= panel.menu.available_height)
                                    local long_row = panel.menu.item_group[1].rich
                                    assert(long_row.quote.line_with_ellipsis and long_row.note.line_with_ellipsis)
                                    assert(long_row.quote.text == long_entry.text and long_row.note.text == require("i18n").T("notebook.note", long_entry.note))
                                    panel:search("Thoughtful note 24")
                                    assert(#panel.menu.item_table == 1 and panel.menu.item_table[1].annotation.note == "Thoughtful note 24")
                                    panel.menu.item_group[1]:onFocus()
                                    assert(panel.menu.item_group[1]._underline_container.color == require("ffi/blitbuffer").COLOR_BLACK)
                                    panel.menu.item_group[1]:onUnfocus()
                                    assert(panel.menu.item_group[1]._underline_container.color == require("ffi/blitbuffer").COLOR_LIGHT_GRAY)
                                    assert(Menu.updateItems == menu_update and Menu.setupItemHeights == menu_heights)
                                    panel:search("No matching synthetic annotation")
                                    assert(#panel.menu.item_table == 1 and panel.menu.item_table[1].select_enabled == false and not panel.menu.item_group[1].rich)
                                    panel.menu:onClose()
                                    assert(not panel.book)
                                    panel:search("Only a note")
                                    panel.menu:onMenuSelect(panel.menu.item_table[1])
                                    local note_only = panel.menu.item_group[1].rich
                                    assert(not note_only.quote and note_only.note.text == require("i18n").T("notebook.note", "Only a note"))
                                    assert(note_only.metadata.text == require("i18n").T("notebook.page", 7) .. " · 2026-11-04")
                                    panel.menu:onClose()
                                    panel:search("Memory-only")
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    local live_row = panel.menu.item_group[1]
                                    live_row:onTapSelect(nil, { pos = Geom:new { x = live_row[1].dimen.x + 10, y = live_row[1].dimen.y + 10 } })
                                    local link = ui.link.addCurrentLocationToStack
                                    local event_handler = ui.handleEvent
                                    local pushed, jumped = 0, 0
                                    ui.link.addCurrentLocationToStack = function(self, ...) pushed = pushed + 1; return link(self, ...) end
                                    ui.handleEvent = function(self, event)
                                        if event.handler == "onGotoXPointer" then jumped = jumped + 1 end
                                        return event_handler(self, event)
                                    end
                                    UIManager:widgetRepaint(panel, 0, 0)
                                    local annotation_row = panel.menu.item_group[1]
                                    annotation_row:onTapSelect(nil, { pos = Geom:new { x = annotation_row[1].dimen.x + 10, y = annotation_row[1].dimen.y + 10 } })
                                    assert(pushed == 1 and jumped == 1 and panel.closed)
                                    View.navigate(ui.document.file, { position = "/invalid/annotation/position" })
                                    assert(pushed == 1 and jumped == 1)
                                    UIManager:close(UIManager:getTopmostVisibleWidget())
                                    ui.link.addCurrentLocationToStack, ui.handleEvent = link, event_handler
                                    local show = ReaderUI.showReader
                                    local calls = 0
                                    ReaderUI.showReader = function(_, filename, provider, seamless, forced, callback)
                                        calls = calls + 1
                                        assert(filename == first and provider == nil and seamless == nil and forced == nil)
                                        local reader = { document = { file = first, info = { number_of_pages = 10 } }, paging = {},
                                            link = { addCurrentLocationToStack = function() pushed = pushed + 1 end },
                                            handleEvent = function(_, event) assert(event.handler == "onGotoPage" and event.args[1] == 7); jumped = jumped + 1 end }
                                        callback(reader)
                                    end
                                    View.navigate(first, { position = 7 })
                                    assert(calls == 1 and pushed == 2 and jumped == 2)
                                    ReaderUI.showReader = show
                                    local prior_reads = reads
                                    Index.invalidate(first)
                                    index:read(records[1])
                                    assert(reads == prior_reads + 1)
                                    index:refresh(function() error("Cancelled callback must not run") end)
                                    index:cancel()
                                    local canceled = reads
                                    ready(index, function()
                                        assert(reads == canceled)
                                        assert(read(root .. "/.notebooks/nbk") == "Untouched synthetic native notebook")
                                        assert(read(corrupt) == corrupt_bytes)
                                        Registry.openDocument, DocSettings.openSettingsFile, lfs.dir = old_open, old_read, old_dir
                                        DocSettings.findSidecarFile, lfs.attributes, DocSettings.open = old_find, old_attributes, old_full_open
                                        assert(catalog_calls >= 4)
                                        ui:onClose()
                                        print("NOTEBOOK SUMMARY CHECK PASSED: real sidecars, primary counts, cache, catalog title, rich layers, search, paging, focus, taps, navigation and cancellation")
                                        UIManager:quit()
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
