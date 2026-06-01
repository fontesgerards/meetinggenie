---
date: 2026-05-30
topic: peek-presence-layer
---

# Peek Presence Layer — Requirements

## Summary

Two small additions governing the peek's *presence* — where it appears and whether it appears: (1) a **floating-pill fallback** so MeetingGenie works on Macs/displays without a notch (a clean rounded panel just below the menu bar, with all the same behavior), and (2) a manual **"Hide while sharing"** toggle that reliably suppresses the peek while you present. Both are deliberately minimal and forward-looking — the fallback closes a table-stakes gap for non-notch users; the toggle is a zero-detection privacy control that closes the accepted macOS-15 screen-share leak.

## Problem Frame

MeetingGenie today only renders meaningfully on a notch display, and it shows the peek regardless of whether the user is screen-sharing. Two gaps follow:

- **Non-notch Macs/displays are unserved.** Mac mini / iMac / Studio, older MacBooks, and external monitors have no notch. The product currently has only a geometry *stub* for this; the peek either mis-renders or risks covering the menu bar. Notch-app reviews treat a working non-notch fallback as table stakes — apps that do nothing on external displays draw one-star reviews. (The product owner runs meetings on the built-in notch screen, so this is for *prospective* users, not a personal pain — scope is sized accordingly.)
- **The peek can leak into a screen-share.** It's documented and accepted that on macOS 15+ the peek may appear in a full-display screen-share (`sharingType = .none` is best-effort). A reliable way to hide it while presenting closes that privacy gap.

A generic Focus/DND suppression feature was considered and rejected: the peek is **not ambient** (it only appears at a meeting's start or on browse), so Focus suppression would add little. The real high-leverage suppression trigger is screen-sharing, addressed manually here.

## Key Decisions

- **Manual "Hide while sharing," not auto-detection.** macOS has no reliable "am I being captured?" API (as fiddly as the exclusion problem). A user-flipped toggle is reliable, has zero false-positives, and needs no detection spike. Auto-detection is explicitly deferred.
- **The non-notch peek floats below the menu bar.** With no notch gap to hide in, the menu-bar-safe "T-shape" does not apply — the fallback is a plain rounded panel positioned entirely below the menu bar, so it never covers menu-bar items.
- **Notch screen wins whenever one exists.** The peek stays on the notch display if any connected screen has one; the floating fallback engages only when no screen has a notch. No new external-display routing for notch-laptop users.
- **Same peek, same behavior.** The floating fallback reuses the existing peek — browse, check-off, quick-add, inline edit, remove, the "now" badge, and show/dismiss motion all work identically.

## Actors

- A1. **User** — runs meetings (sometimes on a non-notch Mac/display); toggles "Hide while sharing" before presenting.
- A3. **Notch app** — chooses the render surface (notch vs floating), honors the suppression toggle.

## Key Flows

- F1. **Non-notch user sees their points**
  - **Trigger:** A meeting's start time arrives on a Mac with no notch (or browse is opened there).
  - **Actors:** A3, A1
  - **Steps:** The app detects no notch screen exists and renders the peek as a floating rounded panel at top-center, below the menu bar; the user reads/checks off/edits exactly as a notch user would.
  - **Outcome:** Full functionality on non-notch hardware, with no menu-bar overlap.
  - **Covered by:** R1, R2, R3, R5

- F2. **Hide before presenting**
  - **Trigger:** The user is about to share their screen.
  - **Actors:** A1, A3
  - **Steps:** The user flips "Hide while sharing" (menu item / hotkey). The peek hides and stays hidden — meetings that fire are suppressed — until the user flips it back, which resurfaces the still-active meeting.
  - **Outcome:** Prepared points never appear in the share.
  - **Covered by:** R6, R7, R8, R10

## Requirements

**Non-notch fallback**

- R1. When no connected screen has a notch, the peek renders as a floating rounded panel at top-center of the main screen, positioned below the menu bar so it never overlaps menu-bar items. Plain rounded corners; the notch "T-shape" does not apply.
- R2. When any connected screen has a notch, the peek renders on that notch screen exactly as today. The floating fallback engages only when no screen has a notch.
- R3. All peek behavior works identically in the floating fallback: browse navigation (‹ ›), check-off, quick-add, inline edit, remove, the "now" badge, and show/dismiss motion.
- R4. Placement is re-evaluated on display reconfiguration (connect/disconnect, resolution/arrangement change).
- R5. Hover-to-open browse is notch-only; on the floating fallback there is no notch to hover, so browse opens via the "Review meetings…" menu item. The live peek still appears automatically at meeting times.

**Hide while sharing**

- R6. A "Hide while sharing" control (menu-bar item; a global hotkey is a nice-to-have, see Outstanding Questions) toggles peek suppression.
- R7. While suppression is on: no peek appears on a meeting trigger, any currently-shown peek hides, and browse cannot be opened.
- R8. While suppression is on and a meeting fires, that meeting is not shown; toggling suppression off resurfaces the meeting if it is still the active/current one.
- R9. The toggle is a session control: it defaults to off and resets to off on relaunch (not persisted).
- R10. The menu reflects the toggle's state (e.g., a checkmark) so the user can tell at a glance whether suppression is active.

## Acceptance Examples

- AE1. **Covers R1, R2.** **Given** a Mac with no notch on any display, **when** a meeting fires, **then** the peek appears as a floating rounded panel below the menu bar with no menu-bar items covered; **and** on a notch Mac the peek renders on the notch as before.
- AE2. **Covers R3, R5.** **Given** the floating fallback is showing, **when** the user pages ‹ ›, checks off, edits, and quick-adds, **then** all behave as on the notch; **and** opening browse uses the "Review meetings…" menu item (hovering does nothing).
- AE3. **Covers R6, R7, R8.** **Given** a live peek is showing, **when** the user toggles "Hide while sharing" on, **then** the peek hides and a subsequent meeting trigger shows nothing; **when** the user toggles it off, **then** the still-active meeting resurfaces.
- AE4. **Covers R9, R10.** **Given** suppression was left on, **when** the app relaunches, **then** suppression is off and the menu shows it as off.

## Scope Boundaries

### Deferred for later
- **Automatic** screen-share/recording detection (the manual toggle is the reliable core; auto-detect can layer on if a dependable signal emerges).
- A global hotkey for the toggle (menu item ships first; hotkey is a nice-to-have).
- Richer external-display routing for notch-laptop users (e.g., choosing to show the peek on an external display while a notch screen is also connected).

### Outside this product's identity
- Generic Focus/DND suppression — reframed away; the peek isn't ambient, so it added little.
- Calendar/meeting-platform integration, transcription, full management GUI, sync/mobile/team (unchanged from prior scope).

## Dependencies / Assumptions

- Builds on the existing peek surface and `NotchGeometry.targetScreen()` (which already prefers a notch screen) — the floating fallback is a placement/shape variant of the same peek, not a new surface.
- The best-effort capture exclusion (`sharingType = .none`) still applies to the floating fallback; the "Hide while sharing" toggle is the reliable layer on top and needs **no** capture-detection API.
- Assumes "below the menu bar, top-center" is an acceptable resting position for the floating fallback (no notch gap exists to tuck into on non-notch displays).

## Outstanding Questions

### Deferred to planning
- Exact floating-pill offset below the menu bar, and whether it uses the existing concave-top `NotchShape` or a plain rounded rectangle on non-notch displays.
- Whether to ship a global hotkey for "Hide while sharing" in v1 or defer it (menu item is the baseline).
- Whether suppression should also change the menu-bar status icon (beyond the menu checkmark) as an at-a-glance "currently hidden" indicator.
- Behavior if a notch screen is disconnected *while* a peek is showing (re-home to the floating fallback mid-session vs. on next trigger).
