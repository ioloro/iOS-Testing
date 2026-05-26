# iostesting

A Swift CLI that drives iOS simulators, physical devices, and XCTest bundles. Companion to the `@ioloro/ios-testing` Claude Code skill — the skill writes the tests, this CLI runs them.

Build-tool agnostic: bring your own build (xcodebuild, swift build, Bazel, whatever). Point iostesting at the resulting `.xctest` bundle.

## Status

**v2.2.0 (current).** Two backends behind a single CLI:

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

## Setup

Claude Code plugins cannot ship permission allowlists via their manifest (only `agent` and `subagentStatusLine` keys are supported in plugin `settings.json`). Without setup, every fresh install of `@ioloro/ios-testing` hits Claude Code permission prompts for `xcrun simctl spawn`, `xcrun simctl location`, `swift build`, `iostesting:*`, etc.

```bash
iostesting setup            # merge iostesting permissions into ~/.claude/settings.json
iostesting setup --dry-run  # preview the diff without writing
iostesting setup --print    # dump the merged file to stdout, don't write
iostesting setup --path PATH  # override settings file location (for testing)
```

Idempotent. Running twice is a no-op. The command preserves unknown top-level keys, sibling keys inside `permissions` (e.g. `deny`), and the order of any pre-existing `allow` entries. It only adds the curated iostesting list. No MCP entries and no machine-specific full paths.

## Command surface (30 leaves under 13 top-level)

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
iostesting sim location --set "37.7749,-122.4194"     # override location (single point)
iostesting sim location --gpx ./round.gpx \           # replay a GPX track (default --interval=1, --max-waypoints=1500)
                       [--interval 1] [--max-waypoints 1500]
iostesting sim location --status                      # iostesting-recorded location state for this sim
iostesting sim location --clear
iostesting sim button home|lock|siri|side|apple-pay
iostesting sim appearance light|dark
iostesting sim open-url <url>                         # universal links + custom schemes
iostesting sim env --set KEY=VALUE [--set ...]        # bridge launchd env into the sim
iostesting sim env --unset KEY [--unset ...]          # newly-launched apps inherit; existing ones don't
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
iostesting test run <path/to/MyTests.xctest> [--filter Suite/test...]... \
                                              [--termination-timeout 120] \
                                              [--sim-env KEY=VALUE]... \
                                              [--privacy-grant SERVICE]... \
                                              [--auto-dismiss-alerts] \
                                              [--auto-dismiss-label LABEL]... \
                                              [--auto-dismiss-bundle-id BID] \
                                              [--json]
```

`test run` emits NDJSON `caseStarted` / `casePassed` / `caseFailed` / `suiteFinished` / `runFinished` events when `--json` is passed.

- `--termination-timeout` (FB backend) controls how long iostesting waits for the host app to terminate after the test method exits. Default 120s. Bump up to 600s when the app holds background subscriptions or in-flight network requests that delay clean shutdown.
- `--sim-env KEY=VALUE` sets a launchd env var on the sim before the runner boots, so newly-launched apps inherit it. Equivalent to `iostesting sim env --set KEY=VALUE` followed by the test run.
- `--privacy-grant <service>` pre-grants a `simctl privacy` service to the target app before the runner launches. Use `all-location` shorthand to grant both `location` and `location-always` (preempts iOS 26's "also use location" upgrade prompt that XCUITest's `addUIInterruptionMonitor` cannot catch). Repeatable.
- `--auto-dismiss-alerts` spawns a background watcher (`iostesting alerts watch`) that polls the sim every 2 seconds, OCRs the screen for known system-alert button labels, and taps them via FBSimulatorHID. Catches SpringBoard-owned modals (location upgrade, notifications, tracking, etc.) that the host-app's interruption monitor misses. Watcher tears down on test completion.
- `--auto-dismiss-label <label>` overrides the default label list (`Keep Only While Using`, `Allow While Using App`, `Allow Once`, `Don't Allow`, `OK`, `Allow`). Repeatable.
- `--auto-dismiss-bundle-id <bid>` resolves the target app for `--privacy-grant` when it can't be inferred from the host runner's sibling app's Info.plist.

### Privacy

```
iostesting privacy grant <service> <bundle-id> [--all-location]
iostesting privacy revoke <service> <bundle-id>
iostesting privacy reset <service> [<bundle-id>]
```

Wraps `xcrun simctl privacy` with safer semantics. The `--all-location` convenience grants both `location` and `location-always` in the order that produces `Authorization=4, AuthorizationUpgradeAvailable=false` in locationd's `clients.plist` — the state that suppresses iOS 26's "Allow X to also use your location even when you are not using the app?" upgrade prompt entirely.

Run AFTER installing the app (locationd needs the bundle path resolved). Recognized services: `all`, `calendar`, `contacts`, `contacts-limited`, `location`, `location-always`, `photos`, `photos-add`, `media-library`, `microphone`, `motion`, `reminders`, `siri`.

### Alerts

```
iostesting alerts dismiss [--label LABEL]... [--min-confidence 0.5] [--json]
iostesting alerts watch   [--label LABEL]... [--duration 600] [--interval 2.0] [--json]
```

Screenshot the sim, OCR it via the Vision framework, find a button whose recognized text contains one of the candidate labels, and tap its centroid via FBSimulatorHID. `dismiss` is one-shot (exit 2 if no match); `watch` polls in a loop until `--duration` expires.

Defaults catch the most common iOS prompts (location upgrade, when-in-use, allow-once, don't-allow, OK, allow). Override with `--label` for app-specific dialogs. The watcher is what `test run --auto-dismiss-alerts` spawns under the hood — call it manually if you want fine-grained control.

Requires `IOSTESTING_BACKEND=fb` (the tap path uses FBSimulatorHID; the OCR path uses Vision, which is bundled with macOS).

### Licenses

```
iostesting licenses     # full third-party notices (MIT, Apache 2.0)
```

### Setup (post-install)

```
iostesting setup [--dry-run] [--print] [--path PATH] [--json]
```

Merges the curated iostesting permission allowlist into `~/.claude/settings.json` so Claude Code stops prompting for `xcrun simctl spawn`, `swift build`, `iostesting:*`, etc. See the **Setup** section above.

### `--examples` on every command

Every command accepts `--examples` to print curated usage snippets and exit:

```
iostesting test run --examples
iostesting sim location --examples
iostesting stop --examples
```

This is the anti-hallucination escape valve — when in doubt, ask the binary instead of guessing.

## Limitations in 2.0.0

- **XCUITest via the FB backend**: in 2.0.0 the direct DTX path stalled on the
  bundle-ready handshake because the runner + target apps were never installed
  before `FBManagedTestRunStrategy` looked them up via
  `installedApplication(bundleID:)`. 2.0.1 installs both first and pins
  `useXcodebuild:NO` (the canonical idb path); the `useXcodebuild:YES` branch
  in upstream `FBXcodeBuildOperation.createXCTestRunFile` writes a literal
  `StubBundleId` placeholder dict that `xcodebuild` can't consume, so we never
  try to use it.
- **UI verbs beyond `tap`/`swipe`** — `find`/`wait`/`assert`/`type`/`screen+AX-tree` need FBAccessibilityElement bridging. Queued for 2.1.
- **Physical-device runtime control + log streaming** — `device list/install/launch` work; richer device ops need FBDeviceControl wired through FBBridge.
- **Performance tests still belong to xcodebuild.** Simulator perf metrics are unreliable; iostesting can't fix that. Run perf tests on physical hardware via `xcodebuild test` with a Release-config perf scheme.

## Pairing with the skill

The `@ioloro/ios-testing` skill in `../skills/ios-testing/` writes good tests in modern Swift Testing / XCTest / XCUITest idioms. When the user asks the agent to actually run them, the skill points at `iostesting test run` instead of `xcodebuild test`. The optional guard hook in `../hooks/` enforces this at the Bash level.

## License

iostesting itself: MIT (see `../LICENSE`).

Third-party notices are embedded in the binary (`iostesting licenses`) and mirrored at `../THIRD_PARTY_LICENSES.txt`. 2.0.0 vendors the Meta-licensed FB frameworks under MIT — the notice covers them.
