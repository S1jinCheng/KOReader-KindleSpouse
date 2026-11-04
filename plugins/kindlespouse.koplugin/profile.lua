local T = require("i18n").T
local Device = require("device")
local UIManager = require("ui/uimanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local lfs = require("libs/libkoreader-lfs")
local json = require("json")
local Screen = Device.screen
local Profile = {}
local Panel = InputContainer:extend { covers_fullscreen = true }
local Calendar = InputContainer:extend {}
local stages = {
    checking_pairing = T("stage_checking_pairing"), checking_local_profile = T("profile_connecting_desktop"),
    receiving_local_profile = T("profile_receiving_lan"), receiving_profile = T("profile_receiving_cloud"),
    syncing_titles = T("profile_syncing_titles"), checking_inbox = T("stage_checking_inbox"), checking_book_folder = T("profile_checking_folder"),
    receiving_folder_books = T("profile_receiving_cloud_books"), receiving_books = T("stage_receiving_books"), saving_receipts = T("profile_confirming"),
    scanning_notes = T("profile_preparing_notes"), backing_up_catalog = T("profile_preparing_history"), checking_cloud = T("profile_checking_backups"),
    uploading_notes = T("profile_uploading_notes"), packing_notes = T("profile_packing_notes"), uploading_bundles = T("profile_uploading_backups"),
    publishing = T("profile_verifying"), receiving_annotations = T("profile_receiving_edits"),
}

function Profile.read(directory, name)
    local file = io.open(directory .. "/" .. name, "rb")
    if not file then return end
    local bytes = file:read(65537)
    file:close()
    if not bytes or #bytes > 65536 then return end
    local ok, data = pcall(json.decode, bytes)
    if ok and type(data) == "table" then return data end
end

function Profile.snapshot(companion)
    local directory = companion.directory or "/mnt/us/kindlespouse"
    local person = Profile.read(directory, "sleep-profile.json") or {}
    local config = Profile.read(directory, "config.json")
    local progress = companion.status and companion:status() or Profile.read(directory, "progress.json") or { state = "idle" }
    local receipt = Profile.read(directory, "profile-receipt.json")
    local local_receipt = Profile.read(directory, "lan-profile-receipt.json")
    local route = T("profile_cloud")
    if local_receipt and (not receipt or tostring(local_receipt.receivedAt or "") > tostring(receipt.receivedAt or "")) then
        receipt, route = local_receipt, T("profile_lan")
    end
    local avatar
    if type(person.avatarHash) == "string" and #person.avatarHash == 64 and person.avatarHash:match("^[a-f0-9]+$") then
        local filename = directory .. "/avatars/" .. person.avatarHash .. ".png"
        if lfs.attributes(filename, "mode") == "file" then avatar = filename end
    end
    local state = companion.launch_pending and "running" or progress.state or "idle"
    local labels = { idle = T("profile_idle"), running = T("profile_running"), completed = T("profile_completed"), failed = T("profile_failed"), paused = T("profile_paused"), pausing = T("profile_pausing") }
    local detail = stages[progress.stage] or (state == "running" and T("profile_connecting") or "")
    if state == "completed" then
        if progress.profileOnly then detail = T("profile_updated")
        else detail = string.format(T("profile_counts"), tonumber(progress.received) or 0, tonumber(progress.files) or 0) end
    elseif state == "failed" then detail = T("profile_retry") end
    if state == "running" and tonumber(progress.total) and progress.total > 0 then
        detail = detail .. string.format(" · %d/%d", tonumber(progress.done) or 0, progress.total)
    end
    local synced = tonumber(progress.completedAt) or (G_reader_settings and tonumber(G_reader_settings:readSetting("kindlespouse_last_sync")))
    return { paired = config ~= nil, name = type(person.displayName) == "string" and person.displayName or T("profile_name_missing"),
        initials = type(person.avatar) == "string" and person.avatar or "K", avatar = avatar,
        device = config and config.name or "Kindle", clouds = type(person.clouds) == "table" and person.clouds or nil,
        reading = type(person.reading) == "table" and type(person.reading.days) == "table" and person.reading or nil,
        state = state, status = labels[state] or T("profile_waiting"), detail = detail, route = route,
        profile_received = receipt and receipt.receivedAt or nil,
        last_sync = synced and os.date("%Y-%m-%d %H:%M", synced) or nil }
end

function Profile.duration(seconds)
    local minutes = math.floor((tonumber(seconds) or 0) / 60)
    if minutes == 0 then return (tonumber(seconds) or 0) > 0 and T("duration_under_minute") or T("duration_zero") end
    if minutes < 60 then return minutes .. T("duration_minute_suffix") end
    return math.floor(minutes / 60) .. T("duration_hour_suffix") .. (minutes % 60 > 0 and " " .. minutes % 60 .. T("duration_minute_suffix") or "")
end

function Calendar:init()
    local TextWidget = require("ui/widget/textwidget")
    local function label(value, size)
        return TextWidget:new { text = value, face = Font:getFace(require("library").fonts.ui, size) }
    end
    self.labels, self.cells = {}, {}
    self.left, self.top = Screen:scaleBySize(20), Screen:scaleBySize(20)
    self.step = math.floor((self.width - self.left) / 52)
    self.cell = math.max(2, self.step - Screen:scaleBySize(2))
    self.dimen = Geom:new { w = self.width, h = self.top + self.step * 7 + Screen:scaleBySize(28) }
    local year, month, day = tostring(self.reading.asOf):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    local today = year and os.time { year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 }
    today = today or os.time()
    local ending = today + ((7 - tonumber(os.date("%w", today))) % 7) * 86400
    local seconds = {}
    for _, entry in ipairs(self.reading.days) do seconds[entry.date] = tonumber(entry.seconds) or 0 end
    local previous_month
    for index = 1, 364 do
        local epoch = ending - (364 - index) * 86400
        local date, current_month = os.date("%Y-%m-%d", epoch), os.date("%m", epoch)
        local value = seconds[date] or 0
        self.cells[index] = { date = date, seconds = value, future = epoch > today,
            level = value >= 3600 and 4 or value >= 1800 and 3 or value >= 900 and 2 or value > 0 and 1 or 0 }
        if (index - 1) % 7 == 0 and current_month ~= previous_month then
            if index > 1 or tonumber(os.date("%d", epoch)) <= 7 then
                self.labels[#self.labels + 1] = { widget = label(tonumber(current_month) .. T("calendar_month_suffix"), 8), x = self.left + math.floor((index - 1) / 7) * self.step, y = 0 }
            end
            previous_month = current_month
        end
    end
    for _, entry in ipairs({ { T("calendar_monday"), 0 }, { T("calendar_wednesday"), 2 }, { T("calendar_sunday"), 6 } }) do
        self.labels[#self.labels + 1] = { widget = label(entry[1], 8), x = 0, y = self.top + entry[2] * self.step }
    end
    self.labels[#self.labels + 1] = { widget = label(T("calendar_less"), 8), x = self.width - Screen:scaleBySize(98), y = self.top + self.step * 7 + Screen:scaleBySize(8) }
    self.labels[#self.labels + 1] = { widget = label(T("calendar_more"), 8), x = self.width - Screen:scaleBySize(12), y = self.top + self.step * 7 + Screen:scaleBySize(8) }
    self.ges_events = { Day = { require("ui/gesturerange"):new { ges = "tap", range = self.dimen } } }
end

function Calendar:paintTo(bb, x, y)
    local BB = require("ffi/blitbuffer")
    self.dimen.x, self.dimen.y = x, y
    self.colors = self.colors or { BB.Color8(245), BB.Color8(195), BB.Color8(145), BB.Color8(85), BB.Color8(25) }
    for index, cell in ipairs(self.cells) do
        local cx = x + self.left + math.floor((index - 1) / 7) * self.step
        local cy = y + self.top + (index - 1) % 7 * self.step
        if not cell.future then
            bb:paintRect(cx, cy, self.cell, self.cell, self.colors[cell.level + 1])
            bb:paintBorder(cx, cy, self.cell, self.cell, 1, BB.COLOR_GRAY)
            if self.selected == index then bb:paintBorder(cx - 2, cy - 2, self.cell + 4, self.cell + 4, 2, BB.COLOR_BLACK) end
        end
    end
    for _, entry in ipairs(self.labels) do entry.widget:paintTo(bb, x + entry.x, y + entry.y) end
    for level = 0, 4 do
        bb:paintRect(x + self.width - Screen:scaleBySize(80) + level * Screen:scaleBySize(13),
            y + self.top + self.step * 7 + Screen:scaleBySize(8), Screen:scaleBySize(10), Screen:scaleBySize(10), self.colors[level + 1])
    end
end

function Calendar:onDay(_, gesture)
    local x, y = gesture.pos.x - self.dimen.x - self.left, gesture.pos.y - self.dimen.y - self.top
    if x < 0 or y < 0 or x >= self.step * 52 or y >= self.step * 7 then return true end
    local index = math.floor(x / self.step) * 7 + math.floor(y / self.step) + 1
    local cell = self.cells[index]
    if cell and not cell.future then
        self.selected = index
        self.detail = require("ui/widget/infomessage"):new { text = cell.date .. T("calendar_reading_prefix") .. Profile.duration(cell.seconds), face = Font:getFace(require("library").fonts.ui, 20) }
        UIManager:setDirty(self.owner, "ui")
        UIManager:show(self.detail)
    end
    return true
end

function Calendar:free()
    for _, entry in ipairs(self.labels) do entry.widget:free() end
end

function Profile.avatar(data, size)
    if data.avatar then return require("ui/widget/imagewidget"):new { file = data.avatar, width = size, height = size } end
    return require("ui/widget/container/framecontainer"):new { padding = 0, margin = 0, bordersize = 1, radius = math.floor(size / 2),
        require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = size - 2, h = size - 2 },
            require("ui/widget/textwidget"):new { text = data.initials, face = Font:getFace(require("library").fonts.ui, size > Screen:scaleBySize(40) and 28 or 9) } } }
end

function Profile.button(companion, height)
    local button = InputContainer:new { dimen = Geom:new { w = height, h = height },
        require("ui/widget/container/centercontainer"):new { dimen = Geom:new { w = height, h = height },
            Profile.avatar(Profile.snapshot(companion), height - Screen:scaleBySize(4)) } }
    button.callback = function() return Profile.open(companion) end
    button.ges_events = { Profile = { require("ui/gesturerange"):new { ges = "tap", range = button.dimen } } }
    button.onProfile = function() button.callback(); return true end
    return button
end

function Panel:render(data)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalSpan = require("ui/widget/verticalspan")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local width, pad = Screen:getWidth(), Screen:scaleBySize(24)
    local offset = self.scroll and self.scroll:getScrolledOffset() or nil
    if self[1] then self[1]:free() end
    self.data = data
    local title = require("ui/widget/titlebar"):new { title = T("profile_title"), fullscreen = true, width = width,
        title_face = Font:getFace(require("library").fonts.title, 17), left_icon = "chevron.left", right_icon = "close",
        left_icon_tap_callback = function() UIManager:close(self) end, right_icon_tap_callback = function() UIManager:close(self) end }
    local content = VerticalGroup:new { align = "left" }
    local function text(value, size, bold, literary)
        content[#content + 1] = TextBoxWidget:new { text = value, width = width - pad * 2,
            face = Font:getFace(require("library").fonts[literary and "title" or "ui"], size), bold = bold or false }
        content[#content + 1] = VerticalSpan:new { width = Screen:scaleBySize(10) }
    end
    content[#content + 1] = VerticalSpan:new { width = Screen:scaleBySize(16) }
    content[#content + 1] = require("ui/widget/horizontalgroup"):new { align = "center",
        Profile.avatar(data, Screen:scaleBySize(52)),
        require("ui/widget/horizontalspan"):new { width = Screen:scaleBySize(14) },
        VerticalGroup:new { align = "left",
            TextBoxWidget:new { text = data.name, width = width - pad * 2 - Screen:scaleBySize(66), face = Font:getFace(require("library").fonts.title, 19) },
            VerticalSpan:new { width = Screen:scaleBySize(5) },
            TextBoxWidget:new { text = T("brand_kindlespouse_prefix") .. (data.paired and (tostring(data.device) .. T("paired_suffix")) or T("not_paired")),
                width = width - pad * 2 - Screen:scaleBySize(66), face = Font:getFace(require("library").fonts.ui, 10) } } }
    content[#content + 1] = VerticalSpan:new { width = Screen:scaleBySize(22) }
    if data.reading then
        local reading = data.reading
        local metrics = require("ui/widget/horizontalgroup"):new { align = "top" }
        local current = reading.asOf == os.date("!%Y-%m-%d", os.time() + 28800)
        self.metrics = { { T("reading_today"), current and Profile.duration(reading.todaySeconds) or T("reading_pending") },
            { T("reading_total"), Profile.duration(reading.totalSeconds) }, { T("reading_books"), tostring(reading.bookCount or 0) .. T("reading_books_suffix") },
            { T("reading_days"), tostring(reading.readingDays or 0) .. T("reading_days_suffix") } }
        for _, metric in ipairs(self.metrics) do
            local column = VerticalGroup:new { align = "left" }
            column[1] = TextBoxWidget:new { text = metric[1], width = math.floor((width - pad * 2) / 4), face = Font:getFace(require("library").fonts.ui, 10) }
            column[2] = VerticalSpan:new { width = Screen:scaleBySize(8) }
            column[3] = TextBoxWidget:new { text = metric[2], width = math.floor((width - pad * 2) / 4), face = Font:getFace(require("library").fonts.title, 13) }
            metrics[#metrics + 1] = column
        end
        content[#content + 1] = metrics
        content[#content + 1] = VerticalSpan:new { width = Screen:scaleBySize(22) }
        text(T("reading_calendar"), 14, false, true)
        text(T("reading_calendar_period"), 10)
        self.calendar = Calendar:new { width = width - pad * 2, reading = reading, owner = self }
        content[#content + 1] = self.calendar
        text(T("reading_calendar_hint") .. tostring(reading.asOf), 9)
        text(reading.readingDays == 0 and T("reading_empty") or T("reading_source"), 9)
    else
        self.metrics, self.calendar = nil, nil
        text(T("reading_stats_pending"), 14, false, true)
        text(T("reading_stats_hint"), 11)
    end
    content[#content + 1] = VerticalSpan:new { width = Screen:scaleBySize(8) }
    text(T("profile_sync_section"), 14, false, true)
    text(data.status, 12)
    if data.detail ~= "" then text(data.detail, 11) end
    if data.last_sync then text(T("profile_last_sync_prefix") .. data.last_sync, 10) end
    if data.profile_received then
        text(T("profile_updated_prefix") .. tostring(data.profile_received):gsub("T", " "):gsub("%.%d+Z$", " UTC"):gsub("Z$", " UTC") .. " · " .. data.route, 10)
    end
    text(T("profile_clouds"), 14, false, true)
    if data.clouds == nil then text(T("profile_clouds_pending"), 11)
    elseif #data.clouds == 0 then text(T("profile_clouds_empty"), 11)
    else
        for _, cloud in ipairs(data.clouds) do
            local provider = cloud.provider == "drive" and T("brand_drive") or cloud.provider == "onedrive" and "OneDrive" or T("profile_cloud")
            text(provider .. " · " .. tostring(cloud.name or ""), 12, true)
            text(cloud.connected and T("profile_desktop_connected") or T("profile_desktop_reconnect"), 10)
        end
        text(T("profile_clouds_hint"), 10)
    end
    if not data.paired then text(T("profile_pair_hint"), 11) end
    local busy = data.state == "running" or data.state == "pausing"
    local buttons = {
        { id = "profile", text = T("profile_sync_action"), enabled = data.paired and not busy, callback = function() self.companion:syncProfile(); self:refreshNow() end },
        { id = "sync", text = data.state == "paused" and T("sync_resume") or T("sync_now"), enabled = data.paired and not busy,
            callback = function() self.companion:sync(false); self:refreshNow() end },
        { id = "pause", text = T("pause"), enabled = data.paired and data.state == "running", callback = function() self.companion:pause(); self:refreshNow() end },
    }
    for _, button in ipairs(buttons) do button.font_size = 12; button.font_face = require("library").fonts.ui; button.font_bold = false end
    self.actions = require("ui/widget/buttontable"):new { width = width, buttons = { buttons } }
    self.scroll = require("ui/widget/container/scrollablecontainer"):new { swipe_full_view = false,
        dimen = Geom:new { w = width, h = Screen:getHeight() - title:getHeight() - self.actions:getSize().h },
        FrameContainer:new { padding = 0, padding_left = pad, padding_right = pad, bordersize = 0, content } }
    if offset then self.scroll:setScrolledOffset(offset) end
    self[1] = FrameContainer:new { padding = 0, margin = 0, bordersize = 0,
        width = width, height = Screen:getHeight(), background = require("ffi/blitbuffer").COLOR_WHITE,
        VerticalGroup:new { align = "left", title, self.scroll, self.actions } }
    self.signature = json.encode(data)
end

function Panel:refreshNow()
    if self.closed then return end
    local data = Profile.snapshot(self.companion)
    if json.encode(data) ~= self.signature then self:render(data); UIManager:setDirty(self, "ui") end
end

function Panel:onCloseWidget()
    if self.closed then return end
    self.closed = true
    UIManager:unschedule(self.refresh_task)
    if self.companion.profile_panel == self then self.companion.profile_panel = nil end
    if self.companion.ui and self.companion.ui.file_chooser then
        self.companion.ui:reinit(self.companion.ui.file_chooser.path)
        UIManager:setDirty(self.companion.ui, "ui")
    end
    if self[1] then self[1]:free(); self[1] = nil end
end

function Profile.open(companion)
    if companion.profile_panel and not companion.profile_panel.closed then return companion.profile_panel end
    local panel = Panel:new { companion = companion, dimen = Screen:getSize() }
    panel:render(Profile.snapshot(companion))
    panel.refresh_task = function()
        if panel.closed then return end
        panel:refreshNow()
        UIManager:scheduleIn(3, panel.refresh_task)
    end
    companion.profile_panel = panel
    UIManager:show(panel)
    UIManager:scheduleIn(3, panel.refresh_task)
    return panel
end

return Profile
