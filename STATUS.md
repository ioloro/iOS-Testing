# Status & Roadmap

Living document. Updated each release. Start here when picking up a new session.

Current version: **2.0.0** (see [CHANGELOG.md](CHANGELOG.md)).

## Three-layer architecture (FlowDeck pattern)

| Layer | Purpose | Where | Status |
|---|---|---|---|
| Skill | Teaches the model to write correct tests | `skills/ios-testing/` | ✅ shipped (decision flowchart, common mistakes table, anti-hallucination Critical Rule #9) |
| CLI (`iostesting`) | Runs tests, drives sims/devices/UI | `cli/` | ✅ shipped (15 top-level / 33 leaves) |
| Hook (`iostesting-guard.sh`) | Blocks raw `xcodebuild test` / `xcrun simctl ...` | `hooks/` | ✅ shipped (12-case regression in CI) |

## Backend status

Two backends behind a `Backend` protocol:

- **`SimctlBackend` (default)** — shells out to `xcrun simctl` / `xcrun devicectl`. Works on any Mac with Xcode installed. Unconditionally what `iostesting` uses unless you opt in.
- **`FBBackend` (opt-in via `IOSTESTING_BACKEND=fb`)** — calls into the Meta FB frameworks via the ObjC bridge at `cli/Sources/FBBridge/`. Pipeline validated end-to-end. `HybridBackend` wraps the two so unimplemented methods fall through to simctl automatically.

### Methods wired through FBBackend → FBBridge

| Method | Wired | Smoke-tested |
|---|---|---|
| `listSimulators` | ✅ | ✅ real `FBSimulator.allSimulators` data |
| `resolveSimulator` | ✅ | ✅ |
| `boot` / `shutdown` / `erase` | ✅ | ✅ wired and functional (sim lifecycle) |
| `install` (SpinCall.app) | ✅ | ✅ `Installed SpinCall.app on PlayingPartners26.4` |
| `uninstall` | ✅ | ✅ `Uninstalled com.ioloro.SpinCall` |
| `launch` (returns real PID) | ✅ | ✅ `Launched com.ioloro.SpinCall (pid 18046) [id 4j95pn]` |
| `terminate` (by bundle id) | ✅ | ✅ `Stopped com.ioloro.SpinCall` |
| `ui tap` | ✅ | ✅ real `FBSimulatorHID` HID event on booted sim |
| `ui swipe` | ✅ | ✅ real swipe with delta steps |
| `listTests` (incl. app-hosted: auto-infers host app from `.app/PlugIns/` path) | ✅ | ✅ XCTestBootstrap + Shimulator runs against booted sim |
| `runTests` (via `FBSimulator.runTestWithLaunchConfiguration:reporter:logger:`) | ✅ | ✅ FBBridgeReporter forwards `suiteStarted/caseStarted/casePassed/caseFailed/runFinished` events through to Swift `RunState`. **Verified with 30+ Swift Testing cases (SpinCallTests).** |
| `runTests` — attachments, activities, video, OSLog, artifacts | ✅ | wired (FBBridgeReporter optional methods → `activityStarted/activityFinished/videoRecorded/osLogSaved/artifactSaved` events). Side-channel — typed `TestEvent` enum ignores them today; the NDJSON `--json` stream surfaces all of them. |
| `runTests` for XCUITest bundles | ⚠️ | wiring + UI-test auto-detection landed (`*UITests-Runner.app/PlugIns` → `initializeUITesting=YES`, target-app sibling discovery). Runtime fails on iOS 26 in two distinct ways — see blocker §4 below. |
| everything else | ⏳ | falls through to SimctlBackend |

## Active blockers

### 1. ✅ FIXED: `/var/db/xcode_select_link` precondition

`scripts/patches/idb-xcode-select-macos26.patch` makes `FBXcodeDirectory.symlinkedDeveloperDirectory()` fall back to `xcode-select -p` when the symlink is missing (macOS 26+ default state). Applied automatically by `scripts/fetch-frameworks.sh`. **Sim lifecycle methods now work without sudo.**

### 2. ✅ FIXED: HID `clientClass` exception on macOS 26

Two patches landed: `scripts/patches/idb-hid-clientclass-macos26.patch` falls back to the `_TtC` Swift mangled name (`_TtC12SimulatorKit24SimDeviceLegacyHIDClient`) when the dotted-form lookup returns nil; and `cli/Sources/FBBridge/FBBridge.m` now also loads `FBSimulatorControlFrameworkLoader.xcodeFrameworks` at bootstrap so SimulatorKit is actually dlopen'd. `ui tap` and `ui swipe` work end-to-end against real `FBSimulatorHID`.

### 3. ✅ FIXED: Swift Testing `lib_TestingInterop.dylib` on iOS 26

Patch `scripts/patches/idb-dyld-testinginterop-ios26.patch` injects `DYLD_LIBRARY_PATH` + `DYLD_FRAMEWORK_PATH` pointing at `$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/usr/lib` (and `Library/Frameworks` + `Library/PrivateFrameworks`) into the xctest env. Applies to FBListTestStrategy, FBLogicTestRunStrategy, and FBTestRunnerConfiguration.

**Verified:** `IOSTESTING_BACKEND=fb iostesting test run` runs 30+ Swift Testing tests across multiple suites end-to-end on `PlayingPartners26.4` (iOS 26.4) — including parameterized `@Test(arguments:)` cases. NDJSON event stream emits `caseStarted`/`casePassed`/`caseFailed` with `durationSeconds` per case.

### 4. ⚠️ KNOWN LIMITATION: XCUITest bundles via FBBridge

UI test bundles (`*UITests.xctest` inside `*UITests-Runner.app`) wire correctly through `FBTestLaunchConfiguration.initializeUITesting=YES` and detect the target app from the runner's sibling `.app`. Two pathways tried, both hit iOS 26 simulator quirks:

- **`useXcodebuild=NO`** (direct FBBundleConnection): host app launches but the runner-to-test DTX handshake stalls for 120 s and bails. Likely entitlements/signing on the spawned runner.
- **`useXcodebuild=YES`** (shell to xcodebuild's canonical harness): fails to write the `.xctestrun` file into the simulator's `data/fbsimulatorcontrol/` directory. Permissions or path-not-found inside sim data container.

Both are fixable but each needs a focused 1-2 hr session against `FBTestBundleConnection` / `FBTestManagerAPIMediator` / `FBXCTestRunFileWriter` in idb. Filed in `STATUS.md` v1.3 queue.

**Workaround:** UI tests continue to run via the default `IOSTESTING_BACKEND=simctl` path which delegates to `xcodebuild test` (the canonical XCUITest harness). The skill's `Running Tests` doctrine already routes UI tests to `xcodebuild test` for this reason.

## What's queued

### Tier 1 — capability gaps

| Item | Estimated effort | Notes |
|---|---|---|
| **XCUITest direct (without xcodebuild)** | 2-3 hr | Patch FBTestBundleConnection / FBTestManagerAPIMediator for iOS 26 DTX handshake quirks. Currently stalls the runner. |
| **XCUITest via xcodebuild path** | 1-2 hr | Fix `.xctestrun` file write into the simulator data container (permissions or wrong directory). |
| **xcresult bundle writer** | 2 hr | Currently reporter emits NDJSON. Wiring `resultBundlePath` to FBTestLaunchConfiguration and parsing `.xcresult` for richer agent reports. |
| **Surface attachments to typed `TestEvent`** | 30 min | Already JSON-emitted; add typed cases for activity start/finish + attachments + video paths so human output can show them. |
| **Device log streaming** | 1-2 hr | FBDeviceControl FBLogCommands; same FBFuture-await pattern as sim lifecycle |
| **`ui find/wait/assert/type/screen+AX-tree`** | 4-6 hr | AX tree extraction via FBAccessibilityElement.serializeWithOptions; rich JSON output for agents |
| **Logic-test `test run`** | 1-2 hr | XCTestBootstrap's `FBLogicTestRunStrategy` is already linked; wire `runTests(udid:bundlePath:filters:onEvent:)` through FBBridge. Listing already works. |

### Tier 2 — productization

| Item | Status |
|---|---|
| Tests for iostesting | ✅ shipped (8 Swift Testing tests) |
| GitHub Actions CI | ✅ shipped (build, test, hook regression, version drift) |
| Homebrew formula | ✅ template shipped; needs `url`/`sha256` filled on first release |
| `iostesting clean` | ✅ shipped |
| `iostesting context` | ✅ shipped |
| Signed prebuilt binary in GitHub Releases | ✅ workflow shipped at `.github/workflows/release.yml`. Needs 6 GitHub secrets (see [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)). Push a `v*` tag and the workflow signs, notarizes, and publishes. |
| Live Homebrew tap pointing at a release | ⏳ tag v2.0.0, fill formula `url`/`sha256`, push to `ioloro/homebrew-tap` |

### Tier 3 — nice-to-haves

| Item | Effort |
|---|---|
| Video record / stream (`iostesting record`) | 1-2 hr once UI bridging is in. Note: screenshot via FB framework is async-only at the public Swift API; simctl-backed screenshot stays the recommended path |
| Crash log enumeration (`iostesting crashes list/show/delete`) | 1-2 hr (FBCrashLogCommands) |
| macOS UI automation (`ui mac click/type/menu/...`) | 4-6 hr (separate AX backend) |
| More NDJSON streams (`apps` watch, `install` progress) | 1 hr each |

## Recommended next sessions, in order

1. **Upstream PR to facebook/idb with the xcode-select patch.** 30 min. Submit `scripts/patches/idb-xcode-select-macos26.patch` so other tools using idb benefit and we can drop our local patch.
2. **Fix HID `clientClass` for macOS 26.** 1-2 hr session. Probably one of: stale class name in `idb`'s symbol lookup, missing `+ load` registration on the `SimDeviceLegacyHIDClient` shim, or new initializer signature on `IndigoHIDRegistrationPort`. After this, `ui tap`/`ui swipe`/`ui type` all light up.
3. **Smoke test app lifecycle** (install/uninstall/launch/terminate) against a real built app. Likely just works; we need to confirm against a Debug `.app`.
4. **App-hosted XCTest via XCTestBootstrap.** The biggest piece — 4-8 hr session, own setup.
5. **v1.3 release**: signed binary + Homebrew tap go-live. 2-3 hr.

## How the bridge pattern works

When adding a new FB-framework-backed method:

1. Add a public method to `cli/Sources/FBBridge/include/FBBridge.h`. Use `BOOL ... error:NSError**` or `nullable Type ... error:NSError**` so Swift sees a throwing function. (Plain `pid_t` won't bridge — wrap in `NSNumber *` instead, as `launchBundleID` does.)
2. Implement in `cli/Sources/FBBridge/FBBridge.m`. Call `[self controlWithError:error]` for the cached `FBSimulatorControl`. Find the `FBSimulator` by UDID. Call the `FBFuture`-returning operation. Synchronously await with `[future awaitWithTimeout:N error:&err]`.
3. Wire from Swift in `cli/Sources/iostesting/Backend/FBBackend.swift`. Wrap with `do { try FBBridge.x() } catch { throw FBBackendError.bridgeFailed("x", error as NSError) }`.
4. Remove the corresponding `throw FBBackendError.notYetImplemented("x")` line so HybridBackend stops falling through.

For UI methods, also cache the `FBSimulatorHID` connection via `+hidForUDID:error:` (already in place) so consecutive events don't reconnect.

## Local dev: run-after-build symlinks

The CLI binary uses rpath `@executable_path/Frameworks`. SwiftPM places the binary at `.build/<arch>-apple-macosx/<config>/iostesting` without a sibling Frameworks dir, so dyld fails to load.

After every `swift build`, run:

```bash
ln -sf /path/to/repo/cli/Frameworks .build/arm64-apple-macosx/debug/Frameworks
# or for release:
ln -sf /path/to/repo/cli/Frameworks .build/arm64-apple-macosx/release/Frameworks
```

For tests:

```bash
ln -sf /path/to/repo/cli/Frameworks \
  .build/arm64-apple-macosx/debug/iostestingPackageTests.xctest/Contents/MacOS/Frameworks
```

A future improvement: a SwiftPM build plugin that does this automatically post-build.

For Homebrew distribution: the formula's `install` block copies `Frameworks/` into `prefix/Frameworks/` alongside `bin/iostesting`, and the rpath resolves.

## Distribution

- **Skill** ships via npm as `@ioloro/ios-testing` (`package.json` `files` array intentionally excludes `cli/`).
- **CLI** ships separately. Currently: `git clone && swift build`. Next: tag `v2.0.0` and the release workflow handles signing + notarization + GitHub Release + tarball with embedded FB Frameworks (~50MB). Then update the Homebrew tap.
