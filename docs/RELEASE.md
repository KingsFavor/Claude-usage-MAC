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
| `DEVELOPER_ID_CERT_P12` | Base64 of your exported **Developer ID Application** cert (`.p12`, includes private key) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password you set when exporting the `.p12` |
| `DEVELOPER_ID_APPLICATION` | Full identity string, e.g. `Developer ID Application: Kwonwoo Lyu (4S9VPFZ465)` |
| `KEYCHAIN_PASSWORD` | Any random string — password for the throwaway CI keychain |
| `NOTARY_API_KEY_P8` | Contents of the App Store Connect API key `.p8` file (paste the whole PEM) |
| `NOTARY_API_KEY_ID` | The key's **Key ID** |
| `NOTARY_API_ISSUER_ID` | The API key **Issuer ID** |
| `HOMEBREW_TAP_TOKEN` | A PAT (fine-grained: `contents:write` on `KingsFavor/homebrew-tap`) so CI can push the cask |

### 2. Export the Developer ID certificate

From Keychain Access → your **Developer ID Application** cert → right-click →
Export → `.p12`. Then base64-encode it for the secret:

```bash
base64 -i DeveloperID.p12 | pbcopy   # paste into DEVELOPER_ID_CERT_P12
```

### 3. Create the App Store Connect API key

App Store Connect → Users and Access → Integrations → App Store Connect API →
generate a key with the **Developer** role (Access: "Developer" is enough for
notarization). Download the `.p8` (one chance only). You get:

- **Issuer ID** → `NOTARY_API_ISSUER_ID`
- **Key ID** → `NOTARY_API_KEY_ID`
- the `.p8` file contents → `NOTARY_API_KEY_P8`

### 4. Homebrew tap

The cask lives in **`KingsFavor/homebrew-tap`** (`Casks/claude-usage.rb`). CI
rewrites and pushes it on every release, so users install with:

```bash
brew install --cask kingsfavor/tap/claude-usage
# upgrades:
brew upgrade --cask claude-usage
```

## Local build

`packaging/build.sh` still works on a laptop. It notarizes automatically when a
`notarytool` keychain profile named `claude-usage` exists:

```bash
xcrun notarytool store-credentials claude-usage \
  --apple-id "<APPLE_ID>" --team-id 4S9VPFZ465
./packaging/build.sh
```

Override behavior with `VERSION=1.2.3 NOTARIZE=0 ./packaging/build.sh`.
