local UIManager = require("ui/uimanager")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local fixture = assert(os.getenv("KINDLESPOUSE_CACHED_FIXTURE"))
local expected = assert(tonumber(os.getenv("KINDLESPOUSE_CACHED_COUNT")))
local phase = assert(os.getenv("KINDLESPOUSE_CACHED_PHASE"))
local root = fixture .. "/books"
local external = root .. "/external-added.epub"
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;plugins/coverbrowser.koplugin/?.lua;" .. package.path
Device.hasKeyboard = function() return false end
Device.hasKeys = function() return false end
local Catalog = require("catalog")
local Extractor = require("extractor")
local scans, events, scanning_events, cold_feedback, captured = 0, {}, 0, 0, false
local original_dir = lfs.dir
lfs.dir = function(directory)
    if directory == root or directory:sub(1, #root + 1) == root .. "/" then scans = scans + 1 end
    return original_dir(directory)
end
local function check(callback)
    local ok, failure = pcall(callback)
    if not ok then
        print("CACHED STARTUP ACCEPTANCE FAILED: " .. tostring(failure))
        UIManager:quit(1)
    end
end
local owner = {}
Catalog.subscribe(owner, function(event)
    if event.root ~= root then return end
    events[#events + 1] = { kind = event.kind, scanning = event.scanning, done = event.done, count = event.count }
    if event.scanning then
        scanning_events = scanning_events + 1
        if phase == "cached" then error("Cached startup emitted scanning=true") end
        cold_feedback = cold_feedback + 1
    end
end)
local function assertQuiet(widget, seen, texts)
    if type(widget) ~= "table" or seen[widget] then return end
    seen[widget] = true
    for key, value in pairs(widget) do
        if (key == "text" or key == "title" or key == "subtitle") and type(value) == "string" then
            assert(not value:find("正在整理书库", 1, true) and not value:find("Organizing library", 1, true), "Cached startup displayed scan text: " .. value)
            texts[#texts + 1] = value
        elseif type(key) == "number" or key == "title_widget" or key == "subtitle_widget" then
            assertQuiet(value, seen, texts)
        end
    end
end
local snapshot
local original_ensure = Catalog.ensure
Catalog.ensure = function(directory, on_done)
    local state = original_ensure(directory, on_done)
    if phase == "cached" and directory == root and state.scan and not state.scan.acceptance_wrapped then
        local scan = state.scan
        scan.acceptance_wrapped = true
        UIManager:unschedule(scan.step)
        local step = scan.step
        scan.step = function()
            check(function()
                step()
                if captured then return end
                assert(state.scanning and state.scan == scan and state.quiet_startup, "Screenshot must be taken while the cached startup scan is in progress")
                assert(scan.seen[external], "The in-progress scan must already have found the external addition")
                local ui = assert(FileManager.instance)
                assert(ui.kindlespouse_patched and require("home").enabled(), "The actual plugin must own Home")
                local shelf = assert(ui.kindlespouse_shelf)
                assert(not shelf.scanning_label, "Cached shelf must not create a scanning label")
                assert(#shelf.items == expected and #ui.file_chooser.item_table == expected and #Catalog.records(root) == expected, "Cached books must remain visible until the scan finishes")
                assert(not Catalog.entries[external], "An incomplete startup scan must not publish a partial list")
                assert(#events == 0, "Cached startup must not publish background progress before completion")
                local texts = {}
                UIManager:widgetRepaint(ui, 0, 0)
                assertQuiet(ui[1], {}, texts)
                assertQuiet(ui.title_bar, {}, texts)
                assertQuiet(shelf.scanning_label, {}, texts)
                Device.screen:shot(fixture .. "/cached-startup-in-progress.png")
                snapshot = { scanning = state.scanning, count = #shelf.items, scans = scans, externalFound = scan.seen[external], texts = texts }
                local stream = assert(io.open(fixture .. "/in-progress.json", "w"))
                stream:write(json.encode(snapshot)); stream:close()
                captured = true
                Catalog.cancel(root)
                assert(state.complete and state.startup_pending and not state.scanning and #Catalog.records(root) == expected,
                    "Cancelling a background startup must retain the completed cached library")
                assert(not Catalog.books[external], "Cancelled startup must not persist its staged additions")
                Catalog.flush()
                local reopened = Catalog.ensure(root)
                assert(reopened.scanning and reopened.quiet_startup and #Catalog.records(root) == expected,
                    "Reopening a cancelled cached startup must stay quiet")
            end)
        end
        UIManager:scheduleIn(0.01, scan.step)
    end
    return state
end
local attempts = 0
local function finishWhenReady()
    check(function()
        attempts = attempts + 1
        assert(attempts < 1800, "Cached startup acceptance timed out")
        local ui = FileManager.instance
        local state = Catalog.roots[root]
        local manager = require("bookinfomanager")
        if not ui or not state or state.scanning or not state.complete or Extractor.isBusy() or manager:isExtractingInBackground() or ui.kindlespouse_catalog_dirty then
            UIManager:scheduleIn(0.1, finishWhenReady)
            return
        end
        local count = #Catalog.records(root)
        if phase == "warm" then
            assert(count == expected and cold_feedback > 0, "Cold scans must keep their feedback")
        else
            assert(captured and count == expected + 1 and Catalog.entries[external], "The external addition must appear after the background scan")
            assert(#ui.kindlespouse_shelf.items == count and #ui.file_chooser.item_table == count)
            assert(scanning_events == 0)
        end
        local before = scans
        local Library = require("library")
        for _ = 1, 4 do
            Catalog.ensure(root)
            assert(#Catalog.items(ui.file_chooser) == count)
            Library.refresh(ui, { query = "缓存书籍" })
            Library.refresh(ui, { query = "" })
        end
        assert(scans == before, "Hot ensures and filters must enumerate zero book directories")
        Catalog.flush()
        local report = { pid = require("ffi").C.getpid(), finalCount = count, directoryScans = scans, scanningEvents = scanning_events,
            snapshotScanning = snapshot and snapshot.scanning or false, snapshotCount = snapshot and snapshot.count or 0,
            quietReopen = phase == "cached" and captured, hotDirectoryScans = scans - before }
        local stream = assert(io.open(fixture .. "/" .. phase .. "-events.json", "w"))
        stream:write(json.encode(events)); stream:close()
        print("KindleSpouse cached startup " .. phase .. " acceptance passed " .. json.encode(report))
        UIManager:quit()
    end)
end
UIManager:tickAfterNext(function() UIManager:scheduleIn(0.1, finishWhenReady) end)
