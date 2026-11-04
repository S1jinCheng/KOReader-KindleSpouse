# Optional overlay repository migration

No repository has been moved. This step requires explicit user approval after the improvement PRs are reviewed.

The core remains exactly at KOReader v2026.07.1, commit 9192014d8bd82a91dc1012473be0f238dedfdb54. An independent repository could contain only plugins/kindlespouse.koplugin, kindlespouse, the dedicated workflow, user documentation and the applicable licenses. Keep the pinned runtime download hash and the plugin-only scope guard; adapt the latter to compare an overlay tree rather than a full upstream checkout.

Before moving, preserve the current fork and review references, decide the new repository and default branch, update build/documentation links and desktop component source references, and validate the generated package with the pinned AppImage and Scribe hardware. A fresh checkout must run the same catalog, home, scheduler, status, reader and notebook tests without a local desktop installation.

The independent sync worker and optional spouse_preset remain desktop-installed components. Do not copy pairing files, tokens, private books, annotation jobs, snapshots or device logs into the new repository or release. Generated acceptance artifacts must use only synthetic fixtures. An overlay migration does not authorize moving or publishing personal data.

Do not upgrade upstream, rewrite old PR history or rename repositories as part of this plan. This document records the possible move; it does not execute it.
