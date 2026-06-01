---
date: 2026-06-01
type: feat
status: active
---

# feat: Editable Meeting Title

## Summary

Add an optional **meeting title** to each entry — a short human label (e.g. "Q3 Planning Sync") shown in the peek as its own row beneath the existing time/nav bar. Agents write it through the `notch` CLI (a `--title` flag on `add` and a dedicated `notch title` subcommand), and the user edits it inline on the peek for active/upcoming meetings, exactly like a talking point. Untitled entries look and behave exactly as today (time-only), and the on-disk store stays backward-compatible.

## Problem Frame

The peek identifies a meeting only by its start time. When several meetings sit close together, or when reviewing past entries, a bare time is thin context — there's no way to say *what* the meeting is. Agents preparing points have a name in hand but nowhere to put it. Adding a short, optional title gives each entry a glanceable identity in the peek and in `notch list`, written by the agent and correctable by the user, without pulling in any calendar/integration data (which stays out of scope per the product's privacy-first, local-only identity).

## Key Decisions

- **`Entry.title` is an optional `String?`.** Swift's synthesized `Decodable` decodes a missing optional key as `nil`, so adding `title` to `Entry` is backward-compatible with existing `store.json` files **without** a custom `init(from:)` (unlike `Point.id`, which needed one because it is non-optional). New field defaults to `nil` in the memberwise init.
- **`title` is user/agent-authored, so it leaves the privacy guard.** `selfcheck`'s AE5 check currently fails the run if the store JSON contains the substring `"title"` (a proxy for calendar-derived data, origin R2/AE5). A user-authored title is legitimate, so `"title"` must be removed from that leak-detection array; `calendar`/`attendee`/`zoom`/`meet`/`email` stay banned. Without this, the title round-trip test and the privacy check are mutually exclusive.
- **Title is sanitized untrusted input with its own length cap.** Titles go through the same `Sanitizer` as points (strips control/format/RLO scalars, NFC, trims) via a new `Validation.validateTitle`, capped by a new `Limits.maxTitleLength` (60 — shorter than the 80-char point cap, since the title is a single glanceable header). Empty-after-sanitize is **allowed** for a title and means "clear it" (→ `nil`), unlike points where empty throws.
- **Separate title row, not a replacement for the time.** The title renders as its own row directly below the unchanged time+nav+× top bar (per the confirmed layout). The existing `model.title` field keeps holding the time string; the title is a **new** `model.meetingTitle` field — no rename, so the diff stays scoped to the feature. (A future cleanup may rename the time field for clarity; out of scope here.)
- **Both CLI write paths, with preserve-on-replace.** `notch add <time> --title "<text>" <point>...` sets the title at creation; `notch title <time> <text>` sets/replaces/clears it later. `add` **preserves** an existing entry's title on replace when `--title` is not supplied, so re-adding points to update a meeting doesn't silently wipe its name. To keep that observable (the failure mode is a silent wipe), `add` echoes the resulting title in its confirmation line.
- **Inline edit reuses the point-edit pattern.** The title row uses the same tap-to-edit → `TextField` → commit-on-Enter / cancel-on-Esc-or-blur flow as `PointRowView`, the same key-focus handoff (`onEditBegin` → `makeKeyAndOrderFront`), and the same recency gating (active/upcoming editable, past read-only). Opening the title field blurs any in-progress point edit, which cancels it via the existing blur-cancel — only one inline field is ever active.

## Requirements

- **R1** — Each entry may carry an optional title; entries without one behave exactly as today.
- **R2** — The peek shows the title as its own row below the time/nav bar when present; nothing extra when absent.
- **R3** — The title is editable inline on the peek for active and upcoming meetings; past entries are read-only.
- **R4** — Committing an empty/whitespace title via the **peek's inline edit** clears the title (stores `nil`) and the row immediately shows the "Add a title…" affordance (active/upcoming) or nothing (past). External CLI title changes are reflected on the peek's next render, not pushed into an already-open peek — the same freshness behavior points already have.
- **R5** — `notch add <time> --title "<text>" <point>...` sets the title at creation; omitting `--title` on a replace preserves any existing title; `add` reports the resulting title.
- **R6** — `notch title <time> <text>` sets/replaces the title on the entry at `<time>`; empty `<text>` clears it; errors if no entry exists at `<time>`.
- **R7** — Titles are sanitized like points and capped at `maxTitleLength`; over-length input is rejected at write time, before any store mutation, with a readable error.
- **R8** — `notch list` shows the title alongside the time for entries that have one.
- **R9** — The title round-trips through the store; an existing titleless `store.json` loads with `title == nil` (no migration, no data loss).

## Implementation Units

### U1. Add `title` to the `Entry` model + free the privacy guard

- **Goal:** Give `Entry` an optional, backward-compatible title field, and stop the privacy check from treating `title` as forbidden.
- **Requirements:** R1, R9
- **Dependencies:** none
- **Files:**
  - Modify: `Sources/NotchCore/Entry.swift`
  - Modify: `Sources/selfcheck/main.swift` (Store round-trip + backward-compat decode; AE5 leak-array fix)
- **Approach:**
  - Add `public var title: String?` to `Entry`; add `title: String? = nil` to the memberwise `init`. Do **not** add a custom `init(from:)` — synthesized `Decodable` already decodes a missing optional key as `nil`. `Equatable`/`Codable` stay synthesized.
  - In `selfcheck`, remove `"title"` from the AE5 `leaks` array (the substring guard `["calendar","attendee","title","zoom","meet","email"]`). Leave the other terms. Add a one-line comment that `title` is now a legitimate user-authored field.
- **Patterns to follow:** the existing `Entry`/`Point` structs in `Entry.swift`; note `Point` only needed a custom decoder because `id` is non-optional.
- **Test scenarios:**
  - **Covers R9.** Encode an `Entry` with a title, decode it → title preserved.
  - **Covers R9.** Decode a `StoreData` JSON string with no `title` key on its entries → entries load with `title == nil` (no throw).
  - **Covers R9.** A `Store` save/load round-trip of a titled entry leaves the AE5 guard green (confirms `"title"` was removed from the leak array; `calendar`/`attendee`/etc. still absent).
  - Two entries differing only by `title` are not `Equatable`-equal.
- **Verification:** `swift run selfcheck` round-trips a titled entry, decodes a legacy titleless store to `nil`, and stays ALL PASS (AE5 included).

### U2. Title validation + length cap

- **Goal:** Sanitize and bound title text, with clear-on-empty semantics.
- **Requirements:** R4, R7
- **Dependencies:** none
- **Files:**
  - Modify: `Sources/NotchCore/Validation.swift`
  - Test: `Sources/selfcheck/main.swift`
- **Approach:**
  - Add `Limits.maxTitleLength = 60`.
  - Add `ValidationError.titleTooLong(max:)` with a readable `description`.
  - Add `Validation.validateTitle(_ raw: String) throws -> String?` — run `Sanitizer.sanitize`; if the result is empty, return `nil` (clear); if its `count` **exceeds** `maxTitleLength` (i.e. `> 60`, so exactly 60 is allowed), throw `titleTooLong`; else return the cleaned string. (Contrast `validatePoint`, which throws on empty.)
- **Patterns to follow:** `Validation.validatePoint` and the `Sanitizer`/`Limits`/`ValidationError` shape in the same file.
- **Test scenarios:**
  - **Covers R7.** `"Q3 Sync"` → `"Q3 Sync"`; leading/trailing space trimmed.
  - **Covers R4.** `"   "` and `""` → `nil` (clear, no throw).
  - **Covers R7.** A 61-char (post-sanitize) string → throws `titleTooLong`; a 60-char string → accepted (boundary).
  - A title containing a U+202E RLO override → the override scalar is stripped (reuses `Sanitizer`).
- **Verification:** `swift run selfcheck` exercises pass/clear/boundary/too-long/strip cases.

### U3. `StoreService` title operations

- **Goal:** Create-with-title and set-title (by time and by id), with preserve-on-replace, validating before any mutation.
- **Requirements:** R3, R4, R5, R6, R7
- **Dependencies:** U1, U2
- **Files:**
  - Modify: `Sources/NotchCore/StoreService.swift`
  - Test: `Sources/selfcheck/main.swift`
- **Approach:**
  - Extend `createEntry(at:points:title:)` with `title: String? = nil`, where the parameter encodes the nil-vs-empty distinction at the boundary: **`nil` = not supplied** (preserve on replace), a **non-nil string (including `""`) = supplied** (set/clear). Validate points and (when supplied) the title **before** touching the store, so an invalid title throws with the store unchanged. On a **new** entry: set `entry.title` to the validated value (nil if not supplied). On **replace**: if `title` was supplied, set the validated value (clearing when empty); if `title` was `nil`, copy the existing entry's title onto the replacement.
  - Add `setTitle(at startTime: Date, title: String) throws` — `noEntry` if none; validate then set (clear on empty). Used by `notch title`.
  - Add `setTitle(entryID: UUID, title: String) throws` — fresh-read entry-by-id mutation (mirrors `updatePoint`); `noEntryID` if none. Used by the peek inline edit (R3).
- **Patterns to follow:** existing `createEntry`, `updatePoint(entryID:index:text:)`, and `addPoint(at:)`/`setChecked(entryID:)` in `StoreService.swift` (validate up front → fresh `load()` → mutate → `save()`).
- **Test scenarios:**
  - **Covers R5.** `createEntry(at:points:title:"Q3 Sync")` → entry has that title.
  - **Covers R5.** `createEntry` again at the same time with `title: nil` (not supplied) → points replaced, **title preserved**.
  - **Covers R5.** `createEntry` again with `title: ""` (supplied empty) → title cleared.
  - **Covers R6.** `setTitle(at:title:"X")` sets; calling again with `""` clears (`nil`).
  - **Covers R6.** `setTitle(at:title:)` on a missing time → throws `noEntry`.
  - **Covers R3.** `setTitle(entryID:title:)` sets the targeted entry; missing id → `noEntryID`.
  - **Covers R7.** Over-length title to any path → throws `titleTooLong`, store unchanged (assert a re-load shows the prior state).
- **Verification:** `swift run selfcheck` covers create-with-title, preserve-vs-clear on replace, set/clear by time and by id, and the missing-target + too-long (store-unchanged) error paths.

### U4. `notch` CLI: `--title` flag, `title` subcommand, list rendering

- **Goal:** Expose title writes to agents and show titles in `list`.
- **Requirements:** R5, R6, R8
- **Dependencies:** U3
- **Files:**
  - Modify: `Sources/notch/main.swift`
- **Approach:**
  - **`add` flag parsing:** scan `rest` for the **first** `--title` token; take the **single** token immediately after it as the title value and remove both from the array; the remaining tokens are points. Resolve the shadow paths explicitly: `--title` as the last token with no following value → `die` with a usage error; `--title` absent → pass `nil` to `createEntry` (preserve-on-replace); `--title ""` → pass `""` (clear). Re-apply the "≥1 point required" guard to the **remaining** points (not the raw arg count). A point whose literal text is `--title` is an accepted edge cost of the simple scan (documented, not handled).
  - Pass the parsed value (`nil` / string / `""`) straight through to `createEntry(at:points:title:)`.
  - Echo the resulting title in the confirmation: e.g. `added entry at 2:00pm — "Q3 Sync" with 1 point(s)`, or `... (untitled)` when `nil`, so preserve-vs-clear is observable (R5).
  - **`title` subcommand:** `notch title <time> <text...>` → `service.setTitle(at: time, title: rest.dropFirst().joined(separator: " "))`; empty text clears (print "cleared title at …").
  - **`list`:** when an entry has a title, render it on the header line, e.g. `2:00pm — Q3 Sync:` (fall back to `2:00pm:` when `nil`).
  - Update the `usage` string with both the `--title` flag and the `title` subcommand.
- **Patterns to follow:** the `switch command` arms, `requireTime`, `die`, and the `usage` block in `notch/main.swift`; mirror `add-point`'s shape for the `title` arm.
- **Test scenarios:** `Test expectation: none — the CLI is a thin `main.swift` over `StoreService` (covered by U3); flag parsing, the echoed confirmation, and list rendering are verified manually. Cap/validation errors surface through the existing `ValidationError` catch.`
- **Verification:** `notch add 2pm --title "Q3 Sync" "p1"` echoes the title and `notch list` shows it; `notch add 2pm "p1 p2"` (no flag) preserves the prior title and the echo confirms it; `notch title 2pm "Renamed"` updates; `notch title 2pm ""` clears; an over-length title exits non-zero with a readable message.

### U5. Peek title row: display, inline edit, layout

- **Goal:** Render and inline-edit the title as a distinct header row below the top bar, gated by recency.
- **Requirements:** R2, R3, R4
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/MeetingGenieApp/PeekView.swift`
- **Approach:**
  - In `PeekModel`: add `@Published var meetingTitle: String? = nil` and callbacks `onTitleEdit: (String) -> Void` and `onTitleEditBegin: () -> Void`. Leave the existing `title` (time string) field as-is — no rename.
  - Add a new `MGTheme` token for title type so it reads as a header distinct from points — e.g. `titleFont = .system(size: sizeCaption, weight: .semibold)` (one rung heavier than point rows), full white for active/upcoming, `MGTheme.pastRow` dimmed for past.
  - Insert a **title row** between the top-bar `HStack` and the points list, shown only when there is a current entry (omit entirely in the empty-browse state — conditionally absent from the `VStack`, not rendered empty):
    - **Has title:** the title text in the title font, `.lineLimit(1)` + `.truncationMode(.tail)` (one line — keeps the fixed row height valid). Active/upcoming: hovering reveals a pencil that opens a full-width inline `TextField` (`fieldFill` + `fieldBorderFocus`, like `PointRowView.editField`) seeded with the current title; Enter commits via `onTitleEdit`, Esc/blur cancels. Past: read-only, no pencil, no hover state.
    - **No title + active/upcoming:** a persistent, placeholder-styled "Add a title…" affordance (`MGTheme.placeholder` color, brightening to `iconHover` on hover — distinct from the bolder "Add point" button so the two don't compete) that opens the same inline field. Committing empty is a no-op/clear.
    - **No title + past:** render nothing.
  - The inline title field uses `onTitleEditBegin` for the key-focus handoff before becoming first responder (same as point edit / quick-add).
- **Technical design (directional):** placement within the existing `VStack`:
  ```
  VStack(.leading) {
    HStack(.center) { ‹  time · recency   ›  × }   // unchanged top bar (model.title = time)
    titleRow                                       // NEW — title / edit field / "Add a title…"
    points + quickAdd  (or emptyMessage)           // unchanged
  }
  ```
- **Patterns to follow:** `PointRowView` (hover-pencil, `editField`, `beginEdit`/`commitEdit`, `@FocusState`), the "Add point" button in `quickAdd`, and `MGTheme` tokens (`placeholder`, `iconHover`, `pastRow`, `fieldFill`, `fieldBorderFocus`).
- **Test scenarios:** `Test expectation: none — SwiftUI view; verified on-device. States checked: titled active = editable header; titled past = read-only dimmed; untitled active = "Add a title…"; untitled past = absent; long title = single-line tail-truncated; opening the title field cancels an in-progress point edit (blur).`
- **Verification:** On-device: an active meeting shows its title as a header and edits inline; a long title truncates on one line; a past meeting shows it dimmed/read-only; an untitled active meeting shows "Add a title…"; an untitled past meeting shows no title row; untitled entries otherwise look identical to today.

### U6. `PeekController` title wiring

- **Goal:** Populate the title into the model, persist inline edits, and size the panel for the title row.
- **Requirements:** R2, R3, R4
- **Dependencies:** U3, U5, U1
- **Files:**
  - Modify: `Sources/MeetingGenieApp/PeekController.swift`
- **Approach:**
  - In `show(_:)` and `renderCurrent()`, set `model.meetingTitle = entry.title` (the existing `model.title = TimeFormatting.display(...)` time assignment is unchanged). In the empty-browse branch of `enterBrowse()`, set `model.meetingTitle = nil`.
  - Wire `model.onTitleEditBegin = beginQuickAdd` (reuse the key-focus handoff) and `model.onTitleEdit = { [weak self] in self?.editTitle(text: $0) }` in `init`.
  - Add `editTitle(text:)`: guard `model.kind != .past`; resolve `displayedEntryID()`; `try? service.setTitle(entryID: id, title: text)`; refresh `model.meetingTitle` from a fresh `service.entry(id:)` and sync the browse `sequence` cache entry (mirror `refreshPoints`); `panel?.resignKey()`; `updatePanelFrame()`.
  - In `updatePanelFrame()`, add a title-row term to `height`: `let showsTitleRow = model.meetingTitle != nil || model.kind != .past` (the "Add a title…" affordance occupies the row for active/upcoming too); add a named `titleRowHeight` constant (≈ 26, matching the per-row constant) when `showsTitleRow`, else 0. So the panel grows/shrinks with the row in both the titled and the affordance state.
- **Patterns to follow:** `editPoint`/`refreshPoints` (gating, fresh-read, browse-cache sync, `resignKey`, `updatePanelFrame`), and the existing `model.title`/`model.points` assignments in `show`/`renderCurrent`.
- **Test scenarios:** `Test expectation: none — @MainActor AppKit lifecycle; verified on-device. Covered: title appears live and in browse; editing an active title persists and survives paging away/back (cache sync); past titles can't be edited; panel height tracks the title row in both titled and "Add a title…" states.`
- **Verification:** On-device: editing an active title persists (visible after paging away/back), a past title is not editable, and the panel resizes correctly as the title/affordance row appears and disappears.

---

## Scope Boundaries

### Deferred to Follow-Up Work
- Renaming the existing `model.title` (time string) field to `model.timeLabel` for clarity — a trivially-reviewable cleanup, kept out of this feature PR.
- A schema-version marker in `store.json` to make the older-writer-drops-field hazard (see Risks) detectable rather than silent.
- A `notch list --json` / richer list formatting — only the human-readable `list` line gains the title here.

### Outside this product's identity
- Deriving titles from calendars, meeting platforms, or any integration — titles are user/agent-authored only.
- Multi-line, rich-text, or styled titles; title search/filtering; per-title notifications.

---

## Risks & Dependencies

- **Stale `notch` binary erases titles on write (medium, forward-compat).** `StoreService` is read-modify-write: every op does `load() → mutate → save()`, re-encoding the **whole** `StoreData`. A `notch` (or app) binary built **before** this change has an `Entry` with no `title` field, so any write it performs (`add-point`, `setChecked`, etc.) re-encodes every entry without `title` and silently wipes all titles. Mitigation: `notch` and the app both link the same `NotchCore`, so building them together from one checkout keeps them in lockstep — the hazard only arises from a separately-built stale binary left on `PATH`; rebuild it. A store-version marker (deferred) would make this detectable. Document this in the System-Wide Impact note rather than leaving the compat story decode-only.
- **`add` preserve-on-replace nil/empty threading (medium).** The "no `--title`" (preserve) vs "`--title ""`" (clear) distinction must survive from CLI parsing through to `createEntry`. A parser bug that collapses both to the same value silently wipes titles on every re-add. U4 pins the parsing; U3's preserve-vs-clear tests guard the service; the echoed `add` confirmation makes a regression observable.
- **Panel sizing (low).** The `titleRowHeight` term must match the rendered row height in both the titled and "Add a title…" states. Verified on-device (U5/U6).

---

## System-Wide Impact

- **Actors:** the agent (writes titles via CLI) and the user (edits inline). No new actors.
- **Privacy/local-only:** unchanged — title is user/agent text, sanitized like points, stored in the same local `store.json`, no network path. The AE5 privacy guard keeps banning calendar/platform-derived substrings; only the now-legitimate `title` leaves the ban list (U1).
- **Backward & forward compatibility:** existing stores load unchanged (`title == nil`), no migration. A newer store read by an older binary decodes fine (unknown key ignored) — **but** an older binary that then *writes* the store erases titles (see Risks); the realistic mitigation is building `notch` and the app together.
- **Existing behavior:** untitled entries render and list exactly as today; the top-bar layout and the `model.title` (time) field are untouched.

---

## Verification Strategy

1. **Build:** `swift build` clean.
2. **Core (`swift run selfcheck`):** title validation (pass/clear/boundary/too-long/strip), Entry Codable round-trip + legacy titleless decode, AE5 still green after the leak-array fix, and StoreService create-with-title / preserve-vs-clear / set+clear by time and id / store-unchanged error paths — ALL PASS.
3. **CLI (manual):** `notch add … --title` (echo shows title), `notch add` without the flag (title preserved, echo confirms), `notch title … / ""`, over-length rejection, and `notch list` showing titles.
4. **On-device:** title-row header display + inline edit across active/upcoming/past, single-line truncation, "Add a title…" affordance, point-edit cancels when the title field opens, panel resize, and untitled-entry parity with today.

Honest gap: the CLI flag parsing and the SwiftUI title row are verified manually/on-device, consistent with the project's posture for the `main.swift` CLI and the AppKit-bound peek.
