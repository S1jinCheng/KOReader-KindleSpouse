local Highlight = require("reader/highlight_bar")
local ReaderBar = require("reader/reader_bar")
local Reader = {}

function Reader.install(ui)
    local settings = Highlight.settings()
    if settings.highlight_bar == false then Highlight.uninstall(ui) else Highlight.install(ui) end
    if settings.reader_bar == false then ReaderBar.uninstall(ui) else ReaderBar.install(ui) end
end

function Reader.uninstall(ui)
    Highlight.uninstall(ui)
    ReaderBar.uninstall(ui)
end

return Reader