# Reader UI contract

The base is c1d9e9e85081cf7854da2a0cda2d006f4110e177. The implementation uses the v2026.07.1 reader APIs without core changes.

`require("reader/highlight_bar")` provides `install(ui)`, `uninstall(ui)` and `settings()`. Installation is idempotent and applies only to this ReaderUI instance. Missing upstream selection APIs leave the stock menu active. Closing or resizing the reader removes the compact popup. Closing the reader restores its instance methods.

`settings()` saves `kindlespouse_reader = { schema = 1, highlight_bar = true, reader_bar = true }`. A legacy boolean controls both fields. Existing field values and additional fields survive migration. Each feature can be disabled independently.

The highlight toolbar handles new selections only. Existing-annotation menus remain upstream. It reads `Device.screen:isColorScreen()` rather than color rendering preferences. A monochrome screen gets one `Highlight` action through upstream gettext (`高亮` in Chinese); it leaves the selection's color unchanged. Color screens get four color choices, each setting only the selected annotation's `color`. Both paths call `saveHighlight()` once and clear the selection.

Neither path changes `selected_text.drawer`, document highlight defaults or global preferences. Upstream uses the selection's drawer when present. Otherwise, it uses `view.highlight.saved_drawer`. Supported styles include Lighten (`lighten`), Underline (`underscore`), Strikethrough (`strikeout`) and Invert (`invert`). The action definition returns the actual upstream annotation index. KOReader's rendered button wrapper discards callback return values.

KOReader v2026.07.1 supports purple, not pink. Color screens offer Yellow, Blue, Purple and Orange. Labels and saved values agree. Note, Copy and Dictionary use current upstream button builders, including their enabled conditions. More invokes the captured original menu without clearing the selection or altering third-party builders. Tapping outside uses the normal selection-clear lifecycle. Stale save and More callbacks check selection identity before closing a dialog, so they cannot save twice or close a newer selection's toolbar.

Translation keys passed to `require("i18n").T(key, ...)`:

- `reader.highlight.yellow`: English `Yellow`; Chinese `黄色`.
- `reader.highlight.blue`: English `Blue`; Chinese `蓝色`.
- `reader.highlight.purple`: English `Purple`; Chinese `紫色`.
- `reader.highlight.orange`: English `Orange`; Chinese `橙色`.
- `reader.highlight.note`: English `Note`; Chinese `笔记`.
- `reader.highlight.copy`: English `Copy`; Chinese `复制`.
- `reader.highlight.dictionary`: English `Dictionary`; Chinese `词典`.
- `reader.more`: English `More`; Chinese `更多`.

Run `python3 kindlespouse/test_reader.py --runtime /path/to/koreader --fonts /path/to/reader-fonts --feature highlight`. It creates a generated multi-page EPUB and isolated KO_HOME. The default `--screen monochrome` uses KOReader's `EMULATE_BW_SCREEN=1` capability; `--screen color` uses the SDL color screen while keeping `color_rendering=false`, proving the toolbar follows hardware capability. Both profiles verify every available action with all four upstream drawer styles, selection-specific overrides, unchanged defaults, and persisted annotation colors and drawers. They also check selection-preserving More, third-party actions, stale callbacks against new selections, outside dismissal, resizing, settings migration and method restoration. Screenshots and logs remain in the printed synthetic fixture directory. The test preloads a translation fallback only when the application translation module is absent.

Device pen input, PDF selection geometry and physical e-ink refresh still need hardware or separate fixture verification.
`require("reader/reader_bar")` provides independent `install(ui)` and `uninstall(ui)` methods. `require("reader/init")` applies both feature settings and removes disabled features. Do not require plain `reader`, which would resolve to KOReader's entry point.

The reader bar replaces only `ReaderMenu:onTapShowMenu`. Swipe-only menu activation still calls upstream. Keyboard menus and menu swipes stay unchanged. More calls the captured original tap handler, preserving the full stock menu and any existing wrapper. Library, contents, bookmarks, search and Aa call `ReaderUI:onHome`, `ReaderToc:onShowToc`, `ReaderBookmark:onShowBookmark`, `ReaderSearch:onShowFulltextSearchInput` and `ReaderConfig:onShowConfigMenu`. Missing action methods disable that button.

The progress bar reads the active rolling or paging module. Taps and releases call `onGotoPercent` with a 0–100 value; pan previews do not navigate. Remaining time uses numeric `statistics.avg_time` only when `statistics.settings.is_enabled` is true. Missing, negative, infinite or NaN averages suppress the estimate. The bar never parses `getTimeForPages`, which returns a locale-dependent presentation string. Remaining seconds round to the nearest whole minute, with 30 seconds rounding upward; 60 minutes displays as one hour and zero minutes.

While the controls are open, the bar renders the complete current `ReaderView` into a temporary buffer and uniformly scales it to fit between the panels. The body is cleared before composition, so the original unscaled text cannot show through the side gutters. Every rendered page pixel, annotation and original footer remains inside the body region. Text is intentionally slightly smaller while controls are open. EPUB pagination and PDF zoom, crop and scroll state remain unchanged. The adapter does not change document dimensions, margins, reading location, footer visibility or user settings. It guards recursive rendering and frees temporary buffers after each paint, including document-render and scaling failures.

The bottom edge of the top panel and top edge of the bottom panel each have one black physical-pixel separator, independent of DPI. The title removes only a trailing `· 阅读` marker. Extra whitespace around that marker is allowed. Other occurrences remain, including `文学·阅读` without a space after the dot. Dismissal, actions, reader destruction, uninstall and dimension changes close the bar and request a full viewport repaint. Rotation closes the bar. Its next opening uses the new screen dimensions.

Additional translation keys:

- `reader.library`: English `← Library`; Chinese `← 书库`.
- `reader.contents`: English `Contents`; Chinese `目录`.
- `reader.bookmarks`: English `Bookmarks`; Chinese `书签`.
- `reader.search`: English `Search`; Chinese `搜索`.
- `reader.appearance`: English and Chinese `Aa`.
- `reader.book`: English `Book`; Chinese `图书`.
- `reader.progress`: English and Chinese `%1 / %2 · %3%`; arguments are current page, total pages and integer percent.
- `reader.remaining.minutes`: English `about %1 min`; Chinese `约 %1 分钟`.
- `reader.remaining.hours`: English `about %1 h %2 min`; Chinese `约 %1 小时 %2 分`.

Use `--feature all` for both features or `--feature reader` for the bar alone. `--statistics` enables the actual statistics plugin in the synthetic profile. Add `--document pdf --feature reader` to generate a 12-page PDF with text extending to both ends of each page. Tests invoke real upstream action hooks, move through the generated document using tap and pan release, verify independent settings, and verify lifecycle restoration. Reader tests compare every framebuffer pixel against the independently rendered full viewport, verify blank side gutters and exactly one separator row, and compare every restored pixel with the original rendering. English and Chinese estimates exercise rounding boundaries, disabled statistics, invalid averages and an intentionally unusable formatted-duration method. Both languages have new unobscured-body screenshots. The parent integration must call the adapter after ReaderReady and expose its two settings separately.
