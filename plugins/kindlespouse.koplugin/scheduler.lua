local Scheduler = {}
local dependencies
local owner
local next_token = 0
local booted = false
local suspended = false
local fallback_inactive_at
local network_ready_at = 0
local fallback_anchor
local pending = {}
local active
local failures = 0
local retry_at = 0
local last_result
local tick
local watch
local arm
local step
local modes = { books = true, full = true, updates = true, profile = true, titles = true }
local priority = { "books", "full", "updates", "profile", "titles" }

local function now()
    return dependencies.now()
end

local function read(key, default)
    local value = dependencies.read(key, default)
    if value == nil then return default end
    return value
end

local function enabled(mode)
    if dependencies.enabled then return dependencies.enabled(mode) end
    if mode == "books" then return read("kindlespouse_auto_receive", true) ~= false end
    return read("kindlespouse_auto_sync", true) ~= false
end

local function allowed(mode, manual)
    return (manual or enabled(mode)) and not dependencies.paused(mode)
end

local function progress_mode(value)
    if modes[value.mode] then return value.mode end
    if value.booksOnly then return "books" end
    if value.profileOnly then return "profile" end
    if value.titlesOnly then return "titles" end
    if value.updatesOnly then return "updates" end
    return "full"
end

local function signature(value)
    return table.concat({ tostring(value.runId or value.pid or ""), tostring(value.startedAt or ""),
        tostring(value.updatedAt or ""), tostring(value.completedAt or ""), tostring(value.state or ""),
        progress_mode(value), tostring(value.error or "") }, "|")
end

local function enqueue(mode, manual, due, replace)
    local previous = pending[mode]
    if previous and (not replace or previous.manual) then due = math.min(due, previous.due) end
    pending[mode] = { mode = mode, manual = manual or previous and previous.manual or false,
        due = due, requestedAt = now() }
end

local function release(job)
    if job.reservation and dependencies.release then dependencies.release(job.reservation) end
    job.reservation = nil
end

local function failed(job, message)
    release(job)
    active = nil
    failures = math.min(failures + 1, 5)
    retry_at = now() + math.min(60 * 2 ^ (failures - 1), 900)
    if not job.external then enqueue(job.mode, job.manual, retry_at, false) end
    last_result = { state = "failed", mode = job.mode, manual = job.manual == true, error = message, retryAt = retry_at }
    if dependencies.notify and owner then dependencies.notify(last_result, owner.host) end
end

local function completed(job, value)
    release(job)
    active = nil
    failures, retry_at = 0, 0
    local stamp = tonumber(value.completedAt) or now()
    if job.mode == "full" then
        dependencies.save("kindlespouse_last_sync", stamp)
        dependencies.save("kindlespouse_last_updates", stamp)
        fallback_anchor = now()
        if job.generation ~= nil and tonumber(read("kindlespouse_sync_generation", 0)) == job.generation then
            dependencies.save("kindlespouse_sync_dirty", false)
            dependencies.save("kindlespouse_reading_dirty", false)
        end
        for _, mode in ipairs({ "books", "updates" }) do
            local request = pending[mode]
            if request and not request.manual and request.requestedAt <= job.launchedAt then pending[mode] = nil end
        end
    elseif job.mode == "updates" then
        dependencies.save("kindlespouse_last_updates", stamp)
    elseif job.mode == "books" then
        dependencies.save("kindlespouse_last_books_check", stamp)
    end
    last_result = { state = "completed", mode = job.mode, manual = job.manual == true, progress = value }
    if dependencies.notify and owner then dependencies.notify(last_result, owner.host) end
end

local function monitor()
    local job = active
    if not job then return end
    local value = dependencies.progress() or {}
    local running = dependencies.running()
    local fresh = progress_mode(value) == job.mode and signature(value) ~= job.baseline
        and (tonumber(value.startedAt) or -math.huge) >= job.launchedAt
    if job.external then
        fresh = progress_mode(value) == job.mode and value.startedAt == job.startedAt
    elseif job.startedAt ~= nil then
        fresh = fresh and value.startedAt == job.startedAt
        if job.runId and value.runId then fresh = fresh and value.runId == job.runId end
        if job.pid and value.pid then fresh = fresh and value.pid == job.pid end
    end
    if fresh then
        job.startedAt = value.startedAt
        job.runId = value.runId or job.runId
        job.pid = value.pid or job.pid
        if value.state == "running" or value.state == "pausing" then
            job.observed = true
            release(job)
        elseif value.state == "completed" then
            completed(job, value)
            return
        elseif value.state == "failed" then
            failed(job, value.error or "Sync failed")
            return
        elseif value.state == "paused" then
            release(job)
            active = nil
            last_result = { state = "paused", mode = job.mode, manual = job.manual == true }
            if dependencies.notify and owner then dependencies.notify(last_result, owner.host) end
            return
        end
    end
    if not running and job.observed then
        failed(job, "Sync stopped before a matching result was available")
    elseif not job.observed and now() >= job.launchedAt + 20 then
        failed(job, "Sync did not publish a fresh result within 20 seconds")
    end
end

local function launch(request)
    local value = dependencies.progress() or {}
    local job = { mode = request.mode, manual = request.manual, launchedAt = now(), baseline = signature(value),
        generation = request.mode == "full" and tonumber(read("kindlespouse_sync_generation", 0)) or nil }
    active = job
    if dependencies.reserve then
        local ok, token, message = pcall(dependencies.reserve, job.mode, job.manual)
        if not ok or not token then failed(job, ok and (message or "Another launch is reserved") or tostring(token)); return end
        job.reservation = token
    end
    local ok, accepted, message = pcall(dependencies.launch, job.mode, job.manual, owner.host)
    if not ok or not accepted then
        failed(job, ok and (message or "Cannot launch sync") or tostring(accepted))
        return
    end
    if pending[request.mode] == request then pending[request.mode] = nil end
end

local function fallback_interval()
    return dependencies.reading() and 1800 or 900
end

step = function()
    if not owner or suspended then return end
    if active then monitor(); arm(); return end
    if dependencies.running() then
        local value = dependencies.progress() or {}
        active = { external = true, mode = progress_mode(value), launchedAt = now(), startedAt = value.startedAt,
            observed = true }
        arm()
        return
    end
    if not dependencies.connected() then arm(); return end
    local current = now()
    if current >= fallback_anchor + fallback_interval() then
        fallback_anchor = current
        for _, mode in ipairs({ "books", "updates" }) do
            if enabled(mode) then enqueue(mode, false, current, false) end
        end
    end
    local selected
    for _, mode in ipairs(priority) do
        local request = pending[mode]
        if request and allowed(mode, request.manual) and current >= math.max(request.due, retry_at, request.manual and 0 or network_ready_at) then
            if not selected or request.manual and not selected.manual then selected = request end
        end
    end
    if selected then launch(selected) end
    arm()
end

tick = function() step() end
watch = function() step() end

arm = function()
    dependencies.unschedule(tick)
    dependencies.unschedule(watch)
    if not owner or suspended then return end
    if active then
        dependencies.schedule(active.observed and 5 or 1, watch)
        return
    end
    if not dependencies.connected() then return end
    local due
    if enabled("books") or enabled("updates") then due = fallback_anchor + fallback_interval() end
    for mode, request in pairs(pending) do
        if allowed(mode, request.manual) then
            local deadline = math.max(request.due, retry_at, request.manual and 0 or network_ready_at)
            due = due and math.min(due, deadline) or deadline
        end
    end
    if due then dependencies.schedule(math.max(0, due - now()), tick) end
end

function Scheduler.configure(value)
    for _, key in ipairs({ "now", "read", "save", "connected", "reading", "paused", "running", "progress", "launch", "schedule", "unschedule" }) do
        assert(type(value[key]) == "function", "Missing scheduler dependency: " .. key)
    end
    if dependencies then dependencies.unschedule(tick); dependencies.unschedule(watch) end
    dependencies = value
    fallback_anchor = fallback_anchor or now()
    if not dependencies.connected() then fallback_inactive_at = fallback_inactive_at or now() end
    arm()
    return Scheduler
end

function Scheduler.attach(host)
    assert(dependencies, "Configure scheduler before attaching")
    next_token = next_token + 1
    local token = { id = next_token, host = host }
    owner = token
    if not booted then
        booted = true
        if now() - (tonumber(read("kindlespouse_last_sync", 0)) or 0) > 600 then enqueue("full", false, now() + 1, false) end
    end
    arm()
    return token
end

function Scheduler.detach(token)
    if owner == token then owner = nil; arm() end
end

function Scheduler.request(mode, manual)
    assert(modes[mode], "Unknown sync mode")
    if manual then retry_at = 0 end
    enqueue(mode, manual == true, now(), false)
    arm()
    return true
end

function Scheduler.markDirty(kind)
    local reading = kind == "page" or kind == "reading"
    dependencies.save(reading and "kindlespouse_reading_dirty" or "kindlespouse_sync_dirty", true)
    dependencies.save("kindlespouse_sync_generation", (tonumber(read("kindlespouse_sync_generation", 0)) or 0) + 1)
    if not reading then enqueue("full", false, now() + 15, true) end
    arm()
end

function Scheduler.pageDirty()
    return Scheduler.markDirty("page")
end

function Scheduler.networkConnected()
    if fallback_inactive_at and not suspended then
        fallback_anchor = fallback_anchor + math.max(0, now() - fallback_inactive_at)
        fallback_inactive_at = nil
    end
    network_ready_at = now() + 8
    retry_at = 0
    local dirty = read("kindlespouse_sync_dirty", false) or read("kindlespouse_reading_dirty", false)
    enqueue(dirty and "full" or "updates", false, now() + 8, false)
    arm()
end

function Scheduler.networkDisconnected()
    fallback_inactive_at = fallback_inactive_at or now()
    arm()
end

function Scheduler.suspend()
    fallback_inactive_at = fallback_inactive_at or now()
    suspended = true
    arm()
end

function Scheduler.resume()
    suspended = false
    if fallback_inactive_at and dependencies.connected() then
        fallback_anchor = fallback_anchor + math.max(0, now() - fallback_inactive_at)
        fallback_inactive_at = nil
    end
    if now() - (tonumber(read("kindlespouse_last_sync", 0)) or 0) > 1800 then enqueue("full", false, now() + 8, false) end
    arm()
end

function Scheduler.snapshot()
    local queued = {}
    for mode, request in pairs(pending) do queued[mode] = { due = request.due, manual = request.manual } end
    return { attached = owner ~= nil, suspended = suspended, pending = queued, launch_pending = active ~= nil and not active.observed,
        running = active ~= nil and active.observed == true, mode = active and active.mode, failures = failures,
        retry_at = retry_at, result = last_result, generation = tonumber(read("kindlespouse_sync_generation", 0)) }
end

return Scheduler
