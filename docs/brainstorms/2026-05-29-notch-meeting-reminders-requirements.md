---
date: 2026-05-29
topic: notch-meeting-reminders
---

# Notch Meeting Reminders — Requirements

## Summary

A macOS notch app that surfaces your meeting talking points as a calm, always-on-top list during the meeting — the one surface a fullscreen call can't bury. Agents are the primary way points get in: a built-in skill and CLI write to a local store, with a minimal click-to-type quick-add on the notch itself. Privacy-first by construction — the store holds only times and notes, never reads the calendar, and requires no integrations.

## Problem Frame

When you want to remember to raise something in a meeting, the note you make is rarely *present* at the moment you need it. Paper notes live off-screen and get forgotten. A notes app gets buried behind the fullscreen Zoom/Meet window — you can't keep it on top of the call without juggling windows mid-conversation. The capture isn't the hard part; surfacing the right points, unoccluded, at the right time is.

The macOS notch is the one region the system keeps above everything, including fullscreen calls. That makes it the natural home for "things to bring up right now" — visible at a glance without stealing focus or fighting the call window for screen real estate.

## Key Decisions

- **Notch as the surface, because it is unoccludable.** The product's reason to exist is that the notch stays on top of fullscreen calls where today's tools fail. This is a positioning choice, not just a UI one — see Scope Boundaries.
- **Time + note is the only data model.** An entry is a start time plus a list of points. The app never reads the calendar and requires no meeting-platform integration. Privacy and zero-setup are structural properties, not features layered on.
- **Agents are the primary writer; v1 ships the CLI only.** Capture is AI-first: a CLI lets Claude/Codex/other agents write entries directly, and a minimal manual quick-add on the notch covers in-the-moment thoughts. A conversational skill wrapper over the CLI is deferred (see Scope Boundaries).
- **Target user is the agent-native operator.** v1 is for people who already live in a Claude/Codex-style agent workflow; the on-notch quick-add is a fallback, not a full management path. A general-macOS-user onboarding is out of scope.
- **Ambient peek, not nudging.** During a meeting window the notch shows a quiet always-on list you glance at and check off. No interruptions, no smart pulses in v1.
- **Start-time trigger with manual dismiss.** A peek appears at the entry's start time and lingers until you dismiss it, with a midnight-local-time safety net. Lenient by design so a meeting that runs long doesn't lose its list.
- **Latest-wins on collision.** When a new entry's start time arrives while a previous peek is still up, the new points replace it and the previous entry is archived as-is (checked state retained). The notch always reflects "now." (Overlapping-meeting handling is an open question — see Outstanding Questions.)
- **Timing accuracy is best-effort.** Because the app never reads the calendar (see Trust boundary), a moved meeting or an un-briefed agent makes the peek fire at the wrong time or not at all, and the app cannot self-correct. This is an accepted limitation of the privacy stance; the trade against an opt-in timing source is left open (see Outstanding Questions).
- **Privacy is enforced at the surface, not just the store.** The peek renders above fullscreen calls but is excluded from screen capture and screen-share by default, so prepared points never reach call participants or recordings.
- **Archive retained indefinitely.** Archived entries are kept forever rather than auto-purged — accepted as a trade-off for future read-back value, with the privacy cost acknowledged (the store accumulates a meeting-prep history).

## Actors

- A1. **User** — runs the meetings; glances at the notch, checks points off, occasionally quick-adds a point manually.
- A2. **Agent** — Claude / Codex / other coding or assistant agents that write and edit entries via the skill or CLI on the user's behalf.
- A3. **Notch app** — reads the local store, drives the peek lifecycle, persists check-offs and archives.

## Key Flows

- F1. **Agent schedules talking points**
  - **Trigger:** User asks an agent to prep for an upcoming meeting (e.g. "remind me to raise the budget question and ask about the Q3 timeline at my 2pm").
  - **Actors:** A2, A3
  - **Steps:** Agent invokes the skill/CLI to create or update an entry `{ start time, points[] }` in the local store. The notch app picks up the change.
  - **Outcome:** An entry exists for 2:00pm with two unchecked points.
  - **Covered by:** R1, R2, R5

- F2. **Peek surfaces at meeting time**
  - **Trigger:** The clock reaches an entry's start time.
  - **Actors:** A3, A1
  - **Steps:** The notch expands into an ambient peek listing the entry's points, on top of any fullscreen app. It stays visible.
  - **Outcome:** User sees their points at a glance without leaving the call.
  - **Covered by:** R7, R8, R9

- F3. **User works the list during the meeting**
  - **Trigger:** User raises a point, or thinks of a new one.
  - **Actors:** A1, A3
  - **Steps:** User taps a point to check it off; or clicks the notch and types a line to quick-add a point. State persists to the store.
  - **Outcome:** The list reflects what's been raised and what's left.
  - **Covered by:** R12, R13

- F4. **Meeting ends / next meeting begins**
  - **Trigger:** User dismisses the peek, or a later entry's start time arrives, or end-of-day is reached.
  - **Actors:** A1, A3
  - **Steps:** On dismiss → the peek collapses and the entry is archived with its checked state. On a colliding later entry → the current entry archives and the new entry's points take over the peek. On end-of-day → any lingering peek auto-dismisses and archives.
  - **Outcome:** The notch shows only what's relevant now; past entries are archived as-is.
  - **Covered by:** R13, R14, R15

## Requirements

**Data & store**

- R1. An entry is `{ start time, points[] }`, where each point is a short line of text with a checked/unchecked state.
- R2. The store persists only times and point text. It never stores calendar data, attendee details, meeting titles from external sources, or any platform-specific identifiers.
- R3. The store is local. No network sync, account, or remote backend is required for any core function.
- R4. The app operates with no calendar, video-platform, or third-party integration of any kind.
- R16. An entry holds at most ~7 points, and each point's text is capped at ~80 characters. The limits are enforced at write time by the CLI (over-limit writes are rejected), keeping the list bounded to what the notch can display.
- R17. The store lives in the app's sandbox container or a permission-restricted directory (owner-read/write only) and is excluded from iCloud/Time Machine backup — or any backup exposure is documented as an accepted risk. The encryption-at-rest posture is stated explicitly.
- R18. Point text supplied via the CLI is treated as untrusted input: validated for length (R16) and sanitized before persistence and before rendering in the notch.

**Agent interface (CLI)**

- R5. A CLI lets an agent create an entry, add points to an entry, remove a point, and clear/remove an entry.
- R6. The CLI is the sole agent interface for v1. A conversational skill wrapper over the CLI is deferred (see Scope Boundaries) — any agent can drive the product through the CLI directly.
- R7. v1 reads the store at peek-trigger time (start-time arrival), which serves the F1 flow where an agent writes before the meeting. Live pickup of writes that arrive while a peek is already showing is deferred (see Scope Boundaries).
- R19. CLI writes are trusted only within the user's login session; there is no over-network or remote write path into the store.

**Surfacing & lifecycle**

- R8. When the clock reaches an entry's start time, the notch expands into an ambient peek listing that entry's points, rendered above fullscreen applications.
- R9. The peek is non-interrupting: it appears and persists for glancing, and does not steal keyboard/mouse focus or emit alerts.
- R10. The peek remains visible until the user dismisses it, with an automatic dismissal at midnight local time as a safety net.
- R11. When a new entry's start time arrives while a peek is still showing, the new entry's points replace the current peek and the previous entry is archived with its current checked state ("latest wins").
- R20. An entry with no points is a no-op: the peek does not open and the notch stays collapsed at the entry's start time.
- R22. A dismissed entry whose start time is in the past but before the midnight safety net can be re-opened by a deliberate action on the notch, restoring its archived state as the live peek.
- R23. When no peek is active, the notch surface is invisible — it defers to the macOS default appearance, leaving no persistent app artifact.
- R24. The peek is excluded from screen capture and screen-share by default (a non-capturable window level), so prepared points are never visible to call participants or in recordings, even while rendered above the call.

**Interaction**

- R12. The user can check off (and un-check) a point directly on the notch; the change persists to the store.
- R13. The user can quick-add a point to the currently-shown entry by clicking the notch and typing a line — no agent round-trip required. When no peek is showing, quick-add is unavailable (a click on the idle notch is a no-op).
- R14. Dismissing a peek collapses the notch and archives the entry with its current checked state. Dismiss is a deliberate action distinct from check-off (a dedicated close affordance, not a tap on the list body), so the list cannot be archived by an accidental tap mid-meeting.
- R25. Quick-add does not capture keyboard focus from the frontmost application unless the user takes a deliberate action (e.g., activating a dedicated add affordance first), preserving R9.

**Archive**

- R15. Archived entries retain their points and checked state. Storing the archive is in scope; programmatic read-back of archives is deferred (see Scope Boundaries). Archived entries are retained indefinitely (no auto-purge) — an accepted privacy trade-off for future read-back value.

## Acceptance Examples

- AE1. **Covers R8, R10.** **Given** an entry for 2:00pm with 3 unchecked points, **when** the clock reaches 2:00pm, **then** the notch shows all 3 points and keeps showing them at 2:50pm if not dismissed.
- AE2. **Covers R11.** **Given** the 2:00pm peek is showing with 1 of 3 points checked, **when** a 2:30pm entry's start time arrives, **then** the notch now shows the 2:30pm points and the 2:00pm entry is archived with its 1-of-3 checked state intact.
- AE3. **Covers R10.** **Given** a peek the user never dismissed, **when** end-of-day is reached, **then** the peek auto-dismisses and the entry is archived as-is.
- AE4. **Covers R13.** **Given** a peek is showing during a meeting, **when** the user clicks the notch and types a line, **then** a new point is added to the current entry and appears in the list.
- AE5. **Covers R2, R4.** **Given** any entry created by an agent or by quick-add, **when** the store is inspected, **then** it contains only times and point text — no calendar or platform-derived data.
- AE6. **Covers R9.** **Given** the user is typing in a foreground application, **when** an entry's start time arrives and the peek appears, **then** the focused application retains keyboard focus and no system alert or sound is emitted.

## Scope Boundaries

**Deferred for later**

- Active nudging (e.g. a gentle pulse near the end of a window if points remain unraised). The ambient peek is the base it would layer onto.
- Programmatic read-back of archives so an agent can summarize "raised vs. missed" or draft follow-ups. The archive retains the data; exposing it to agents comes later.
- Non-notch Mac fallback (a menu-bar or floating surface for Macs without a notch).
- A conversational skill wrapper over the CLI. v1 ships the CLI only; the skill follows once an agent integration needs more than the CLI provides.
- Live pickup of store writes that arrive while a peek is already showing. v1 reads at peek-trigger time (R7).
- An `edit point text` operation in the CLI. v1 covers edits via remove-and-re-add; a dedicated edit verb is deferred alongside archive read-back.

**Outside this product's identity**

- Calendar, Zoom/Meet/Teams, or any meeting-platform integration. The product's privacy and zero-setup stance is the point; reading external sources would erode it.
- Listening to, transcribing, or note-taking from the call itself. This app is about *your* prepared points, not capturing the meeting.
- A full GUI for managing entries. Agents plus the notch quick-add are the management surface; a separate management app inverts the AI-native identity.
- Cross-device sync, mobile companions, or shared/team entries.

## Dependencies / Assumptions

- macOS with a notch is the target. The unoccludable-on-top behavior is platform-specific; a non-notch fallback is explicitly deferred.
- **Trust boundary (confirmed):** the app never reads the calendar. The agent decides what start time and point text to write, so timing accuracy depends on what the user tells the agent — not on any source the app reads itself.
- The product rests on a load-bearing platform assumption: that the notch region can host a surface that renders above fullscreen apps **and** is excluded from screen capture/share on the target macOS version. This is promoted to a validation spike that must pass before planning (see Outstanding Questions → Resolve before planning); if it fails, the deferred non-notch fallback becomes the actual product.
- Assumes a single active peek at a time is acceptable (no need to show two meetings' lists simultaneously), consistent with the latest-wins decision.

## Outstanding Questions

**Resolve before planning**

- Validation spike: confirm a notch-region surface can render above a native-fullscreen Zoom/Meet call **and** be excluded from screen capture/share on the target macOS version. Pass/fail criterion: a high-window-level borderless window with `canJoinAllSpaces` collection behavior is visibly on top of the fullscreen call locally, yet absent from a screen recording / screen-share of that display. If it fails, revisit the notch-only positioning and the deferred non-notch fallback.

**Deferred to planning**

- Overlapping / back-to-back meetings: reconcile latest-wins (R11) with the "don't lose the list" intent — e.g. confirm before replacing a peek that still has unraised points, vs. archiving silently.
- The timing-accuracy trade (Key Decisions → Timing is best-effort): whether to offer an opt-in, no-integration timing source (e.g. user-pasted schedule text) or an on-notch time adjust, or keep timing fully manual as a hard principle.
- Local store format and location (file shape, where it lives on disk) and the encryption-at-rest decision behind R17.
- Exact CLI command surface and verb naming.
- How the running app observes store changes if/when live pickup (R7) is un-deferred.
- Minimum supported macOS version, notch detection, and any first-run permission prompt (e.g. Accessibility) the always-on-top surface requires.
- Quick-add interaction details (inline field vs. small popover) and the precise dismiss vs. check-off affordances (R14, R21-adjacent).
