# Developer Guide

How to cut releases, sign binaries, and publish to Homebrew. Everything that needs your Apple Developer credentials lives here.

## Cutting a release

1. **Bump versions.** Edit `package.json`, `skills/ios-testing/SKILL.md` (frontmatter), `cli/Sources/iostesting/Commands/RootCommand.swift` (`version:`), and add a section to `CHANGELOG.md`. All four must match — `scripts/check-version-drift.sh` enforces this in CI.

2. **Pin the idb SHA.** Verify `scripts/fetch-frameworks.sh` builds clean against the current `main` of `facebook/idb`. If you want a fixed SHA, write it into `scripts/idb-sha` (one line). The release workflow reads from there with `dabc268` as fallback.

3. **Tag + push.** GitHub Actions handles the rest (build frameworks, sign, notarize, tarball, release):
   ```bash
   git tag v1.3.0
   git push origin v1.3.0
   ```

4. **Update the Homebrew formula.** Once the release is published, edit `HomebrewFormula/iostesting.rb`:
   - Replace the `head` block with `url`, `sha256`, `version` filled from the release.
   - Or, if you've set up a dedicated tap repo (`ioloro/homebrew-tap`), commit the formula there.

## One-time setup: signing credentials

The release workflow needs 6 GitHub Actions secrets to sign + notarize. Set them at `Settings → Secrets and variables → Actions`:

| Secret | What it is | How to get it |
|---|---|---|
| `APPLE_DEVELOPER_ID_APPLICATION` | Full identity name, e.g. `Developer ID Application: Your Name (J9F8F3PWTV)` | `security find-identity -v -p codesigning` |
| `APPLE_CERT_P12_BASE64` | The cert exported as `.p12`, then `base64`-encoded | Export from Keychain Access (right-click cert → Export) with a password; `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERT_P12_PASSWORD` | Password you set when exporting | (your choice during export) |
| `APPLE_ID` | The Apple ID email for notarytool | Your developer account email |
| `APPLE_ID_PASSWORD` | App-specific password for notarytool | https://appleid.apple.com → Sign-In → App-Specific Passwords |
| `APPLE_TEAM_ID` | 10-char team ID | The parenthesized code in your `find-identity` output |

If `APPLE_CERT_P12_BASE64` is unset, the workflow falls back to producing an **unsigned** tarball with a warning. That's useful for early testing but Gatekeeper will quarantine the binary on user machines.

## What the release workflow does

1. Checks out the repo.
2. Selects Xcode and installs `xcodegen`.
3. Runs `scripts/fetch-frameworks.sh` which clones `facebook/idb`, applies our patches (xcode-select fallback + HID clientClass mangled-name fallback + SimulatorKit loader), builds the 4 frameworks, and vendors them into `cli/Frameworks/`.
4. `swift build -c release`.
5. Signs each `.framework`'s executable + the `iostesting` binary with Developer ID Application (`--options=runtime --timestamp` for notarytool acceptance).
6. Tars the binary + Frameworks + docs into `iostesting-vX.Y.Z-macos-arm64.tar.gz`.
7. Submits to notarytool (`--wait`).
8. Creates the GitHub Release with the tarball + sha256 attached.

## Homebrew distribution

### First-time tap setup

Create a new repo `ioloro/homebrew-tap` with this structure:

```
homebrew-tap/
└── Formula/
    └── iostesting.rb
```

Copy `HomebrewFormula/iostesting.rb` into `Formula/`. Users then install:

```bash
brew tap ioloro/tap
brew install iostesting
```

### Per-release formula update

After each release, update `iostesting.rb` in the tap repo:

```ruby
url "https://github.com/ioloro/iOS-Testing/releases/download/v1.3.0/iostesting-v1.3.0-macos-arm64.tar.gz"
sha256 "<from tarball.sha256>"
version "1.3.0"
```

Then `brew test ioloro/tap/iostesting` locally to verify.

## Local development

After every `swift build`, symlink the vendored frameworks next to the binary so dyld can load them:

```bash
ln -sf "$(pwd)/cli/Frameworks" cli/.build/arm64-apple-macosx/release/Frameworks
```

For tests:

```bash
ln -sf "$(pwd)/cli/Frameworks" \
  cli/.build/arm64-apple-macosx/debug/iostestingPackageTests.xctest/Contents/MacOS/Frameworks
```

A future SwiftPM build plugin should do this automatically.

## Patches against facebook/idb

We maintain two compat patches under `scripts/patches/`:

- `idb-xcode-select-macos26.patch` — falls back to `xcode-select -p` when `/var/db/xcode_select_link` is missing (macOS 26+ default).
- `idb-hid-clientclass-macos26.patch` — adds the legacy `_TtC` Swift mangled name as a fallback for `SimDeviceLegacyHIDClient` lookup.

Both auto-apply in `scripts/fetch-frameworks.sh`. **Submit them upstream to facebook/idb** when possible so we can drop the local fork.

## Versioning policy

Versions for the skill (npm), CLI, hook, and frameworks are kept in lockstep. CI's `check-version-drift.sh` enforces this — break it and the PR fails.

Bump rules:
- **Patch** (`1.2.0 → 1.2.1`): doc fixes, bug fixes to existing commands, framework rebuilds against new idb SHA.
- **Minor** (`1.2.0 → 1.3.0`): new commands or backend methods, new skill sections.
- **Major** (`1.x → 2.0`): breaking CLI changes, removed flags, new license terms.
