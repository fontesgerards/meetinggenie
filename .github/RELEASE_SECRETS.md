# Release CI — required secrets

`.github/workflows/release.yml` cuts a signed, notarized release when you push a
`vX.Y.Z` tag. It needs the secrets below set in **Settings → Secrets and
variables → Actions** (ideally scoped to a protected `release` environment).

> **Security posture.** These move your signing identity off your laptop into
> GitHub. Mitigations baked in: an App Store Connect API key (scoped +
> revocable, not your account password), strict `vX.Y.Z` tag validation (no
> shell injection), and `env:`-only interpolation. **Recommended:** create a
> `release` environment (Settings → Environments) with **required reviewers**,
> so a human approves each release job. Revoke any secret independently if leaked.

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | base64 of your exported Developer ID Application cert **+ private key** (`.p12`) |
| `DEVELOPER_ID_CERT_PASSWORD` | the password you set when exporting the `.p12` |
| `AC_API_KEY_ID` | App Store Connect API **Key ID** |
| `AC_API_ISSUER_ID` | App Store Connect API **Issuer ID** |
| `AC_API_KEY_P8_BASE64` | base64 of the downloaded `AuthKey_XXXX.p8` |
| `SPARKLE_ED_PRIVATE_KEY` | the exported Sparkle EdDSA private key (string) |
| `TAP_REPO_TOKEN` | fine-grained PAT with **Contents: read/write** on `fontesgerards/homebrew-meetinggenie-tap` |

## How to produce each

**Developer ID cert (`.p12`)** — Keychain Access → find *"Developer ID
Application: … (R47R74J893)"* → right-click → **Export** → save a `.p12` with a
password. Then pipe it straight into the env-scoped secret (value never hits the
clipboard or disk; delete the `.p12` afterward — the Keychain keeps the original):
```sh
base64 -i /path/to/your.p12 | tr -d '\n' \
  | gh secret set DEVELOPER_ID_CERT_P12_BASE64 --env release -R fontesgerards/meetinggenie
gh secret set DEVELOPER_ID_CERT_PASSWORD --env release -R fontesgerards/meetinggenie  # paste export password
```

**App Store Connect API key** — App Store Connect → **Users and Access →
Integrations → Keys** → generate a key (Developer access is enough for
notarization). Download `AuthKey_XXXX.p8` (one-time). The page shows the **Key
ID** and, at top, the **Issuer ID**.
```sh
gh secret set AC_API_KEY_ID    --env release -R fontesgerards/meetinggenie   # paste Key ID (in the .p8 filename)
gh secret set AC_API_ISSUER_ID --env release -R fontesgerards/meetinggenie   # paste Issuer ID (UUID atop the Keys tab)
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' \
  | gh secret set AC_API_KEY_P8_BASE64 --env release -R fontesgerards/meetinggenie
```

**Sparkle EdDSA private key** — export the key `generate_keys` stored in your
login keychain:
```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
gh secret set SPARKLE_ED_PRIVATE_KEY --env release -R fontesgerards/meetinggenie < sparkle_private_key
rm sparkle_private_key                        # don't leave it on disk
```
(The public half is already in `packaging/Info.plist` as `SUPublicEDKey` — don't change it, or existing installs can't verify updates.)

**Tap token** — GitHub → Settings → Developer settings → **Fine-grained tokens**
→ new token, repository access = `homebrew-meetinggenie-tap`, permission
**Contents: read and write**.

## Cutting a release

```sh
git tag v0.1.1 && git push origin v0.1.1
```
The workflow builds → signs → notarizes → DMG → appcast → GitHub Release →
pushes `appcast.xml` to `gh-pages` → bumps the cask. Existing installs auto-update.
