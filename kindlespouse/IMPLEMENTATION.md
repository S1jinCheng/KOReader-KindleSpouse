# Improvement implementation

Pinned runtime: KOReader v2026.07.1 (9192014d8bd82a91dc1012473be0f238dedfdb54).
Integration base: codex/improvement-baseline-v1. The existing notebook experiment branches remain available. Only the approved plugin, kindlespouse, workflow and README paths are included here.

| Unit | Scope | State |
| --- | --- | --- |
| 01 | P0 annotation isolation, alternate slots, optional sleep preset | Verified in AppImage; device check pending |
| 02 | P4 reversible patch registry | Pending |
| 03 | P4 plugin-only and lint CI guards | Pending |
| 04 | P1 asynchronous catalog and metadata queue | Pending |
| 05 | P1 local shelf refresh and display-mode changes | Pending |
| 06 | P1 body-only tab switching | Pending |
| 07 | P2 shared event scheduler | Pending |
| 08 | P2 localized menus and status dialog | Pending |
| 09 | P4 version guard and main module split | Pending |
| 10 | P3 highlight bar | Pending |
| 11 | P3 reader toolbar | Pending |
| 12 | P3 annotation notebook and navigation | Pending |

Each unit is a separate stacked PR and is verified in the pinned AppImage runtime before the next dependent unit. PRs remain unmerged for user review. Device checks are reported separately from simulator checks. Repository migration, core changes, firmware updates, Amazon NBK editing, DRM work and desktop changes are outside this implementation.

Implementation adaptations: positive-delay scan chunks yield actual input time; the custom shelf must update its own items and scroll geometry as well as the FileChooser; background metadata extraction is serialized because starting a new batch terminates an active batch. These adapt the plan to verified upstream and current plugin APIs.
