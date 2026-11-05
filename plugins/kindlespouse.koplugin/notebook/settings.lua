local Settings = {}

Settings.settings = require("reader/settings")

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
