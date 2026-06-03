# Releasing MeetingGenie

Releases are **CI-driven**. You push a version tag, approve one gate, and the
workflow does the rest: universal build → sign → notarize → DMG → GitHub
Release → Sparkle appcast on `gh-pages` → Homebrew cask bump. Existing installs
then auto-update via Sparkle (or `brew upgrade`).

## TL;DR

```sh
git tag vX.Y.Z && git push origin vX.Y.Z
```

Then open the run in the **Actions** tab → **Review deployments** → approve the
`release` environment. That's it.

## One-time setup (already done for this repo)

- The 7 signing/notary/tap secrets live in the **`release` environment** (not
  repo-level). See `.github/RELEASE_SECRETS.md` to (re)produce any of them.
- The `release` environment has a **required reviewer**, which is what creates
  the approval gate. Settings → Environments → `release`.

## What the workflow does (`.github/workflows/release.yml`)

Triggered by a `v*` tag. The version is derived **from the tag** — nothing to
bump by hand (Info.plist short version = the tag, build number = git commit
count, cask + appcast enclosure = the tag).

1. Validate the tag is strict `vX.Y.Z` (rejects anything else — injection guard)
2. Import the Developer ID cert into an ephemeral keychain
3. Write the App Store Connect API key
4. Resolve Sparkle
5. **Build, sign, notarize, DMG, appcast** — `package-app.sh` → `sign-and-notarize.sh` → `make-dmg.sh` → `update-appcast.sh`
6. Create the GitHub Release and upload the DMG
7. Push `appcast.xml` to `gh-pages`
8. Bump `version` + `sha256` in the `homebrew-meetinggenie-tap` cask

The whole job is gated on the `release` environment, so step 1–8 only run
**after** you approve — your abort point before any signing material is used.

## Verify after it goes green

```sh
gh release view vX.Y.Z                                            # DMG attached, not draft
curl -fsSL https://fontesgerards.github.io/meetinggenie/appcast.xml | grep shortVersionString
curl -fsSL https://raw.githubusercontent.com/fontesgerards/homebrew-meetinggenie-tap/HEAD/Casks/meetinggenie.rb | grep -E 'version|sha256'
```

All three should show the new version, and the appcast enclosure URL should
point at the release DMG.

## Local dry run (no shipping)

To prove the build/bundle before tagging — produces `build/MeetingGenie.app`
(universal), signs nothing, ships nothing:

```sh
./scripts/package-app.sh X.Y.Z          # universal (arm64+x86_64) bundle
./scripts/package-app.sh X.Y.Z --native # host-arch only, faster, for quick GUI checks
```

## Gotchas

- **Tag format is strict.** The workflow only accepts `vMAJOR.MINOR.PATCH`
  (e.g. `v0.1.3`). Pre-release/suffix tags are rejected by design.
- **Never `swift build --arch … --arch …`.** That routes through xcbuild, which
  is broken on Xcode 16.x for this package's `swiftLanguageMode(.v5)`
  (`given: [5], supported: []`, `Unexpected duplicate tasks`). `package-app.sh`
  builds each arch with the native build system and `lipo`s them instead.
- **A failed run publishes nothing** (no Release, no appcast, no cask change),
  so a re-run is safe. To retry the same version, prefer cutting the **next
  patch** (`vX.Y.(Z+1)`) over force-moving a tag — moving a remote tag is a
  destructive git op and a published tag must never be rewritten.
- **Setting file-derived secrets:** `base64 -i <file> | gh secret set …` must be
  run where the shell can actually read the file. macOS TCC blocks sandboxed/
  agent shells from `~/Documents` and `~/Downloads`; a silently-empty secret is
  the result. Run it in a real Terminal with folder access (and verify the
  base64 length is non-zero), per `.github/RELEASE_SECRETS.md`.
