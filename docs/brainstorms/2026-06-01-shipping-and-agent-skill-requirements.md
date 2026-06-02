---
date: 2026-06-01
topic: shipping-and-agent-skill
tier: deep-product
---

# Shipping MeetingGenie + the Portable Agent Skill — Requirements

## Summary

A distribution + agent-skill layer that turns MeetingGenie from a build-from-source project into an installable, self-updating product reachable from **any agent surface that can run a shell**. Five deliverables: (1) a signed/notarized `.app`, (2) a Homebrew cask in a custom tap that installs the app and puts `notch` on `PATH`, (3) a **portable, surface-agnostic agent skill** that bootstraps the install and documents the CLI, (4) a landing page, and (5) the release plumbing that ties them together. The shipping choices carry the product's privacy-first, no-integrations identity (no telemetry, local-only) into how it's distributed.

## Problem Frame

MeetingGenie works but cannot be *had* by anyone but a developer who clones the repo and runs `swift run`. Two gaps block real adoption:

- **No install path.** The app is a raw SwiftPM executable — no `.app` bundle, icon, code-signing, notarization, update mechanism, or delivery channel. An end user has no way to install or keep it current, and Gatekeeper would block an unsigned build.
- **No agent skill.** The whole premise is that agents write the talking points, but there's no artifact that *teaches* an agent how. The `notch` CLI exists; the instruction layer that makes it discoverable and usable from an arbitrary agent surface does not.

The bet: package once for the lowest common denominator — a shell — rather than chasing per-surface integrations. Any agent that can run a command and read a file can drive MeetingGenie, so a single portable skill plus a Homebrew-installed CLI reaches today's surfaces *and* whatever surfaces appear next, without per-surface maintenance.

## Actors

- **A1. End user** — installs MeetingGenie (typically via one `brew` command), runs the menu-bar app, sees the peek, receives auto-updates.
- **A2. Agent** — any shell-capable coding/work agent (Claude Code, Codex, and others). Reads the portable skill, ensures `notch` is installed, writes meeting points/titles via the CLI.
- **A3. Maintainer** — cuts a release: builds, Developer ID-signs, notarizes + staples, publishes the artifact, updates the Sparkle appcast, and bumps the cask.

## Key Flows

- **F1. First-run install (A1/A2)**
  - **Trigger:** Someone wants MeetingGenie on a Mac.
  - **Steps:** `brew tap` the custom tap → `brew install --cask meetinggenie` → the notarized `.app` lands in `/Applications` and `notch` is symlinked onto `PATH` → launch the app (menu-bar accessory).
  - **Outcome:** A running notch app + a working `notch` CLI, Gatekeeper-clean.
  - **Covers:** R1, R3, R4

- **F2. Agent bootstrap on a fresh surface (A2)**
  - **Trigger:** An agent is asked to prep talking points and has the skill text.
  - **Steps:** Agent reads the portable skill → checks for `notch` → if absent, runs the documented `brew install` → confirms the app is present → writes points/titles with the documented verbs.
  - **Outcome:** Points appear at the user's notch with zero bespoke per-surface setup.
  - **Covers:** R9, R10, R11, R13

- **F3. Auto-update (A1)**
  - **Trigger:** A newer release exists.
  - **Steps:** The app's Sparkle updater checks the appcast in the background → notifies the user → one-click installs the signed update.
  - **Outcome:** The user stays current without reinstalling.
  - **Covers:** R6, R7

- **F4. Release (A3)**
  - **Trigger:** A change is ready to ship.
  - **Steps:** Build → Developer ID sign → notarize + staple → publish release artifact → add appcast entry → bump cask version/checksum.
  - **Outcome:** Both Sparkle and Homebrew users converge on the new version.
  - **Covers:** R5, R17

## Requirements

### App packaging & signing
- **R1** — The app ships as a notarized `.app` (Developer ID-signed, hardened runtime, stapled) so Gatekeeper opens it without warnings.
- **R2** — The bundle has an app icon and runs as a menu-bar accessory (no Dock icon), preserving today's `setActivationPolicy(.accessory)` behavior.
- **R3** — The `notch` CLI is distributed with the app and placed on `PATH` by the cask, versioned in lockstep with the app.

### Homebrew
- **R4** — A custom Homebrew tap hosts a cask; `brew install --cask <tap>/meetinggenie` installs the notarized app and exposes `notch`.
- **R5** — Each release bumps the cask (version + checksum) so `brew upgrade --cask` works for cask users.

### Auto-update
- **R6** — The app self-updates via Sparkle: background appcast check → user-facing notification → one-click install.
- **R7** — Updates are cryptographically verified (Sparkle EdDSA signature + Developer ID); the appcast is hosted (landing page / GitHub Releases).
- **R8** — The Sparkle update check is the **only** network call the app makes; the app remains otherwise local-only, consistent with the privacy-first identity.

### Portable agent skill
- **R9** — A single portable skill doc is the canonical agent instruction, fetchable by raw URL **before** the CLI is installed (so it can instruct the install).
- **R10** — The skill's bootstrap teaches the agent to detect `notch`, install it via the documented `brew` command if absent, and verify the app is present.
- **R11** — The skill documents the verb surface (`add`/`title`/`add-point`/`remove-point`/`remove`/`list`/`clear`), time formats, the data model (times + notes + title only — no calendar/integrations), and **when** to use it (writing prepared talking points the user sees at the notch).
- **R12** — `notch skill` emits the current verb reference (and optionally installs the skill doc), so the instructions never drift from the installed binary.
- **R13** — The skill works on any surface that can run shell commands and read an instruction file; no surface-specific code paths.

### Landing page
- **R14** — A landing page states what MeetingGenie is, shows the one-line install, surfaces the skill, and shows the peek in action (demo).
- **R15** — The landing page hosts or links the Sparkle appcast and release downloads.
- **R16** — The landing page carries no analytics/tracking, consistent with the privacy-first identity.

### Release plumbing
- **R17** — A repeatable, documented release process exists: build → sign → notarize + staple → publish → appcast entry → cask bump (manual is acceptable for v1; automation is deferred).

## Acceptance Examples

- **AE1. Covers R1, R3, R4.** Given a clean Mac, when the user runs the `brew install` command, then the app installs, opens with no Gatekeeper warning, and `notch` resolves on `PATH`.
- **AE2. Covers R9, R10, R13.** Given an agent on a shell-capable surface with the skill text and a machine where `notch` is absent, when it follows the skill, then it runs the documented install and goes on to write points successfully.
- **AE3. Covers R6, R7.** Given a newer release with an appcast entry, when the running app checks for updates, then the user is notified and installs the signed update in one click.
- **AE4. Covers R12.** Given the app installed, when an agent runs `notch skill`, then it prints a verb reference that matches the installed binary's actual commands.
- **AE5. Covers R8, R16.** Given the shipped app and landing page, when network activity is inspected, then the app's only call is the Sparkle update check and the landing page sets no tracking/analytics.

## Scope Boundaries

### Deferred for later
- Submitting the cask to **homebrew-cask core** (start with a custom tap; core submission has its own review bar).
- A secondary **notarized DMG** download for users who don't use Homebrew.
- **Release automation** (e.g., GitHub Actions notarization pipeline) — v1 may cut releases manually.
- **Thin per-surface wrappers** (a Claude Code plugin entry, a Codex `AGENTS.md` pointer) that point at the canonical skill — a later convenience layer if a specific surface warrants it.

### Outside this product's identity
- **Mac App Store** distribution — the global mouse monitor + screen-saver-level overlay conflict with the sandbox, and the Store can't expose `notch` on `PATH`.
- **Per-surface native integrations** as the primary strategy — betting on specific surfaces (Cowork/Hermes/OpenClaw) contradicts the durable, shell-LCD approach.
- **Analytics, telemetry, accounts, or integrations** on the app or landing page — the product is privacy-first and local-only; shipping must not smuggle tracking in.

## Dependencies / Assumptions

- **Apple Developer ID** ($99/yr) for Developer ID signing + notarization — a hard prerequisite gating the cask, Sparkle, and Gatekeeper-clean install. **Assumed available.**
- **Sparkle** framework added as an app dependency (appcast feed + EdDSA update-signing keys).
- A **hosting location** for the appcast + landing page + release artifacts (e.g., GitHub Pages + GitHub Releases).
- **Homebrew** present on the user's machine for the cask path; the skill's bootstrap assumes `brew` or guides installing it.
- The app's **GUI runtime is still pending on-device verification** (per `README.md`); shipping assumes the running app is validated first — a notarized build of a broken GUI is worse than no ship.

## Outstanding Questions

### Deferred to planning
- Exact **tap name, bundle identifier, and app/product name casing**.
- Whether `notch skill` only prints the doc or also supports `--install <path>` into a surface's skill location.
- **Landing-page tech/host** (static GitHub Pages vs hosted) and how the demo asset is produced (the GUI must be on-device-verified to capture it).
- Whether to add the secondary **notarized DMG** channel in v1 or strictly later.
- **Manual vs automated** notarization for the first release.
