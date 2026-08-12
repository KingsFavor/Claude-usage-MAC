# Release & distribution

Releases are fully automated. Push a version tag and GitHub Actions builds,
Developer-ID signs, **notarizes + staples**, publishes a GitHub Release with the
DMG, and updates the Homebrew cask.

```bash
# 1. Bump the version in packaging/Info.plist (CFBundleShortVersionString)
# 2. Commit, then tag and push:
git tag v1.2.3
git push origin v1.2.3
```

`workflow_dispatch` (Actions → Release → Run workflow) also works for a manual
build if you pass the version.

## One-time setup

### 1. GitHub Actions secrets (repo → Settings → Secrets → Actions)

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Base64 of your exported **Developer ID Application** cert (`.p12`, includes private key) |
| `MACOS_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12` |
| `MACOS_SIGN_IDENTITY` | Full identity string, e.g. `Developer ID Application: Kwonwoo Lyu (4S9VPFZ465)` |
| `NOTARY_KEY_BASE64` | **Base64** of the App Store Connect API key `.p8` file |
| `NOTARY_KEY_ID` | The key's **Key ID** |
| `NOTARY_ISSUER_ID` | The API key **Issuer ID** |
| `TAP_GITHUB_TOKEN` | A PAT (fine-grained: `contents:write` on `KingsFavor/homebrew-tap`) so CI can push the cask |

> The CI keychain password is generated per-run inside the workflow — no secret needed.

### 2. Export the Developer ID certificate

From Keychain Access → your **Developer ID Application** cert → right-click →
Export → `.p12`. Then base64-encode it for the secret:

```bash
base64 -i DeveloperID.p12 | pbcopy   # paste into MACOS_CERTIFICATE_BASE64
```

### 3. Create the App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API →
generate a key with the **Developer** role (Access: "Developer" is enough for
notarization). Download the `.p8` (one chance only). You get:

- **Issuer ID** → `NOTARY_ISSUER_ID`
- **Key ID** → `NOTARY_KEY_ID`
- the `.p8` file, base64-encoded → `NOTARY_KEY_BASE64`
  (`base64 -i AuthKey_XXXX.p8 | pbcopy`)

### 4. Homebrew tap

The cask lives in **`KingsFavor/homebrew-tap`** (`Casks/claude-usage.rb`). CI
rewrites and pushes it on every release, so users install with:

```bash
brew install --cask kingsfavor/tap/claude-usage
# upgrades:
brew upgrade --cask claude-usage
```

## Local build

For building, packaging, and notarizing on a laptop (without CI), see
[DEVELOPMENT.md](DEVELOPMENT.md).
