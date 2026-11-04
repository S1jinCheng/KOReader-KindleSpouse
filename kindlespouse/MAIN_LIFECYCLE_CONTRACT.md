# Main lifecycle integration

The leaf change depends on `sleep_cover.lua`, `menu.lua`, `sync_status.lua` and `i18n.lua` from services revision `2e8b40546da6bb67b7523b6258dec400846fbd2f`, plus `version_guard.lua` from `f665e446378cd35d58e65545864f13a6f0be6843`. Worker-only baseline `b795480f` imports these files for testing; do not cherry-pick that baseline when the parent already has the helpers.

Synchronization configuration and `Scheduler.attach` run before guarded interface installation. Unsupported versions and immediate/deferred UI errors leave the scheduler attached. The ordinary synchronization menu is registered independently so users retain its controls.

Home loading/installation runs inside `Guard.install`. During that call only, PostInit registrations are wrapped with `Guard.run` and a closed-host check. The temporary registration wrapper is removed immediately afterward; other plugins' callbacks retain their original behavior. Parent Home layout/tab and catalog callbacks must also invoke `Guard.run`; this leaf intentionally does not modify Home.

`installReaderExperience` consults `package.loaded["reader/init"]` or `package.loaded["reader.init"]` and calls an already-loaded module's `install(host)` under the guard. It never requires a not-yet-delivered P3 module. Parent reader integration can replace this optional hook once that module is part of the stage.

Sleep profile, setting and preparation methods delegate to Sleep. User toggles call `Sleep.savePreference(enabled, { directory = host.directory })`: validate the preset, preserve existing fields, atomically publish the preference, then change screensaver settings and prepare. Write/rename/preset failures preserve the old profile and acknowledgment; incoming `applyProfile` never calls this persistence path. Menu construction/status dialogs delegate to Menu. Refresh delegates to `Catalog.rescan(Home.root(ui))`; it does not call `ui:reinit`. Auto-sync and auto-receive menu adapters keep the original settings and pause semantics.

Close marks the host closed, detaches its exact scheduler token, cancels its annotation/title/request callbacks, closes its status session, and restores its temporary UI registration patches. Home teardown uses an already-loaded module only. Shared Sleep preparation is cancelled only when the closing host is still current, so a late predecessor close cannot cancel its successor. Suspend/network lifecycle forwarding likewise accepts only the current host.

Parent merges must retain their existing `Catalog.touch` on CloseDocument and successful books/full rescan in the scheduler completion callback. These parent hooks are absent from this worker's stage-07 baseline and are not replaced by this leaf.

Run `python3 kindlespouse/test_plugin.py --runtime <pinned-runtime> --test main_lifecycle`. The test uses actual LuaJIT and production main/Scheduler/Launcher/Status/Sleep/Menu/Guard modules, isolated settings/files, fake timers/process execution, and controlled UI fixtures. It covers supported/unsupported/throwing installations, deferred callback safety, optional reader installation, close cleanup, late close ownership, refresh without reinit and preservation of foreign callbacks.
