# Notes and highlights summary

This module lists KOReader annotations. It does not read, convert or write Amazon NBK notebooks.

`require("notebook/index").new({ catalog = Catalog })` creates an index. The catalog defaults to `require("catalog")`; it must provide `records(root?)`, returning raw records with `path`, `title` or `name`, `author`, `recent` and `status`. Records with `status == "new"` are skipped before sidecar lookup, stat or open. The index never asks the catalog to scan and never opens a document engine.

`index:refresh(callback, root?)` processes at most 50 records per scheduled batch, with a positive 0.01 second delay. The callback receives `(books, complete)`. `index:cancel()` stops future batches and detaches the callback. `index:search(query, path?)` returns matching books, or position-sorted annotations for one book. Queries match title, author, quote and note text as appropriate.

`Index.invalidate(path)` invalidates the shared cache for a book. `index:invalidatePath(path)` does the same for an injected private cache. Parent integration can call the module hook when a reader closes. The API-selected sidecar path, modification time, size and change time invalidate the cache automatically. The currently open book always uses in-memory annotations instead of the cache.

The index reads only the current primary `annotations` table, removes identical entries within it, excludes plain page bookmarks, and counts highlights and notes separately. An empty or missing primary produces no annotations. The live ReaderUI's in-memory primary is authoritative, including when empty. Engine-specific `annotations_rolling` and `annotations_paging` collections are not merged or used as recovery data. Upstream ReaderAnnotation manages those incompatible collections when the user switches rendering engines; the summary does not guess an engine or revive its saved alternate collection. A highlighted annotation with a note contributes to both counts. Books sort by catalog reading recency, then annotation update date. EPUB positions use natural xpointer ordering; PDF positions use numeric page ordering.

Sidecar lookup delegates to `DocSettings:findSidecarFile` and follows the configured preferred location. Reading uses `DocSettings.openSettingsFile`; it never calls the mutating `DocSettings:open` path or flushes metadata. A corrupt selected file produces an empty result and a log warning. The summary preserves that file and does not search backups or repair metadata. Unlike the Reader's full `DocSettings:open`, this read-only API chain does not select another location by modification time or recover from a corrupt preferred file. Opening the book in Reader owns those recovery decisions. Metadata files larger than 10 MiB are not loaded. Old pre-annotation bookmark/highlight formats require KOReader's own migration when the user opens that book.

`require("notebook/view").open(companion, height, { catalog = Catalog, root = root })` returns an embeddable panel without showing a global window. Options are optional. The panel exposes `refresh()`, `search(query)` and `onCloseWidget()`. Calling `search()` without an argument opens an input dialog. A nonempty query updates the list locally. Refresh reactivates a retained panel after closing or switching away; it preserves the current book and query.

The first list shows annotated books and counts. Selecting a book shows its annotations. The back button returns to books. Search covers quote and note excerpts. The secondary Kindle-notebooks button calls `Home.returnToKindle`; it does not replace Amazon's notebook editor. Parent integration owns the lazy Notebook-tab creation, retention across tab switches, header-search binding and invalidation hook. The view's close handler cancels its index and closes its search dialog.

`View.navigate(path, annotation)` reuses the current reader when possible. Otherwise it passes a fifth `after_open_callback` to `ReaderUI:showReader(path, nil, nil, nil, callback)`. That callback receives the new ReaderUI instance in v2026.07.1. It records the current location using `link:addCurrentLocationToStack()` before sending `GotoXPointer` or `GotoPage`. Invalid or incompatible locations show a message instead of guessing another location.

Translation keys for `require("i18n").T(key, ...)`:

- `notebook.summary`: English `Notes & highlights`; Chinese `笔记与标注`.
- `notebook.books`: English `← Books`; Chinese `← 图书`.
- `notebook.counts`: English `%1 highlights · %2 notes`; Chinese `%1 处标注 · %2 条笔记`.
- `notebook.page`: English `Page %1`; Chinese `第 %1 页`.
- `notebook.loading`: English `Reading annotations…`; Chinese `正在读取批注…`.
- `notebook.empty`: English `No matching notes or highlights`; Chinese `没有匹配的笔记或标注`.
- `notebook.search`: English `Search notes`; Chinese `搜索笔记`.
- `notebook.cancel`: English `Cancel`; Chinese `取消`.
- `notebook.refresh`: English `Refresh`; Chinese `刷新`.
- `notebook.native`: English `Kindle notebooks`; Chinese `Kindle 原生笔记`.
- `notebook.note`: English `Note: %1`; Chinese `笔记：%1`.
- `notebook.location_unavailable`: English `This annotation position is no longer available.`; Chinese `这条批注的位置已不可用。`.

Run `python3 kindlespouse/test_notebook_summary.py --runtime /path/to/koreader --fonts /path/to/reader-fonts`. It creates a real generated EPUB and real DocSettings fixtures under an isolated KO_HOME. The real UIManager processes 121 eligible records from 122 catalog entries in three batches. Tests cover alternate-slot deduplication, open-reader annotations, notes without highlights, exclusion of plain bookmarks, corrupted-sidecar preservation, configured-location API delegation, unopened-book I/O exclusion, cache and mtime invalidation, search, embedding, natural position sorting, callback cancellation and untouched synthetic NBK bytes. Document opens and book-folder enumeration are forbidden during indexing. Navigation checks call the actual current reader and spy on the supported cross-document callback boundary. Screenshots and logs remain in the printed fixture directory.

PDF engine selection and Kindle hardware remain outside this simulator fixture. Exact ordering across multiple text flows is approximated by natural xpointer order because the summary does not open documents to ask their rendering engines.
Parent integration uses registry wrappers for embedded panel render/refresh/search and Menu/InputDialog instance methods. Hidden panels cancel index work and restore menu wrappers; resume installs them again. Permanent disposal releases both panel and Home wrappers. Row previews retain full searchable text in the index while showing bounded UTF-8 excerpts, note, chapter and date within three lines. Native handwriting is a secondary bottom action.
