# Mint Todo 2.0 goals preview

Development branch: `feature/goals-and-ai-planning`, based on main `c36e813`. No main merge is part of this work.

## Architecture found in 1.4

- `MintTodo.swift`: SwiftUI daily list hosted in an AppKit borderless NSPanel, persistent resize/pinning, TaskStore and optional ISO 8601 deadlines.
- `tasks.json`: categories plus a flat Todo array; legacy numeric dates are still readable. No existing daily priority or goal hierarchy.
- `FontSettings.swift` / `AppearanceSettings.swift`: local fonts, size, appearance and UserDefaults settings.
- `RemindersSync.swift`: one selected EventKit list; stable UUID-to-reminder links in `reminder-links.json`, local change callback plus an 8-second poll. The per-list reconciliation is retained; access refresh, writable-list discovery and async fetch isolation are hardened.
- Text/Markdown checkbox import is line based; there was no block Markdown reader.
- Direct `swiftc` build, macOS 13 minimum, universal Apple Silicon/Intel app, ad hoc signature. No third-party runtime dependencies.

## Implemented incrementally

### V1: goals, import and Markdown

`GoalModels.swift`, `GoalStore.swift`, `OrbPlanSchema.swift`, `GoalEditorView.swift`, `GoalViews.swift`, `MarkdownNotes.swift`, `PlanPrompt.swift` add a separate Goal → Phase → Task hierarchy and a wider, resizable native window. Daily list and menu-bar entries open “我的目标”.

Manual creation/edit/delete, stage/task ordering, optional dates, statuses, long/short types, timeline collapse, milestones, progress and history/archive are supported. Markdown supports headings, inline emphasis/code/links, lists, code fences with copy, interactive checklists and explicit step promotion. Notes steps never count toward progress or auto-complete their task.

Plan import accepts JSON text/files and a complete outer Markdown JSON fence. Validation checks core fields/types/schema, real YYYY-MM-DD dates/order, estimates, duplicate IDs, missing/circular dependencies and size limits. Unknown optional fields are ignored. Empty phases are allowed with a warning. All edits take place in a draft until confirmation; duplicate titles/content require an additional confirmation. Export uses the stable `orb-todo-plan-v1` contract, including null dates/estimates. Research examples are not installed as default goals.

### V2: daily linkage

Only an explicit “加入待办列表/今日待办” creates a daily item. Optional `Todo.goalTaskID` links daily tasks; 2.2 also adds optional completion/recurrence metadata. Old records decode without these fields. Both sides retain stable IDs. A linked daily Todo is the source of execution status; goal commands update it once and the store callback reconciles without recursive saves. A missing daily item clears its link, retaining the goal task. Deleting a goal/stage/task retains daily items and removes their association. Same-title unlinked daily tasks can be linked after user choice. Goal import rekeys internal IDs, preventing cross-plan collisions.

Only daily Todos enter EventKit; GoalStore has no EventKit calls. Existing reminder updates preserve the optional goal metadata. Completion timestamps and manual Markdown outcome records persist and export.

Progress: completed counted tasks / all counted tasks. Paused tasks remain in the denominator; cancelled/archived tasks are excluded. Empty stages report zero. Dates and note checkbox counts never imply completion. Goal/phase status remains explicitly editable.

### V3: optional AI

`AIClient.swift` and `AISettingsView.swift` use native URLSession and Security. Base URL and model are user configured; there is no default provider. Keys are stored only in macOS Keychain, not preferences, JSON or logs. URL normalization supports root, `/v1` and a complete `/chat/completions` path. Remote endpoints require HTTPS; localhost HTTP is allowed. Redirects are rejected so credentials cannot follow them to another host. Requests use no mandatory JSON mode, model-specific parameters or Structured Outputs.

A connection test sends a short test message only. Generation sends the form's inputs, then uses exactly the same parser and editable import preview. AI-suggested dates are labeled suggested. Task refinement sends only its title/summary/notes, goal title and the user's instruction, then offers append/replace/cancel. Cancellation, timeout, authentication, 404, rate limit, malformed/empty/nonstandard and truncated outputs produce recoverable messages. Provider error bodies are not shown, avoiding echoed keys. No external request happens on app startup.

## Local Apple Reminders repair

The installed app had a stale saved calendar identifier: it no longer matched any current list. Read-only diagnostics confirmed a writable local EventKit source on this Mac, with no iCloud requirement. The new settings refresh on activation, appearance, EventKit changes and polling; list labels include local/account identity and exclude read-only lists. An unavailable selection pauses sync and preserves local data and link history. Explicit local-list creation is available only if EventKit exposes a local source. Other Macs may not expose one; the app reports that limitation instead of inventing local account support.

Every fetch captures its list ID and generation; switching/pausing invalidates and cancels it. Callback rechecks current authorization and list availability; timeout is 25 seconds. Local-save failure rolls back in-memory reminder changes and does not advance links. Sync links are atomically saved with errors reported. Existing remote reminders' alarms are retained; a deadline is not an automatic notification guarantee.

`zsh test.sh --local-reminders` is an opt-in live test requiring existing authorization and a local source. It creates a uniquely named disposable local QA list, tests both directions and stale selection cancellation, and removes its own list. It never requests permission, reads existing reminders, changes iCloud or enables sync on the user's selected list. Standard unit tests still use no EventKit database.

## Storage and recovery

No migration or rewrite of existing daily data is required. The bundle identifier and legacy `~/Library/Application Support/OrbTodo` path are intentionally unchanged. New data is in `goals.json` (version 1). A complete candidate is encoded before atomically writing. The previous readable file is saved to `goals.backup.json`. Corrupt primary files block goal writes; an explicit recovery action restores the backup while preserving the damaged original separately. Closing and reopening reads the same stable hierarchy and IDs.

There is no two-file transaction between goals and daily tasks. Recoverability comes from the daily task's stable `goalTaskID`: after interruption reconciliation can reconnect it without creating another item. In-process saves report a goal/link failure instead of partially publishing the goal candidate.

## Build and test

- `zsh build.sh`: universal app archive in `dist/MintTodo-macOS.zip`, or set `ORBTODO_OUTPUT_DIR` for a separate destination.
- `zsh test.sh`: compile actual production sources into an isolated native test executable. It does not load user tasks or contact a real API / EventKit database. A uniquely named temporary Keychain item is created, updated, read and deleted.
- For UI QA, launch a separate preview bundle with `MINTTODO_DATA_DIR=/absolute/test/folder MINTTODO_TEST_MODE=1`. This disables system Reminders access and isolates daily/goal files. Never set these flags for the normal installed app.

Automated checks cover schema and fence parsing, unknown keys, malformed input, dates, IDs/dependencies, long notes, export/reimport, duplicates, draft non-persistence, legacy daily input, restart, storage failure safety, recovery, task linkage and bidirectional completion, simulated reminder updates, checklist isolation, API URL assembly/errors/cancellation, and Keychain read/update/delete.

## Deliberately deferred V4

Whole-goal AI replanning/diffs, automatic rescheduling, dependency editing/graph UI, weighted statistics, rich attachments and multi-version history are future stages. Dependency IDs are already validated, stored, exported and displayed. The current preview can be used without any AI service.

## Validation limits

Live paid/provider-specific API calls require the user's configuration; HTTP behavior is tested with URLProtocol mocks. Real iCloud propagation and Reminders permission prompts are not exercised. Local EventKit integration is checked only in a disposable QA list. The retained reconciliation path is tested via `applyReminderChanges`. macOS 13/Intel compilation is checked, but runtime QA is on this Apple Silicon Mac. This remains an ad hoc signed preview, not a notarized App Store distribution.

## 2.0.1 model discovery

AI settings supports explicit GET model discovery at the sibling `/models` endpoint (root, `/v1`, prefixed paths and complete Chat Completions URLs normalize consistently). Standard `data[].id` responses are deduplicated and sorted. Empty, malformed, unauthorized, timed out or cancelled responses preserve input and permit manual model entry. A changed URL cannot silently reuse a different saved endpoint’s key for discovery. Fetched IDs may include non-chat models; connection testing remains available. API contract: https://developers.openai.com/api/reference/resources/models/methods/list. No real user key is accessed by the automated tests.

## 2.1 integrated long-term tab

`LongTermTasksView` is the third widget tab and observes the same GoalStore as the wide planning window. Paste-and-parse passes a value-based sheet request to PlanImportView, then uses the shared validator and editable confirmation; no duplicate store or daily pollution. Specific plans open selected in the full planning window, including archived/history selection. Existing short plans remain accessible in this collection.

`PlanRevision` allows explicit whole-plan AI revision with a pre-application preview. It retains matching task UUIDs (unique-title fallback for omitted IDs), daily links, completion state/time and outcome records; new IDs are regenerated and dependencies remapped. New tasks cannot acquire AI-invented completion or links. Removal titles/counts are shown; removed daily items are retained under the existing unlink behavior. Applying a stale snapshot is rejected to protect concurrent completion/reminder updates. This is a preview workflow, not an automatic scheduler or full textual diff engine. No real AI key is needed by tests.

## 2.2 paper design and window interaction

Only the widget's outer mask and background use a Rectangle. Internal tab, entry, card and native control shapes retain their previous rounding. Retro paper is opt-in via `noteStyle`, with four persisted `notePaper` palettes; Canvas draws fixed fibres, rules and a margin without external image assets. The minimal style retains existing glass/solid/transparent/photo preferences. Retro content forces a light local color scheme for legible ink on paper.

The collapsed view uses a 52-point hit area and a 32-point visible circle by default (26–40 in settings). It uses the theme color as an opaque solid or unruled paper texture, with no photo/glass/marks, and docks at the nearest of the current screen's four visible corners.

The old lower-right resize glyph is removed. An AppKit NSView overlay accepts mouse events only within 9-point edges or 18-point corners; it returns nil for the rest of the content. Cursors indicate direction. Drag calculations anchor the opposite edge, respect minimum dimensions, screen bounds and the 900-point cap, and existing NSWindow notifications persist size/position. Unit checks cover the geometry. Native settings fields and buttons remain interactive.

## 2.2 completion, recurrence and tolerant import

Daily Todo adds optional completedAt, repeatRule, repeatInterval, occurrenceAt, generatedFrom and recurrenceSpawnedAt. All old records remain decodable. Completion stamps are set only on a state transition; uncompletion clears the stamp. Reminder imports preserve remote completionDate or use the observed completion time. The Todo tab includes pending and today's completed items; the Completed tab retains all history.

Enter creates a sheet-local draft. Only successful atomic save inserts it; cancellation inserts nothing and write failure keeps the editor open. Daily/weekdays/interval recurrence uses Calendar day arithmetic, preserving local due time across DST. The timer/startup generates one next occurrence when eligible, marking the source in the same write so restart cannot duplicate it. Missed occurrences collapse to the current eligible day; outstanding items do not multiply. Restoring old completion leaves any existing successor intact. Recurrence is local, not mapped to EventKit recurrence rules.

Goal creation creates its named category without creating daily tasks. Explicit attachment inherits it; goal edits regroup linked daily records. Category and goal files remain separately recoverable, not a multi-file transaction.

Import extracts one balanced object while respecting JSON string quoting. It removes Markdown punctuation escapes only inside strings, escapes literal line breaks/tabs, and removes trailing commas outside strings. It reports normalization in warnings and retains strict structural/date/dependency validation. Multiple objects, arrays and truncation are rejected. Copying any custom prompt always appends the current contract and a parse-tested JSON example.

Validation: 127 native checks passed, including calendar recurrence/DST, today-only completion, restore, persistence/idempotency, failed draft writes and tolerant parser fixtures. UI QA uses isolated tasks and disables EventKit. No paid AI endpoint was contacted.

AppKit WindowDragSurface handles explicit header/title dragging and orb pointer tracking with a 3-point threshold. Click without drag opens goals or expands the orb. Collapse chooses the nearest corner from the window center on its current screen; expanding follows a moved orb and clamps into the visible frame. Nine geometry checks cover four-corner docking and screen containment.

## 2.3 signed automatic updates

AppUpdater.swift wraps Sparkle 2.10.0 SPUStandardUpdaterController. Info.plist supplies a fixed GitHub Releases latest/download/appcast.xml URL, public Ed25519 key, automatic-check/download defaults, signed-feed requirement and verify-before-extraction. No system profiling. Sparkle owns scheduling and preferences; the UI binds its properties instead of duplicating defaults. Startup may make one immediate background check only when automatic checks are enabled. Test mode disables the updater unless MINTTODO_TEST_UPDATES=1 explicitly opts in.

setup-sparkle.sh downloads the exact official archive with a pinned SHA-256. build.sh embeds the upstream-signed universal framework preserving symlinks/signatures, includes its complete license and signs the containing app ad hoc. The app is not Developer ID signed/notarized; Gatekeeper/translocation and non-writable locations may require initial manual installation or authorization. Existing data stays outside the bundle.

release.sh verifies that Keychain account com.codex.orbtodo.release matches SUPublicEDKey, builds the app, signs its archive and feed using generate_appcast. Never export/commit/upload the private key. Keep that Keychain available for future releases. Publish v<CFBundleShortVersionString> against the source branch and attach the unmodified MintTodo-macOS.zip and appcast.xml to a GitHub Release marked latest. Attach MintTodo-project.zip for optional full-source downloads. The README's stable latest/download links do not change between releases. Increment both CFBundleVersion and version label for new releases. Do not replace signed bytes in an existing tag.

Header labels are single-line fixed-size; 40-point controls and a 44 × 40 collapse hit area fit the 320-point minimum width. The edge overlay passes header control events through except the outermost 3 points. Unpublished release feeds are regenerated after each rebuild so signatures always match the archive.

## 2.3.1 immediate completion

The Todo tab now shows only todo and pending tasks. Completed tasks move immediately to the Completed tab, where unchecking restores them. Removed the redundant day-change refresh; recurrence and completion timestamps are unchanged. All 127 native checks pass, including immediate removal, retained history and restoration.

## 2.4 daily subtasks

Daily Todo embeds an optional-on-read `subtasks` array of stable UUIDs, titles and independent completion flags. Older records decode to an empty array. Creation and editing use the same sheet-local draft with plus/minus controls; cancellation leaves stored tasks unchanged. The list shows a completion count, collapsible child rows and smaller circle controls. Subtask completion uses the same atomic-save rollback as parent status changes and does not change parent status.

New recurring occurrences copy subtask titles with fresh IDs and unchecked state. Text export writes indented Markdown checkboxes; import attaches indented children to the preceding parent. EventKit continues syncing parent tasks only and preserves local subtasks when applying reminder changes. All 135 native checks pass, covering persistence, restart, independent completion, text roundtrip, recurrence reset and existing legacy-data compatibility.
