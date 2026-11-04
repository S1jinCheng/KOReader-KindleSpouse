return function()
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
