# Cached Home tabs

`Home.switchTab(ui, companion, tab)` swaps only `ui.kindlespouse_content[1]`. The shared header, navigation, outer frame, file chooser and shelf keep their identity. The library body stays `{header, toolbar, shelf}` so `Library.updateToolbar` continues to replace index 2. Notebook content is created on its first visit through `Home.notebook(companion, height)`.

Switching away from Library cancels the shelf's delayed cover request and extractor subscription, frees its visible cards and scratch buffer, and retains the shelf and its scroll offset. Switching back paints the same shelf and restarts only work needed by its visible cards. It does not close the shelf permanently.

A notebook body may provide `onCloseWidget()` to cancel hidden work and `refresh()` to resume it. A close handler should set `closed = true`; refresh should clear it. This prevents a second close when KOReader has already delivered CloseWidget to the visible body. The cached notebook keeps its search and navigation state between visits. `Home.notebook` remains the integration boundary for the later annotation-summary view.

The shared header belongs to Home. Cached body groups must not free it. Rotation rebuilds the layout, and disabling Home or closing FileManager disposes both bodies, the header and navigation, and removes catalog callbacks. Library refresh while Notebook is active must preserve the notebook title and search label. Home navigation switches to the cached Library body and refreshes its catalog snapshot.

Run from WSL Ubuntu with the real v2026.07.1 AppImage runtime:

```text
python3 kindlespouse/test_home.py --runtime /mnt/d/kindleBooming/KindleSpouse/native/tools/koreader/squashfs-root/usr/lib/koreader --fonts /mnt/d/kindleBooming/KindleSpouse/native/tools/reader-fonts
```

The eight-book simulator acceptance test covers 20 tab round trips with actual paints, unchanged chooser/shelf/header/frame/navigation, a retained nonzero shelf scroll offset, zero reinitializations and root directory scans, one lazy notebook construction, pause/resume, background Library refresh, cached Home navigation, rotation, disabling from Notebook, and actual FileManager window close. Existing filtering, sorting, font, native-menu and layout acceptance checks also run. Screenshots use only generated fixtures.
