# Local services contract

All APIs use dot calls. These modules do not enable Wi-Fi or launch workers.

`i18n.T(key, ...)` selects Chinese when the current language starts with `zh`, otherwise English. It supports numbered reader placeholders and printf formats. `i18n.keys` maps existing human strings to semantic keys, and `en` and `zh` expose the dictionaries. Callers translate visible text, preserving internal `Library`, `Notebook`, stage, setting, and mode tokens. Reader translation keys match `READER_CONTRACT.md`.

`sync_status.configure { directory, now, proc_directory, logger }` changes local dependencies. Defaults use `/mnt/us/kindlespouse/`, epoch seconds, and `/proc/`. `readJSON(name, limit)` reads at most 64 KiB by default and logs an unreadable existing file once per path. The optional bound cannot exceed 1 MiB.

`workerRunning()` checks only `sync.lock` and the matching process command line. `isRunning()` also accepts a `sync.launching` marker younger than 20 seconds. Marker JSON uses `{ schema=1, owner, startedAt, mode }`; plain epoch markers and mtime fallback are supported. `launchMarker()` returns a fresh marker, and `paused(mode)` reads the existing mode pause file.

`snapshot()` normalizes worker state, counters, timestamps, mode flags, and errors. Its `launching=true` represents the marker before a real worker appears. Scheduler adapters must not count this synthetic running state as observed worker progress. Use `workerRunning()` as the scheduler's running dependency, and map `progress.launching` to an idle observation when adapting progress.

Terminal snapshots attach the exact ISO `last-result.completedAt` as `runId` only when terminal state, completion second, and mode agree. A launch marker never inherits a previous result ID. Different ISO fractions distinguish same-second completed runs. A result without progress has no invented start timestamp. `summary(snapshot)` translates the normalized state and progress.

`menu.build(host)` returns the KindleSpouse menu descriptor. Its callbacks delegate to host methods: `sync(false)`, `pause()`, `showStatus()`, `refreshLibrary()`, `toggleHome()`, `setSleepCover(enabled)`, `setAutoSyncEnabled(enabled)`, `setAutoReceiveEnabled(enabled)`, `syncProfile()`, `receiveBooks(false)`, `collectTitles()`, `syncTitles()`, and `applyAnnotations()`. The profile action uses `openProfile()` or lazily opens the existing profile module. Automatic-setting setters own settings persistence and scheduler notifications. `readerMenuItems()` optionally supplies the Reading experience submenu.

`menu.showStatus(host)` creates a native InfoMessage and one stable three-second callback for that host. A changed message closes the old widget and creates a replacement. `closeStatus(host)` cancels the callback and closes the owned widget. Native dismissal and suspension also cancel it. `host.status_dialog` remains available for compatibility. Teardown must call `closeStatus`.

Run `python3 kindlespouse/test_plugin.py --runtime /path/to/pinned/koreader --test services`. The test uses generated local files, an isolated process-directory fixture, and actual KOReader widgets. It checks both locales, bounded reads, launch expiry, pause state, result identity, delegated callbacks, dialog replacement, and timer cleanup.

`launcher` returns translated semantic-key messages as its second return value on failure, including pause writes. Both English and Chinese cover mode validation, running/reserved launches, marker I/O and ownership, resume/pause failures, lost/expired reservations, pairing, reading-state saving and worker startup. Raw filesystem and process diagnostics appear only in logger warnings prefixed `KindleSpouse:`. Callers can continue passing returned failure text directly to notification APIs.
