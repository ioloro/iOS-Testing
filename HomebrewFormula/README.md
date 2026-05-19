# Homebrew formula

`iostesting.rb` is the Homebrew formula for the `iostesting` CLI.

## Install from this repo as a tap

Until a release is cut and a dedicated tap repo exists, users can install directly from this checkout:

```bash
brew install --HEAD ./HomebrewFormula/iostesting.rb
```

This builds from `main` via `swift build -c release` in the `cli/` directory.

## Release flow (when ready)

1. Tag the version: `git tag v2.0.0 && git push --tags`.
2. Create a GitHub Release with the tag; GitHub auto-generates a tarball.
3. Run `shasum -a 256` on the tarball.
4. Edit `iostesting.rb`: uncomment + fill in `url`, `sha256`, `version`.
5. Run `scripts/check-version-drift.sh` to confirm `package.json`, `SKILL.md`, `CHANGELOG.md`, and `RootCommand.swift` agree.
6. Commit the formula update.
7. (Optional) Mirror to a dedicated `ioloro/homebrew-tap` repo so users can `brew tap ioloro/tap && brew install iostesting` without referencing this repo's path.

## FB framework packaging (2.0.0+)

Since 2.0.0 the formula needs to ship the four Meta-licensed `.framework` bundles alongside the binary. The `install` step:

- `depends_on macos: :sequoia` (or whichever Xcode SPI compat floor matches — currently tested on macOS 26.4)
- Run `scripts/fetch-frameworks.sh <pinned-idb-sha>` first to clone facebook/idb, apply our three compat patches (xcode-select fallback, HID clientClass, DYLD env for Swift Testing), and build the frameworks
- `prefix.install "cli/Frameworks"` so `Frameworks/` lands next to `bin/iostesting`
- The binary's rpath is already `@executable_path/Frameworks`, so dyld resolves correctly once the layout matches
