# Simplification with unchanged tests

This PR follows the seven revision commits on `codex/improvement-12-notebook`. Its comparison base is `7a8fe56ec8909c226ff2e618e803627f15b79e2f`.

All 29 tracked test and checker files remain byte-for-byte unchanged, including the complete runtime runner and package validator. The comparison checks Git blob identities, including added and removed paths.

## Changes

- The scheduler uses one scheduled callback and drops a redundant owner counter. Launcher writes the existing reservation object directly and removes small one-use wrappers.
- UTC timestamp conversion uses KOReader's existing `ffi.C.timegm` declaration. Strict suffix and UTC round-trip validation remain. Fractional ISO strings still identify separate runs within one second.
- Catalog shares root initialization and removes unused scan generation state. Extraction uses one retry path. Notebook indexing removes intermediate annotation containers.
- Highlight and Notebook settings use one migration function. Both public settings APIs remain direct aliases to it. Explicit flags, legacy false values and unknown settings survive migration.

Reservation ownership, 20-second expiry and owner-preserving release remain because the unchanged tests require them. The ISO parser also retains its tested validation and identity behavior. Neither mechanism has been deleted.

## Size

The metric includes every Lua file under `plugins/kindlespouse.koplugin`, including the new shared settings module. It uses Git blobs with LF line endings, excluding tests, documentation and bundled fonts.

- Total lines: 4,870 to 4,819, down 51 or 1.0472%.
- Nonblank lines: 4,541 to 4,494, down 47 or 1.0350%.
- Source bytes: 232,846 to 230,484, down 2,362 or 1.0144%.
- Lua files: 23 to 24.

The requested 25% reduction is not achieved. No lines are packed, no logic is moved outside the plugin, and no test is weakened to increase the percentage.

Reproduce the size and frozen-test checks after committing changes:

```sh
python3 kindlespouse/measure_plugin.py --base 7a8fe56ec8909c226ff2e618e803627f15b79e2f --output kindlespouse/build/simplification-result.json
```

## Verification

Run the same 24-group source and fresh-package acceptance as the parent PR:

```sh
python3 kindlespouse/build.py
python3 kindlespouse/test_runtime.py --runtime /path/to/koreader --fonts kindlespouse/build/cache --package kindlespouse/build/KindleSpouse-Scribe-Overlay.zip --expected-version 202607010000
python3 kindlespouse/test_scheduler_idle.py --runtime /path/to/koreader --seconds 600
```

The idle check measures actual simulator wall time and background launch count. It does not measure Scribe battery usage or live network speed. Hardware validation remains separate. v2026.07.2 remains unverified and outside the whitelist.
