# iostesting

A Swift CLI that drives iOS simulators, physical devices, and XCTest bundles. Companion to the `@ioloro/ios-testing` Claude Code skill — the skill writes the tests, this CLI runs them.

Build-tool agnostic: bring your own build (xcodebuild, swift build, Bazel, whatever). Point iostesting at the resulting `.xctest` bundle.

## Status

**v2.0.0 (current).** Two backends behind a single CLI:

- **`IOSTESTING_BACKEND=simctl` (default)** — shells out to `xcrun simctl` / `xcrun devicectl`. Works on any Mac with Xcode 14+.
- **`IOSTESTING_BACKEND=fb`** — direct linkage against the four MIT-licensed Meta frameworks (FBControlCore / FBSimulatorControl / FBDeviceControl / XCTestBootstrap). Unlocks UI automation (`tap`, `swipe`), Swift Testing bundles end-to-end, full app lifecycle via FB framework calls, NDJSON event streaming for test runs. See `scripts/fetch-frameworks.sh` and `../scripts/patches/` for the build pipeline + three macOS-26 compat patches.

`HybridBackend` wraps the two — opting into `fb` falls through to `simctl` automatically for methods not yet wired (and surfaces real bridge failures to the caller).

## Build

```bash
cd cli
swift build -c release
# binary at .build/release/iostesting
```

Requires Xcode 14+ and Swift 6 (tested on Swift 6.3 / Xcode 26.4).

## Command surface (29 leaves under 12 top-level)

### Config (eliminate boilerplate)

```
iostesting config show                                # effective config + sources
iostesting config get <key>                           # sim | bundleId
iostesting config set --sim "iPhone 17 Pro"           # project (./.iostesting/config.json)
iostesting config set --bundle-id com.example.MyApp
iostesting config set --global --sim "iPhone 17 Pro"  # ~/.config/iostesting/config.json
iostesting config reset [--global]
```

Once set, `--sim` and the bundle-id positional argument become optional on every command. Precedence: explicit arg > env var > project config > global config.

For CI without a config file: `IOSTESTING_SIM` and `IOSTESTING_BUNDLE_ID` env vars take effect immediately.

### Simulators

```
iostesting sim list [--state Booted] [--runtime "iOS 26"] [--json]
iostesting sim boot <name-or-udid>
iostesting sim shutdown <name-or-udid>
iostesting sim erase <name-or-udid>
iostesting sim create --name <n> --device-type <t> --runtime <r>
iostesting sim prune                                  # delete unavailable

iostesting sim media-add <files>...                   # photos/videos to camera roll
iostesting sim location --set "37.7749,-122.4194"     # override location
iostesting sim location --clear
iostesting sim button home|lock|siri|side|apple-pay
iostesting sim appearance light|dark
iostesting sim open-url <url>                         # universal links + custom schemes
```

### Apps (lifecycle + registry)

```
iostesting install <app-path>
iostesting uninstall <bundle-id>
iostesting launch <bundle-id> [--env KEY=VAL]... [--arg VALUE]... [--wait-for-debugger]
iostesting stop <short-id-or-bundle-or-pid>

iostesting apps list [--all] [--json]                 # registry of launched apps
iostesting apps prune                                 # drop terminated records
```

`launch` records each app to a registry at `~/Library/Application Support/iostesting/apps.json` and prints a 6-character short ID. `stop` and `logs` accept that short ID and resolve sim + bundle automatically:

```
$ iostesting launch com.example.MyApp
Launched com.example.MyApp on iPhone 17 Pro (pid 12345) [id ab12kw]

$ iostesting logs --bundle-id ab12kw      # short ID, no --sim needed
$ iostesting stop ab12kw
```

### Logs + screenshot

```
iostesting logs [--bundle-id <id-or-short-id>] [--predicate "..."] [--json]
iostesting screenshot [-o ./shot.png]
```

### Physical devices

```
iostesting device list [--json]
iostesting device install -d <device-id> <app-or-ipa-path>
iostesting device launch -d <device-id> <bundle-id>
```

Backed by `xcrun devicectl`. A follow-up release will swap to FBDeviceControl for full device control (logs, terminate, OS log streaming, etc).

### Tests

```
iostesting test list <path/to/MyTests.xctest>
iostesting test run <path/to/MyTests.xctest> [--filter Suite/test...]... [--json]
```

`test run` emits NDJSON `caseStarted` / `casePassed` / `caseFailed` / `suiteFinished` / `runFinished` events when `--json` is passed.

### Licenses

```
iostesting licenses     # full third-party notices (MIT, Apache 2.0)
```

### `--examples` on every command

Every command accepts `--examples` to print curated usage snippets and exit:

```
iostesting test run --examples
iostesting sim location --examples
iostesting stop --examples
```

This is the anti-hallucination escape valve — when in doubt, ask the binary instead of guessing.

## Limitations in 2.0.0

- **XCUITest via the FB backend has known iOS 26 quirks** — direct path stalls on DTX handshake; `useXcodebuild=YES` path fails on `.xctestrun` write. Routes to the simctl backend (`xcodebuild test`) work fine. Targeted fix in 2.1.
- **UI verbs beyond `tap`/`swipe`** — `find`/`wait`/`assert`/`type`/`screen+AX-tree` need FBAccessibilityElement bridging. Queued for 2.1.
- **Physical-device runtime control + log streaming** — `device list/install/launch` work; richer device ops need FBDeviceControl wired through FBBridge.
- **Performance tests still belong to xcodebuild.** Simulator perf metrics are unreliable; iostesting can't fix that. Run perf tests on physical hardware via `xcodebuild test` with a Release-config perf scheme.

## Pairing with the skill

The `@ioloro/ios-testing` skill in `../skills/ios-testing/` writes good tests in modern Swift Testing / XCTest / XCUITest idioms. When the user asks the agent to actually run them, the skill points at `iostesting test run` instead of `xcodebuild test`. The optional guard hook in `../hooks/` enforces this at the Bash level.

## License

iostesting itself: MIT (see `../LICENSE`).

Third-party notices are embedded in the binary (`iostesting licenses`) and mirrored at `../THIRD_PARTY_LICENSES.txt`. 2.0.0 vendors the Meta-licensed FB frameworks under MIT — the notice covers them.
