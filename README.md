# MeetingGenie

A privacy-first macOS notch app that surfaces your prepared meeting talking
points as a calm, always-on-top "peek" during a call. Points are written
primarily by AI agents through the `notch` CLI; the only data ever stored is
times and note text — no calendar, no integrations.

See [`docs/brainstorms/`](docs/brainstorms/) for the requirements and
[`docs/plans/`](docs/plans/) for the implementation plan.

## Layout

Everything builds with SwiftPM (no Xcode project required):

| Product | What it is |
|---|---|
| `NotchCore` (library) | Model, JSON store (atomic, `0600`, backup-excluded), validation/sanitization, file watcher. AppKit-free and unit-tested. |
| `notch` (executable) | The agent-facing CLI — the sole write path in v1. |
| `MeetingGenie` (executable) | The menu-bar agent app + notch peek (runs as an accessory via `setActivationPolicy(.accessory)`). |
| `overlay-spike` (executable) | The U1 feasibility prototype (throwaway). |
| `selfcheck` (executable) | CLT-runnable smoke verification of `NotchCore`. |

## Build & verify

```bash
swift build              # builds every product
swift run selfcheck      # runs the core verification harness (22 checks)
```

The full test suite lives in `Tests/NotchCoreTests` using **Swift Testing**
(`import Testing`). It runs in **Xcode** or any toolchain that bundles the
Testing/XCTest frameworks; the Command Line Tools-only toolchain does not ship
them, which is why `selfcheck` exists as a CLT-runnable equivalent.

## Using the CLI

```bash
notch add 2:00pm "raise the budget" "ask about Q3 timeline"
notch add-point 2:00pm "mention the new hire"
notch list
notch remove-point 2:00pm 1
notch remove 2:00pm
notch clear
```

The store lives at `~/Library/Application Support/MeetingGenie/store.json`.

## Run the app

```bash
swift run MeetingGenie
```

It installs a menu-bar item (no Dock icon). When an entry's start time arrives,
the peek appears at the notch. Re-open a dismissed entry from the menu-bar item.

## ⚠️ Status — what is and isn't verified

The **core and CLI are built and verified** here (`selfcheck` green, CLI
smoke-tested end-to-end). The **GUI compiles and links**, but its *runtime
behavior cannot be verified in a headless / Command Line Tools environment* and
needs manual testing on a Mac with a notch:

- **U1 gate (run this first).** `swift run overlay-spike`, enter a native
  fullscreen Zoom/Meet call, and confirm the banner stays on top. Then run the
  capture matrix (share-entire-screen vs share-a-window vs screen recording) on
  the target macOS (26.x). Per research, expect: visible above the call +
  hidden from window-share/legacy, but **likely visible in full-display
  screen-share on macOS 15+/26** — this leak is accepted (R24 is best-effort).
- **Quick-add focus & clicks (needs verification).** SwiftUI controls hosted in
  a non-activating `NSPanel` may need `acceptsFirstMouse` / explicit key
  handling to register taps; the focus handoff for quick-add is implemented but
  unverified. See the plan's review notes.

## Deviation from the plan

The plan's Output Structure assumed an Xcode project for the app target. This
build instead ships the app as a **SwiftPM executable** (programmatic
menu-bar agent) so it builds without Xcode and compiles in CI. Functionally
equivalent for v1; revisit if a signed/notarized `.app` bundle is needed.
