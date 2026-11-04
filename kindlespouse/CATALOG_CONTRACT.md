# Catalog integration contract

All APIs use dot calls. Catalog and Extractor are process singletons. Book files remain unchanged.

## Catalog

- `ensure(root, on_done)` selects the root and schedules its first scan. Each process also schedules one incremental scan on the first ensure of a persisted complete root. This startup marker exists only in memory. Further ensures, filters and reader returns reuse the root without enumeration. Unfinished metadata resumes independently.
- `rescan(root, on_done)` explicitly enumerates again. It updates changed files and removes missing files. Both scan methods return the root state. Their callbacks receive that state after enumeration, before metadata necessarily finishes. Concurrent calls join the existing scan.
- `root` and `entries` expose the current root and its path-to-record map. `records(root)` returns a path-sorted array, defaulting to the current root. `items(chooser)` builds native FileChooser items with `getListItem` and a `kindlespouse` record. These reads never enumerate directories or stat books.
- `touch(path)` refreshes one book and its reading state. `add(path)` adds a supported visible file to matching known roots. `remove(path)` removes its cache record. None enumerates directories.
- `attachBookInfo(ui.bookinfo)` enables sidecar metadata fallback with `no_open_document=true`. Engine extraction runs only in subprocesses.
- `subscribe(owner, callback)` replaces an observer. `unsubscribe(owner)` removes it. Callbacks receive `(event, root)`. Events contain `kind`, `root`, `scanning`, `count`, and `done`. Kinds are `scan`, `metadata`, `touch`, `add`, and `remove`. Scan completion sets `done=true`. Metadata events can arrive later.
- `cancel(root)` closes its directory iterator and cancels metadata subscriptions. It leaves active extraction running. An interrupted scan becomes incomplete. `flush()` persists the cache immediately.

Records contain `path`, `name`, `format`, `source`, `size`, `mtime`, `modified`, `added`, `title`, `author`, `meta_ready`, `status`, `progress`, and `recent`. `modified` aliases `mtime`. `meta_ready` means extraction has settled, including unsupported files. `meta_error` records failures. Raw records use an empty missing author; native items use the existing Chinese placeholder.

Schema 2 reuses `settings/kindlespouse-library.lua` and preserves legacy titles, authors, and added timestamps. Scans process at most 50 directory entries per positive-delay UI task. Hidden directories, `.sdr` directories, and links are excluded. UI observers can throttle list updates and ignore roots they no longer display.

## Extractor

- `enqueue(owner, files, callback)` accepts `{ filepath, cover_specs }` records. Callbacks receive `(filepath, cached_info, status)` per file. Status is `ready`, `unsupported`, `failed`, or `missing`.
- `cancel(owner)` removes only that owner's subscriptions. `isBusy()` reports this queue's work. `cached(path)` reads metadata without decoding a cover buffer.
- `isFresh(info, attr)` compares numeric file size and mtime. `needs(info, attr, specs)` also checks extraction and cover flags. `poll()` runs a queue pass; normal callers do not need it.

Pending requests merge owners and maximum cover dimensions by path. Upgrades during extraction queue a follow-up. Batches contain at most 50 files, with at most three startup or interruption attempts. Fresh metadata does not re-extract existing covers. Re-extraction preserves ignore preferences, even after all subscribers cancel.

The queue waits for any existing BookInfoManager process. It records PIDs after its own successful launch from an idle manager and collects completed processes through the manager. Catalog and Shelf use this queue instead of directly calling `extractInBackground` or `terminateBackgroundJobs`. Shelf close cancels its owner subscription.

## Shelf updates and verification

Keep the Shelf widget when its list changes. Save its scroll offset, free Content cards, replace FileChooser and Shelf items, update Content height, call `reset()`, restore the clamped offset, and dirty the shelf rectangle. Cover-only updates release cards and dirty that rectangle.

Run `python3 kindlespouse/test_catalog.py --runtime /path/to/pinned/koreader`. Generated fixtures check 500 books in three directory levels, input polling between chunks, migration, hot reads, incremental updates, real extraction, process ownership, startup retry, cancellation, cover retention, and persisted restart behavior.

The virtual shelf constructs the FileChooser item shape from catalog records, rather than invoking getListItem: the upstream collection marker performs a realpath lookup per book, and some native collates open documents. Canonical root resolution happens once during enumeration. Collection membership and hot reading flags use cached tables. Actual reader return performs zero book-directory scans; the unchanged upstream saveSettings does one custom-cover lookup within the current .sdr, reported separately.
