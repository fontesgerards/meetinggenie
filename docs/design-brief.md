# MeetingGenie — Visual Design Brief

A baseline description of the app's current look & feel, as a starting point for
refining the visual design. The implementation lives in
`Sources/MeetingGenieApp/` — `PeekView.swift` (content), `NotchShape.swift`
(silhouette), `NotchGeometry.swift` (placement), `PeekPanel.swift` (window).

## What it is

A macOS menu-bar utility that, during a meeting, drops a small "peek" of your
prepared talking points down from the notch. It's an ambient glance surface, not
a window — calm, non-interrupting, always on top, and it never steals keyboard
focus.

## The surface — a "notch peek"

- Anchored flush to the **top-center of the screen**, visually continuous with
  the MacBook notch — it reads as the hardware notch *growing downward*.
- **Shape:** a custom "T" / mushroom silhouette (`NotchTShape`). Within the
  menu-bar band at the very top it is only as wide as the **physical notch**
  (centered in the menu bar's empty gap, so it never covers menu-bar items);
  just below the band it **flares outward through concave shoulders** into a
  wider rounded panel. Bottom corners are convex (~20pt); the shoulder flares
  are concave (~12pt). (A simpler `NotchShape` with concave top corners is the
  fallback on non-notch displays.)
- **Background:** solid black (`Color.black`) to blend into the notch. No border
  or shadow currently.
- **Width:** ~360pt body; notch tab ~240pt. Height grows with the point count.

## Content & layout (top → bottom, left-aligned)

- A muted **time label** (e.g. "1:51pm") at the top of the body, below the notch.
- A **vertical list of talking points**, one row each: a circle icon + the text.
  - Unchecked: hollow circle + white text.
  - Checked: green filled checkmark + strikethrough + dimmed text.
- An **"Add point"** affordance (`plus.circle`) below the list; tapping it
  reveals an inline rounded text field.
- A **dismiss control** (`xmark.circle.fill`) pinned top-right, deliberately
  separate from the list so a stray tap can't dismiss it.

## Type & color (current — minimal)

- White text on black; secondary elements ~50–55% white opacity; green for the
  checked state. System font, caption/caption2 sizes. ~18pt horizontal padding;
  content offset below the notch band.

## States

- **Idle:** nothing visible — the notch shows the macOS default.
- **Showing:** the peek with the list.
- **Quick-add:** an inline text field replaces the + button.
- Checked vs. unchecked rows as above.

## Menu bar

A single note icon (`note.text`) with a menu: "Re-open last meeting's points"
and "Quit".

## Design system (shipped)

The look & feel is now formalized in `docs/design-system/` (tokens + the system
README, from the Claude Design handoff) and implemented in `PeekView.swift` /
`PeekController.swift`:

- **Type & color:** SF Pro at caption/caption2; the white-on-black opacity
  ladder (1.0 / 0.55 / 0.50 / 0.45 / 0.40); `#30D158` green for the checked state
  only.
- **Quick-add field card:** `0.08` white fill, `0.10` hairline border (→ `0.25`
  on focus), `6pt` radius, `0.35` placeholder.
- **Motion** (calm ease-out `cubic-bezier(0.32,0.72,0,1)`, respects Reduce
  Motion): show/dismiss slide+fade (~220ms); check-off tick with a ~1.06
  checkmark scale-punch + dim/strike (~140ms); quick-add reveal crossfade.
- **Hover/press:** hover raises icons one opacity rung; press gives a quiet
  shrink (the check-off is the primary press target).

## Still open / deferred

- A **non-notch fallback** surface (floating panel) — deferred product scope.
- **Logo / wordmark** — none exists; if marketing needs one, design it inside
  these constraints (monochrome, the notch silhouette as a motif).

## Constraints to respect

- Stays **black-on-notch** and **flush at the top**.
- The menu-bar band must remain **notch-width only** (T-shape) so it never
  covers menu items.
- Must **not steal keyboard focus** (quick-add only takes focus on deliberate
  activation).
- Privacy-first, local-only, agent-written content; the peek is shown over the
  call (it may appear in a full-display screen-share — accepted, best-effort).
