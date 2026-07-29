# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Skill 2.2.0 → 2.3.0 — test reliability reference.** New `skills/ios-testing/test-reliability.md` capturing the failures that only show up on a loaded/shared/newer-OS CI runner ("passes locally, crashes in CI"):
  - **Timing-robust tests:** never assert a wall-clock *upper* bound; poll-to-a-condition instead of fixed `sleep`; measure timing *relatively* when it's the contract; guarantee "some but not all" by construction.
  - **Actor isolation on the iOS 26+/Swift 6 runtime:** off-main calls into `@MainActor` code are now a hard `EXC_BREAKPOINT`/`SIGTRAP` (older runtimes silently continued) — Codable DTOs/models must be nonisolated; bridge mock callbacks (that run off-main) to main; the `@unchecked Sendable` continuation box.
  - **Continuation-bridge safety:** defensive timeout + once-guarded resume so a callback that never fires can't leak/hang; mocks must honor the reply/error contract.
  - **Unit-test-host hygiene:** guard app-startup network/listeners/gates and crash-reporting SDKs on `XCTestConfigurationFilePath`.
  - **CI runner reality:** `-parallel-testing-enabled NO` on constrained runners; `-retry-tests-on-failure` over named-suite skips (whack-a-mole); `build-for-testing` as a fast per-platform compile gate; tiered PR-vs-nightly gating; unreliable Swift Testing `skippedTests`/`-skip-testing` for nested `@Suite`s → gate at the source with `.enabled(if:)`.
  - **Diagnosis discipline:** read the real `.xcresult`/`.ips` crash before diagnosing; the crash victim ≠ the cause; reproduce on the exact runtime and verify locally before pushing.
- SKILL.md: new "Reliability, Concurrency & the CI host" best-practices section, matching anti-patterns, an expanded activation `description`, and the new reference in the file list.

## [2.0.0] - 2026-05-19

Major release: the package is no longer a skill-only npm install — it now ships a **three-layer system** (skill + Swift CLI + Claude Code hook) backed by direct linkage against Meta's MIT-licensed iOS automation frameworks (FBControlCore, FBSimulatorControl, FBDeviceControl, XCTestBootstrap). UI automation (`tap`, `swipe`), Swift Testing bundles, full app lifecycle, and XCTest event streaming all work end-to-end on iOS 26 simulators.

The version bump from 1.1.0 → 2.0.0 reflects the architectural shift: prior versions were documentation-only; 2.0.0 ships actual runtime infrastructure. The CLI surface is purely additive and the skill remains backwards compatible (npm consumers who only want the skill still get it via `npm install -g @ioloro/ios-testing`).

### Added

#### CLI (new — `cli/`)
- Swift 6 Package at `cli/`, builds to `iostesting` binary. ArgumentParser-based.
- **Simulator lifecycle:** `sim list`, `sim boot`, `sim shutdown`, `sim erase`, `sim create`, `sim prune`.
- **Simulator IO and state:** `sim media-add`, `sim location --set/--clear`, `sim button`, `sim appearance light|dark`, `sim open-url`.
- **App lifecycle:** `install`, `uninstall`, `launch` (with `--env`, `--arg`, `--wait-for-debugger`), `stop`.
- **App registry + short IDs:** every launched app gets a 6-char ID. `iostesting apps list/prune`. `stop` and `logs` accept the short ID and resolve sim + bundle automatically.
- **Logs:** `iostesting logs` with NDJSON output, bundle-id filter, custom NSPredicate.
- **Screenshot:** `iostesting screenshot`.
- **Tests:** `iostesting test list` (Mach-O symbol parse via `nm`), `iostesting test run` (logic tests via `simctl spawn xctest`, NDJSON event stream).
- **Physical devices:** `iostesting device list/install/launch` via `xcrun devicectl`.
- **Config:** `iostesting config show/get/set/reset` with project + global scopes; `IOSTESTING_SIM` and `IOSTESTING_BUNDLE_ID` env vars for stateless CI invocation.
- **License attribution:** `iostesting licenses` prints third-party notices (MIT for facebook/idb frameworks now vendored, Apache 2.0 for swift-argument-parser).
- **`--examples` flag on every command** — anti-hallucination escape valve; prints curated usage snippets and exits.
- `--json` on every read/write command for machine output.

#### Hook (new — `hooks/`)
- `hooks/iostesting-guard.sh`: Claude Code `PreToolUse` hook that blocks `xcodebuild test`, `xcrun simctl boot/install/launch/terminate/uninstall/create/erase/shutdown`, `simctl io ... screenshot`, `simctl spawn ... log`, and `simctl spawn ... xctest`, with `iostesting` suggestions.
- Allows: `xcodebuild build`, `build-for-testing`, `test-without-building`, `xcrun simctl list/runtime`, `notarytool`/`altool`, `swift build/test`. Handles `sudo`/`env`/`bash -c "..."` wrappers and tool names in argument position.
- `hooks/README.md` documents the install path.

#### Skill (`skills/ios-testing/SKILL.md`)
- Added "Running Tests" section: doctrine ("the test must run and pass before the change is considered done"), iostesting command examples, per-test-type decision rule (unit → iostesting; UI → xcodebuild until iostesting's XCUITest path stabilizes; perf → physical device).
- Note about config making `--sim` implicit.
- Pointer to the optional enforcement hook.

#### Other
- `THIRD_PARTY_LICENSES.txt` at repo root for repo browsers; identical content embedded in the CLI binary.
- `scripts/fetch-frameworks.sh` clones facebook/idb at a pinned SHA, applies our three compat patches (xcode-select fallback, HID clientClass, DYLD env for Swift Testing), builds the four MIT-licensed frameworks + shims, and vendors them into `cli/Frameworks/`.

### Added (FB framework integration)

- **FB framework integration pipeline** — `cli/Frameworks/` houses the four MIT-licensed Meta frameworks (built via `scripts/fetch-frameworks.sh`). `Package.swift` links them with `@rpath`-based runtime resolution.
- **`Sources/FBBridge/`** — ObjC bridging target. Clean `+ (BOOL)methodName:error:` API over the FB headers so Swift can call into the stack without inheriting CoreSimulator's missing module map.
- **`FBBackend`** — wired methods: `listSimulators`, `resolveSimulator`, `boot`, `shutdown`, `erase`. Opt in via `IOSTESTING_BACKEND=fb`.
- **`HybridBackend`** — falls through to SimctlBackend on `.notYetImplemented`, surfaces real bridge failures.

### Tooling

- `iostesting context` — project/scheme/target discovery via `xcodebuild -list -json`.
- `iostesting clean` — DerivedData + registry + project config, with `--dry-run`.
- `scripts/check-version-drift.sh` — locks package.json / SKILL.md / CLI / CHANGELOG to one version. Runs in CI.
- `.github/workflows/ci.yml` — build, swift test, hook regression (12 cases), version drift on every PR.
- `HomebrewFormula/iostesting.rb` — formula template for the eventual tap.
- 8 Swift Testing unit tests for `ConfigStore`, `AppRegistry`, `Examples`.

### Skill

- Added ASCII decision flowchart at top of `SKILL.md`.
- Common Mistakes table + Critical Rule #9 (do not invent assertion syntax).

### Added (FB framework integration substantially complete)

- **`scripts/patches/idb-xcode-select-macos26.patch`** — falls back to `xcode-select -p` when `/var/db/xcode_select_link` is missing (macOS 26+ default state). Auto-applied by `scripts/fetch-frameworks.sh`.
- **`scripts/patches/idb-hid-clientclass-macos26.patch`** — adds the legacy `_TtC` Swift mangled name as fallback for `SimDeviceLegacyHIDClient` lookup. Restores HID functionality on macOS 26+.
- **App lifecycle via FBBridge:** install / uninstall / launch (real PID) / terminate, all smoke-tested end-to-end against a real `.app` bundle.
- **UI automation via FBBridge:** `iostesting ui tap` and `iostesting ui swipe` work against real `FBSimulatorHID`. SimulatorKit is now loaded at bootstrap via `FBSimulatorControlFrameworkLoader.xcodeFrameworks`.
- **`iostesting test list` via XCTestBootstrap** when `IOSTESTING_BACKEND=fb`. Shims (`libShimulator.dylib`, `libMaculator.dylib`) shipped in `cli/Frameworks/FBControlCore.framework/Resources/`. Auto-infers the host `.app` from `Foo.app/PlugIns/FooTests.xctest` paths so app-hosted bundles work.
- **`iostesting test run` via XCTestBootstrap** wired through `FBSimulator.runTestWithLaunchConfiguration:reporter:logger:`. The bridge implements `FBXCTestReporter` (FBBridgeReporter) and forwards `suiteStarted/caseStarted/casePassed/caseFailed/runFinished` events to Swift's `RunState` for NDJSON streaming and human output. App-hosted + logic bundles wired.
- **Swift Testing bundles now run end-to-end on iOS 26.** Patch `scripts/patches/idb-dyld-testinginterop-ios26.patch` injects `DYLD_LIBRARY_PATH` + `DYLD_FRAMEWORK_PATH` into the xctest env so `lib_TestingInterop.dylib` resolves. Verified with SpinCallTests: 30+ Swift Testing cases across 6 suites, including parameterized `@Test(arguments:)` cases, all reporting via NDJSON.
- **XCUITest auto-detection in FBBackend** — bundles inside `*UITests-Runner.app/PlugIns` are recognized; target-app sibling is discovered automatically. `FBTestLaunchConfiguration.initializeUITesting=YES` is set; xcodebuild harness path is selected via `useXcodebuild=YES`. Runtime hits iOS 26 sim quirks (see STATUS §4) — use the default simctl backend / `xcodebuild test` for UI tests until the DTX-handshake / xctestrun-write fixes land in 2.1.
- **FBXCTestReporter optional methods**: `willStartActivity`/`didFinishActivity`/`didRecordVideoAtPath`/`didSaveOSLogAtPath`/`didCopiedTestArtifact` all forwarded to the JSON event stream as `activityStarted/activityFinished/videoRecorded/osLogSaved/artifactSaved` events with attachment metadata (name, UTI, size).

### Release infrastructure

- `.github/workflows/release.yml` — tag-triggered build → sign (Developer ID) → notarize (notarytool) → publish GitHub Release with tarball + sha256.
- `DEVELOPER_GUIDE.md` — full guide for setting up the 6 signing secrets, cutting releases, and maintaining the Homebrew tap.
- `HomebrewFormula/iostesting.rb` — formula template; fill in `url`/`sha256` on first tagged release.

### Known limitations (2.0.0)

- **XCUITest via FB backend** — wired but hits iOS 26 simulator quirks. Direct path stalls on the DTX runner-to-bundle handshake; `useXcodebuild=YES` path fails on `.xctestrun` write into the sim data container. Routes to the simctl backend (`xcodebuild test`) work fine. Targeted fix in 2.1.
- **No UI `find/wait/assert/type/screen` yet** — `tap` + `swipe` work; remaining UI verbs need FBAccessibilityElement bridging (1 session, 4-6 hr).
- **Physical-device runtime control + log streaming** — `device list/install/launch` work via `xcrun devicectl`; richer device ops need FBDeviceControl wired through FBBridge.
- **FB-backed screenshot** — Apple deprecated the synchronous FBFuture path in idb's public surface; only async-Swift is exposed. simctl-backed `iostesting screenshot` is the recommended path.
- **Performance tests** still require physical hardware and `xcodebuild test` directly. iostesting cannot make simulator perf numbers meaningful.

## [1.1.0] - 2026-04-17
- Better xctrace handling, including suggestions and limiting token context waste.

## [1.0.0]
- Initial release of the @ioloro/ios-testing skill: Swift Testing, XCTest, XCUITest, and Instruments .trace analysis.
