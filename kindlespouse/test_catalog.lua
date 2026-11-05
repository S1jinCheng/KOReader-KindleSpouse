local UIManager = require("ui/uimanager")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local ffi = require("ffi")
local project = assert(os.getenv("KINDLESPOUSE_TEST_ROOT"))
local fixture = assert(os.getenv("KINDLESPOUSE_CATALOG_FIXTURE"))
local root = fixture .. "/books"
package.path = project .. "/plugins/kindlespouse.koplugin/?.lua;plugins/coverbrowser.koplugin/?.lua;" .. package.path
local input_waits, scans, ui_opens, starts, extracted, collisions = 0, 0, 0, 0, 0, 0
local Catalog, Extractor
local main_pid = ffi.C.getpid()
local files_stream = assert(io.open(fixture .. "/files.json", "rb"))
local files = json.decode(files_stream:read("*a"))
files_stream:close()
local function check(callback)
    local ok, failure = pcall(callback)
    if not ok then
        print("CATALOG ACCEPTANCE FAILED: " .. tostring(failure))
        UIManager:quit(1)
    end
end
local function later(callback, delay)
    UIManager:scheduleIn(delay or 0.05, function() check(callback) end)
end
local function waitFor(predicate, callback, attempts)
    attempts = attempts or 0
    assert(attempts < 1800, "Asynchronous operation did not complete")
    if predicate() then callback() else later(function() waitFor(predicate, callback, attempts + 1) end, 0.1) end
end
local original_dir = lfs.dir
lfs.dir = function(directory)
    if directory:sub(1, #root) == root then
        assert(not directory:find("/loop", 1, true) and not directory:find("/.notebooks", 1, true)
            and not directory:find("/ignored.sdr", 1, true), "Excluded directories must never be traversed")
        scans = scans + 1
    end
    return original_dir(directory)
end
local original_wait = Device.input.waitEvent
Device.input.waitEvent = function(self, ...)
    if Catalog and Catalog.roots[root] and Catalog.roots[root].scanning then input_waits = input_waits + 1 end
    return original_wait(self, ...)
end
local registry = require("document/documentregistry")
local original_open = registry.openDocument
registry.openDocument = function(self, ...)
    if ffi.C.getpid() == main_pid then
        ui_opens = ui_opens + 1
        error("Catalog must not open a document in the UI process")
    end
    return original_open(self, ...)
end
local manager = require("bookinfomanager")
local original_extract = manager.extractInBackground
local original_terminate = manager.terminateBackgroundJobs
local fail_start = true
manager.terminateBackgroundJobs = function(self)
    if self:isExtractingInBackground() then collisions = collisions + 1 end
    return original_terminate(self)
end
manager.extractInBackground = function(self, batch)
    assert(#batch <= 50, "Extraction batches must be bounded")
    if fail_start then fail_start = false; return false end
    starts, extracted = starts + 1, extracted + #batch
    return original_extract(self, batch)
end
local function idle()
    return not Extractor.isBusy() and not manager:isExtractingInBackground()
end
local function count()
    return #Catalog.records()
end
local function finish()
    assert(collisions == 0 and ui_opens == 0)
    print("KindleSpouse catalog acceptance passed " .. json.encode({ books = count(), directoryScans = scans,
        inputPollsDuringScan = input_waits, extractionBatches = starts, extractedFiles = extracted,
        uiDocumentOpens = ui_opens, extractionCollisions = collisions, schema = 2 }))
    UIManager:quit()
end
local function verifyActiveCancel(target)
    manager:setBookInfoProperties(target, { ignore_meta = "Y", ignore_cover = "Y" })
    local changed = assert(io.open(target, "ab")); changed:write("changed queue fixture"); changed:close()
    local owner = {}
    Extractor.enqueue(owner, { { filepath = target } }, function() error("Active cancelled owner received completion") end)
    waitFor(function() return Extractor.active ~= nil end, function()
        Extractor.cancel(owner)
        assert(Extractor.active ~= nil, "Cancellation must leave active subprocess running")
        waitFor(idle, function()
            local info = Extractor.cached(target)
            assert(info.ignore_meta and info.ignore_cover and info.has_cover, "Cancelled extraction must preserve ignore preferences and covers")
            finish()
        end)
    end)
end
local function verifyQueue()
    local cancelled, notified = {}, 0
    local live = {}
    local target = fixture .. "/queue.epub"
    local source = assert(io.open(fixture .. "/queue-source.epub", "rb"))
    local output = assert(io.open(target, "wb"))
    output:write(source:read("*a")); output:close(); source:close()
    local foreign = fixture .. "/foreign.epub"
    source = assert(io.open(files[6], "rb")); output = assert(io.open(foreign, "wb"))
    output:write(source:read("*a")); output:close(); source:close()
    assert(original_extract(manager, { { filepath = foreign } }))
    Extractor.enqueue(cancelled, { { filepath = target, cover_specs = { max_cover_w = 40, max_cover_h = 60 } } }, function() error("Cancelled owner received completion") end)
    Extractor.enqueue(live, { { filepath = target, cover_specs = { max_cover_w = 80, max_cover_h = 120 } } }, function(_, info, status)
        assert(status == "ready" and info.cover_fetched and info.has_cover)
        notified = notified + 1
    end)
    later(function()
        assert(manager:isExtractingInBackground(), "Foreign process must remain owned by BookInfoManager")
        Extractor.cancel(cancelled)
        manager:collectSubprocesses()
    end, 0.2)
    waitFor(function() return notified == 1 and idle() end, function()
        local before = starts
        Extractor.enqueue(live, { { filepath = target } }, function(_, info, status)
            assert(info.cover_fetched and info.has_cover and status == "ready", "Fresh metadata request must preserve cover result")
            notified = notified + 1
        end)
        waitFor(function() return notified == 2 and idle() end, function()
            assert(starts == before, "Fresh metadata must not trigger destructive re-extraction")
            verifyActiveCancel(target)
        end)
    end)
end
local function verifyReload()
    Catalog.entries[files[2]].meta_ready = false
    Catalog.flush()
    local removed, changed, added = files[8], files[4], root .. "/restart-added.epub"
    assert(os.remove(removed))
    local source = assert(io.open(files[7], "rb"))
    local bytes = source:read("*a"); source:close()
    local output = assert(io.open(changed, "wb")); output:write(bytes .. "restart change"); output:close()
    output = assert(io.open(added, "wb")); output:write(bytes); output:close()
    local previous_scans, previous_extracted = scans, extracted
    package.loaded.catalog = nil
    Catalog = require("catalog")
    for _, failure in ipairs({ "open", "iterate" }) do
        local state = Catalog.ensure(root)
        UIManager:unschedule(state.scan.step)
        local directory = lfs.dir
        lfs.dir = function(path)
            if path ~= root then return directory(path) end
            if failure == "open" then error("Fixture directory open failure") end
            return function() error("Fixture directory iterator failure") end
        end
        state.scan.step()
        lfs.dir = directory
        assert(state.complete and state.startup_pending and not state.scanning and not state.scan and count() == 500,
            "Failed cached startup scans must preserve the completed cache and stay quiet on retry")
    end
    local completed, startup_events, touch_events = 0, 0, 0
    local startup_owner = {}
    Catalog.subscribe(startup_owner, function(event)
        assert(not event.scanning, "Cached startup must never publish a scanning event")
        if event.kind == "touch" then touch_events = touch_events + 1
        else startup_events = startup_events + 1 end
    end)
    local state = Catalog.ensure(root, function()
        completed = completed + 1
        assert(startup_events == 1, "Cached startup must publish its first update only after enumeration")
        Catalog.unsubscribe(startup_owner)
        assert(count() == 500 and scans > previous_scans, "A fresh module must rescan persisted roots at startup")
        assert(not Catalog.entries[removed] and Catalog.entries[added], "Startup must find externally added and removed books")
        assert(Catalog.entries[files[1]].title == "迁移标题" and Catalog.entries[files[1]].added == 1234)
        waitFor(function() return Catalog.entries[files[2]].meta_ready and idle() end, function()
            assert(Catalog.entries[changed].title == "Fixture Book 006", "Startup must refresh changed file metadata")
            assert(extracted - previous_extracted == 2, "Startup must extract only added and changed files")
            local hot_scans = scans
            local ui = require("apps/filemanager/filemanager").instance
            local chooser, previous_path = ui.file_chooser, ui.file_chooser.path
            chooser.path = root
            for _ = 1, 4 do
                Catalog.ensure(root)
                assert(#Catalog.items(chooser) == 500 and #Catalog.records(root) == 500)
            end
            chooser.path = previous_path
            later(function()
                assert(scans == hot_scans and completed == 2, "Hot ensures and multiple hosts must share exactly one startup scan")
                verifyQueue()
            end)
        end)
    end)
    local scan = assert(state.scan)
    assert(state.quiet_startup and #Catalog.records(root) == 500, "Cached startup must retain its complete library")
    assert(scans == previous_scans, "Startup enumeration must be scheduled in the background")
    assert(Catalog.ensure(root, function() completed = completed + 1 end).scan == scan,
        "Concurrent hosts must reuse the startup scan")
    Catalog.touch(files[1])
    assert(touch_events == 1 and startup_events == 0, "Explicit book changes must stay observable during quiet startup")
end
local function verifyIncremental()
    local before = extracted
    local manual_owner, scanning_events = {}, 0
    Catalog.subscribe(manual_owner, function(event)
        if event.scanning then scanning_events = scanning_events + 1 end
    end)
    local removed = files[3]
    assert(os.remove(removed))
    local changed = assert(io.open(files[4], "ab")); changed:write("changed fixture"); changed:close()
    local source = assert(io.open(files[5], "rb"))
    local added = root .. "/added.epub"
    local output = assert(io.open(added, "wb")); output:write(source:read("*a")); output:close(); source:close()
    Catalog.rescan(root, function()
        assert(scanning_events > 0, "Manual rescans must retain scanning feedback")
        Catalog.unsubscribe(manual_owner)
        assert(count() == 500 and not Catalog.entries[removed] and Catalog.entries[added])
        waitFor(idle, function()
            assert(extracted - before == 2, "Rescan must extract only changed and added files")
            local previous_scans = scans
            local info = require("ui/widget/booklist").book_info_cache
            info[files[2]] = { been_opened = true, status = "reading", percent_finished = 0.42 }
            require("readhistory").hist = { { file = files[2], time = 4242 } }
            Catalog.touch(files[2])
            local fake = { getDocProps = function(_, file, _, cached_only)
                assert(file == files[2] and cached_only == true)
                return { title = "Updated fixture title", authors = "Updated fixture author" }
            end }
            Catalog.attachBookInfo(fake)
            Catalog.touch(files[2], true)
            assert(Catalog.entries[files[2]].title == "Updated fixture title" and Catalog.entries[files[2]].author == "Updated fixture author")
            Catalog.attachBookInfo(require("apps/filemanager/filemanager").instance.bookinfo)
            assert(Catalog.entries[files[2]].progress == 0.42 and Catalog.entries[files[2]].recent == 4242)
            assert(scans == previous_scans)
            local extra = root .. "/event.epub"
            source = assert(io.open(added, "rb")); output = assert(io.open(extra, "wb"))
            output:write(source:read("*a")); output:close(); source:close()
            Catalog.add(extra)
            assert(count() == 501 and scans == previous_scans)
            Catalog.remove(extra)
            assert(os.remove(extra))
            assert(count() == 500 and scans == previous_scans)
            waitFor(idle, verifyReload)
        end)
    end)
end
UIManager:tickAfterNext(function() later(function()
    local first = lfs.symlinkattributes(files[1])
    local settings = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/kindlespouse-library.lua")
    settings:saveSetting("books", { [files[1]] = { title = "迁移标题", author = "旧作者", size = first.size,
        modified = first.modification, added = 1234 } })
    settings:flush()
    Catalog, Extractor = require("catalog"), require("extractor")
    local ui = assert(require("apps/filemanager/filemanager").instance)
    local props = ui.bookinfo.getDocProps
    ui.bookinfo.getDocProps = function(self, file, value, no_open)
        assert(no_open == true)
        return props(self, file, value, no_open)
    end
    Catalog.attachBookInfo(ui.bookinfo)
    local owner, events, scanning_events = {}, 0, 0
    Catalog.subscribe(owner, function(event)
        assert(event.root == root and event.count <= 501)
        events = events + 1
        if event.scanning then scanning_events = scanning_events + 1 end
    end)
    Catalog.ensure(root, function()
        assert(count() == 500 and input_waits > 0 and events > 1 and scanning_events > 0)
        assert(Catalog.entries[files[1]].title == "迁移标题" and Catalog.entries[files[1]].author == "旧作者")
        local previous_scans = scans
        local chooser = ui.file_chooser
        local previous_path = chooser.path
        chooser.path = root
        for _ = 1, 4 do
            assert(#Catalog.items(chooser) == 500)
            Catalog.ensure(root)
            assert(#Catalog.records(root) == 500)
        end
        chooser.path = previous_path
        assert(scans == previous_scans, "Hot root, filters and reads must not enumerate directories")
        Catalog.unsubscribe(owner)
        waitFor(idle, function()
            assert(Catalog.entries[files[2]].title == "Fixture Book 001")
            verifyIncremental()
        end)
    end)
end, 0.1) end)
