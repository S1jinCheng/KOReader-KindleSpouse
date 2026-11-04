# Reader UI contract

The base is c1d9e9e85081cf7854da2a0cda2d006f4110e177. The implementation uses the v2026.07.1 reader APIs without core changes.

`require("reader/highlight_bar")` provides `install(ui)`, `uninstall(ui)` and `settings()`. Installation is idempotent and applies only to this ReaderUI instance. Missing upstream selection APIs leave the stock menu active. Closing or resizing the reader removes the compact popup. Closing the reader restores its instance methods.

`settings()` saves `kindlespouse_reader = { schema = 1, highlight_bar = true, reader_bar = true }`. A legacy boolean controls both fields. Existing field values and additional fields survive migration. Each feature can be disabled independently.

The highlight toolbar handles new selections only. Existing-annotation menus remain upstream. Color buttons set the selected annotation's `color` and `drawer = "lighten"`, call `saveHighlight()` once, then clear the selection. They do not change default highlight preferences. The returned index is the actual upstream annotation index.

KOReader v2026.07.1 supports purple, not pink. The four actions are therefore Yellow, Blue, Purple and Orange. Labels and saved values agree. Note, Copy and Dictionary use current upstream button builders, including their enabled conditions. More invokes the captured original menu without clearing the selection or altering third-party builders. Tapping outside uses the normal selection-clear lifecycle.

Translation keys passed to `require("i18n").T(key, ...)`:

- `reader.highlight.yellow`: English `Yellow`; Chinese `黄色`.
- `reader.highlight.blue`: English `Blue`; Chinese `蓝色`.
- `reader.highlight.purple`: English `Purple`; Chinese `紫色`.
- `reader.highlight.orange`: English `Orange`; Chinese `橙色`.
- `reader.highlight.note`: English `Note`; Chinese `笔记`.
- `reader.highlight.copy`: English `Copy`; Chinese `复制`.
- `reader.highlight.dictionary`: English `Dictionary`; Chinese `词典`.
- `reader.more`: English `More`; Chinese `更多`.

Run `python3 kindlespouse/test_reader.py --runtime /path/to/koreader --fonts /path/to/reader-fonts --feature highlight`. It creates a generated multi-page EPUB and isolated KO_HOME, checks real color annotations and their persisted settings, selection-preserving More, third-party actions, settings migration and method restoration. Screenshots and logs remain in the printed synthetic fixture directory. The test preloads a translation fallback only when the application translation module is absent.

Device pen input, PDF selection geometry and physical e-ink refresh still need hardware or separate fixture verification.
`require("reader/reader_bar")` provides independent `install(ui)` and `uninstall(ui)` methods. `require("reader/init")` applies both feature settings and removes disabled features. Do not require plain `reader`, which would resolve to KOReader's entry point.

The reader bar replaces only `ReaderMenu:onTapShowMenu`. Swipe-only menu activation still calls upstream. Keyboard menus and menu swipes stay unchanged. More calls the captured original tap handler, preserving the full stock menu and any existing wrapper. Library, contents, bookmarks, search and Aa call `ReaderUI:onHome`, `ReaderToc:onShowToc`, `ReaderBookmark:onShowBookmark`, `ReaderSearch:onShowFulltextSearchInput` and `ReaderConfig:onShowConfigMenu`. Missing action methods disable that button.

The progress bar reads the active rolling or paging module. Taps and releases call `onGotoPercent` with a 0–100 value; pan previews do not navigate. Remaining time appears only through an available statistics module's `getTimeForPages`. The overlay paints and refreshes its top and bottom rectangles, dismisses on an outside tap and closes on reader destruction or dimension changes.

Additional translation keys:

- `reader.library`: English `← Library`; Chinese `← 书库`.
- `reader.contents`: English `Contents`; Chinese `目录`.
- `reader.bookmarks`: English `Bookmarks`; Chinese `书签`.
- `reader.search`: English `Search`; Chinese `搜索`.
- `reader.appearance`: English and Chinese `Aa`.
- `reader.book`: English `Book`; Chinese `图书`.
- `reader.progress`: English and Chinese `%1 / %2 · %3%`; arguments are current page, total pages and integer percent.
- `reader.remaining`: English `%1 left`; Chinese `剩余 %1`; the argument is the statistics module's formatted duration.

Use `--feature all` for both features or `--feature reader` for the bar alone. `--statistics` enables the actual statistics plugin in the synthetic profile. Tests invoke real upstream action hooks, move through the generated document using tap and pan release, verify independent settings, and verify lifecycle restoration. The parent integration must call the adapter after ReaderReady and expose its two settings separately.