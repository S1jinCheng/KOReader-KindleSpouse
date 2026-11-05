local Settings = {}

function Settings.settings()
    local previous = G_reader_settings:readSetting("kindlespouse_reader")
    if type(previous) == "table" and previous.schema == 1
        and type(previous.highlight_bar) == "boolean" and type(previous.reader_bar) == "boolean"
        and type(previous.notebook_summary) == "boolean" then return previous end
    local settings = { schema = 1, highlight_bar = previous ~= false, reader_bar = previous ~= false, notebook_summary = true }
    if type(previous) == "table" then
        for key, value in pairs(previous) do settings[key] = value end
        settings.schema = 1
        settings.highlight_bar = previous.highlight_bar ~= false
        settings.reader_bar = previous.reader_bar ~= false
        settings.notebook_summary = previous.notebook_summary ~= false
    end
    G_reader_settings:saveSetting("kindlespouse_reader", settings)
    return settings
end

function Settings.enabled()
    return Settings.settings().notebook_summary
end

function Settings.setEnabled(enabled)
    local settings = Settings.settings()
    settings.notebook_summary = enabled == true
    G_reader_settings:saveSetting("kindlespouse_reader", settings)
    return settings.notebook_summary
end

function Settings.toggle(companion)
    local enabled = Settings.setEnabled(not Settings.enabled())
    local ui = companion and companion.ui
    if ui and ui.kindlespouse_patched then require("home").clearCachedNotebook(ui, companion) end
    return enabled
end

return Settings
