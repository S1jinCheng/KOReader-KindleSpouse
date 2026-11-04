# Shared synchronization scheduler

`scheduler.lua` is one Lua module singleton per KOReader process. It never opens sockets, starts Wi-Fi, touches device files, or changes pause flags. The existing worker lock remains authoritative. FileManager and ReaderUI share it through `require("scheduler")`.

Call `configure(deps)` once before attaching. Reconfiguration preserves pending work and runtime state while replacing dependency functions. Every dependency must avoid closing over an obsolete plugin instance.

Required dependencies:

- `now()` returns epoch seconds compatible with worker `startedAt`/`completedAt`.
- `read(key, default)` and `save(key, value)` access current KOReader settings.
- `connected()` checks an existing connection without enabling Wi-Fi.
- `reading()` checks the current `ReaderUI.instance`, not the attaching host.
- `paused(mode)` checks the corresponding existing pause file; updates uses full-sync pause semantics.
- `running()` checks the existing worker lock and live process.
- `progress()` returns normalized worker state, including `state`, `startedAt`, mode flags or `mode`, and timestamps. Include a stable invocation `runId` or worker `pid` when available.
- `launch(mode, manual, host)` starts the existing worker asynchronously and returns `true`, or `false, error`. `full` maps to the existing shell's normal invocation. This callback receives the current host at invocation time. It must not call the shell with arbitrary mode input.
- `schedule(delaySeconds, callback)` and `unschedule(callback)` map to UIManager. Callbacks have stable identity; unschedule removes every matching pending callback.

Optional dependencies:

- `enabled(mode)` overrides automatic-mode settings lookup. Manual requests bypass automatic toggles but always respect `paused(mode)`.
- `reserve(mode, manual)` returns an owner token or `nil, error` before launch. `release(token)` clears only that reservation. Without these hooks the launch adapter owns reservation lifecycle. Its atomic `.partial` plus rename marker is a launch handshake, not a cross-process mutex; keep the worker's exclusive lock. Do not overwrite another live launch marker. The scheduler releases its reservation when it observes fresh running state, a terminal result, or a launch failure/20-second timeout.
- `notify(result, host)` receives a matched terminal result and the current host. Its callback may render feedback or apply queued annotations. Results include a mode and a `manual` boolean; silent/manual notification policy remains an adapter concern.

`attach(host)` returns an opaque ownership token. `detach(token)` only detaches a matching current host. Detaching retains pending deadlines, generation, backoff and active-worker observation. Attaching a successor resumes the same process-wide callbacks. A late old-widget close cannot detach the successor. Calling `suspend()` stops scheduling without cancelling a worker; `resume()` resumes observation and adds a full request after eight seconds only when the last successful full sync is older than thirty minutes. Offline and sleep time do not consume the fallback interval, including overlapping intervals.

`request(mode, manual)` coalesces `books`, `full`, `updates`, `profile` or `titles` work. Due manual requests take precedence. A paused or offline request remains pending until a later lifecycle/configuration event re-arms the scheduler. Manual requests reset retry delay. `markDirty(kind)` increments `kindlespouse_sync_generation`: `page`/`reading` only marks reading state; other kinds schedule a trailing fifteen-second full-sync debounce. `pageDirty()` is the reading shorthand.

`networkConnected()` queues a check after eight seconds: full if either dirty flag is set, otherwise updates. `networkDisconnected()` cancels idle scheduling while offline. Repeated events coalesce; automatic launches wait for the eight-second network settling deadline and a restored connection resets retry delay. The first attach requests full once when the last full sync is older than ten minutes. Idle fallback is fifteen awake connected minutes, or thirty while reading, and queues books plus updates. Page-only changes therefore wait for close/annotation events, stale resume, or reconnection before a full upload.

There is no idle 30/90-second loop. A running job is observed at five-second intervals, and a launch handshake at one-second intervals for at most twenty seconds. Failures retry with 60, 120, 240, 480 and at most 900 seconds. Disconnected time does not launch work; existing pending work is preserved.

Only a fresh matching successful full result can clear dirty flags, and only if its captured generation still equals the persisted generation. Other modes and externally started workers never clear them. Older completed records are rejected. Worker timestamps alone cannot distinguish two otherwise identical same-second invocations; if no invocation identifier is available the scheduler conservatively times out an indistinguishable result instead of clearing dirty state.

`snapshot()` supplies shared pending/launch/run state for status/profile consumers. Do not retain per-instance copies of `launch_pending`, generation, or backoff. Keep dialogs and their refresh tasks local to their UI owner, and close/unschedule them on widget teardown. None of these timers run after KOReader exits.

Existing settings preserved: `kindlespouse_auto_receive`, `kindlespouse_auto_sync`, `kindlespouse_last_sync`, `kindlespouse_last_updates`, `kindlespouse_sync_dirty`, `kindlespouse_reading_dirty`, `kindlespouse_sync_generation`. Successful books checks additionally save `kindlespouse_last_books_check`.

Verification uses `kindlespouse/test_scheduler.lua` through the existing `test_plugin.py --test scheduler` harness. It runs actual LuaJIT with fake time, network/process state, execution, launch-marker ownership and UI timer functions; no device, network or personal data is accessed.
