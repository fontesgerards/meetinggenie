# CLAUDE.md

Guidance for AI agents (and humans) working in this repo. Keep it short and
high-signal; prefer fixing the code/docs over growing this file.

## What MeetingGenie is

A privacy-first macOS **notch** menu-bar app. It surfaces prepared meeting
talking points as a calm "peek" at the MacBook notch (with a floating fallback
on non-notch displays). Points are written primarily by **AI agents** via the
local `notch` CLI. Only times + note text (+ optional title) are stored — no
calendar, no integrations, no network except the Sparkle update check. The
store is `~/Library/Application Support/MeetingGenie/store.json` (atomic, `0600`,
backup-excluded).

## Build & verify

SwiftPM only — **there is no Xcode project**.

```sh
swift build                 # builds every product
swift run selfcheck         # 22-check core verification harness
swift run MeetingGenie      # runs the menu-bar app (accessory, no Dock icon)
```

- **Tests:** `Tests/NotchCoreTests` use Swift Testing (`import Testing`), which
  needs the Xcode/Testing toolchain. `selfcheck` exists as a Command-Line-
  Tools-runnable equivalent because CLT-only toolchains don't ship Testing.
- Targets: `NotchCore` (AppKit-free model/store/validation), `notch` (the agent
  CLI — the sole write path in v1), `MeetingGenie` (the app), `overlay-spike`
  (throwaway U1 prototype), `selfcheck`.
- Package: `swift-tools-version: 6.0`, `.macOS(.v13)`, targets pinned to
  `swiftLanguageMode(.v5)`.

## Packaging gotchas (learned the hard way)

- **Never `swift build --arch arm64 --arch x86_64`.** That routes through
  xcbuild, which is broken on Xcode 16.x for this package's
  `swiftLanguageMode(.v5)` — you get `Swift language versions … (given: [5],
  supported: [])` and `Unexpected duplicate tasks`. `scripts/package-app.sh`
  builds each arch with the **native** build system (`-Xswiftc -target` into
  separate `--scratch-path` dirs) and `lipo`s the slices. `swift run`/`selfcheck`
  are fine because they use the native build system, not xcbuild.
- **SwiftPM emits no `.app`** — `package-app.sh` hand-assembles the bundle:
  `MeetingGenie` → `Contents/MacOS`, `notch` → `Contents/Resources` (the cask
  symlinks it onto PATH), Sparkle into `Contents/Frameworks`.
- **The `@loader_path/../Frameworks` rpath is required** (Package.swift linker
  flag). Without it the bundled app can't load Sparkle.framework at runtime —
  works under `swift run`, crashes when bundled.
- **Signing is inside-out, never `--deep`**, with `--options runtime --timestamp`
  (`scripts/sign-and-notarize.sh`, identity auto-detected — not hardcoded).
- Bundle id `com.fontesgerards.meetinggenie`, `LSUIElement` (accessory app).
  `SUFeedURL`/`SUPublicEDKey` in `packaging/Info.plist` drive Sparkle — do not
  change the public key or existing installs can't verify updates.

## Releasing

CI-driven: `git tag vX.Y.Z && git push`, then approve the `release` environment
gate. Full runbook: **`scripts/RELEASING.md`**. Secrets: `.github/RELEASE_SECRETS.md`.

## Working norms in this repo

- **One PR at a time in the merge path.** Once a PR is opened/approved, put
  follow-on work on a **fresh branch**, never push more commits onto the
  about-to-merge branch — that strands the later commits when the original PR
  merges. (This has bitten before.)
- **PRs get an automated review** from gemini-code-assist. Read its comments,
  apply the valid ones, and reply on threads explaining any you decline (with
  evidence — e.g. it has misflagged non-deprecated APIs and suggested unsafe
  `gh` flag removals).
- **`docs/` is local-only** — gitignored and purged from history (brainstorms,
  plans, design, the landing-page source). The live landing + appcast are served
  from the **`gh-pages`** branch, not `docs/`.
- Use **repo-relative paths** in committed docs, never absolute machine paths,
  and don't commit real key IDs / local paths into this public repo.
