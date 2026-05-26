---
name: ios-testing
version: "2.2.0"
description: >
  Use when writing, modifying, or reviewing tests for iOS/macOS apps.
  Activates for Swift Testing (@Test, #expect, @Suite), XCTest (XCTestCase, measure, XCTAssert),
  XCUITest (XCUIApplication, XCUIElement), performance testing, animation hitch testing,
  Instruments .trace file analysis (CPU profiling, system trace, allocations, etc.),
  or when the user asks to write tests.
---

# iOS Testing Skill

You are an expert in Apple platform testing. Follow these rules strictly.

## Decision flowchart (READ FIRST)

```
   ┌─────────────────────────────────┐
   │  User wants tests written or run │
   └────────────────┬────────────────┘
                    │
                    ▼
        ┌────────────────────────┐
        │  What are we testing?  │
        └─┬──────────┬──────────┬┘
          │          │          │
   logic/async    UI/screens   perf / energy / hitches
          │          │          │
          ▼          ▼          ▼
   ┌─────────┐ ┌──────────┐ ┌────────────────────┐
   │  Swift  │ │ XCUITest │ │  XCTest +          │
   │ Testing │ │  (part   │ │  XCTMetric         │
   │         │ │  of      │ │  subclasses.       │
   │ default │ │  XCTest) │ │  Physical device + │
   │ for new │ │          │ │  Release scheme    │
   │ tests   │ │          │ │  required for      │
   │         │ │          │ │  accurate numbers. │
   └────┬────┘ └─────┬────┘ └──────────┬─────────┘
        │            │                 │
        └──────┬─────┴─────────────────┘
               │
               ▼
   ┌──────────────────────────────────────────────────┐
   │   Test compiles + builds (xcodebuild build /      │
   │   build-for-testing / swift build / etc.)         │
   └──────────────────┬───────────────────────────────┘
                      │
                      ▼
   ┌──────────────────────────────────────────────────┐
   │   How do we run it?                              │
   ├──────────────────────────────────────────────────┤
   │  logic / unit       → iostesting test run        │
   │  app-hosted XCTest +→ IOSTESTING_BACKEND=fb       │
   │   Swift Testing       iostesting test run         │
   │  UI test bundle     → xcodebuild test (FB path    │
   │                       has iOS 26 quirks → 2.1)    │
   │  performance        → xcodebuild test on real     │
   │                       device, Release scheme,     │
   │                       perf-only scheme           │
   └──────────────────────────────────────────────────┘
```

The two iron rules: **(1) do not invent assertion syntax** — when in doubt about `#expect(throws:)`, `try #require`, `confirmation`, or `@Test(arguments:)`, read [swift-testing.md](swift-testing.md) before writing. **(2) the test must run and pass before the change is done** — writing is half the job; closing the loop with `iostesting test run` (or `xcodebuild test` for UI/perf) is the other half.

## Framework Selection

Choose the correct framework based on what you are testing:

| What you are testing | Framework | Import |
|---------------------|-----------|--------|
| Unit tests, integration tests, logic, async code | **Swift Testing** | `import Testing` |
| Performance benchmarks (CPU, memory, clock, storage) | **XCTest** | `import XCTest` |
| Energy/power measurement | **XCTest** | `import XCTest` |
| Animation hitches, scroll performance, render metrics | **XCTest + XCUITest** | `import XCTest` |
| UI automation, element interaction, accessibility audits | **XCUITest** | `import XCTest` |
| Light/dark mode appearance testing | **XCUITest** (launch args) | `import XCTest` |
| Contrast and visibility testing | **XCUITest** (accessibility audit) | `import XCTest` |
| Snapshot/visual regression testing | **XCTest** (+ swift-snapshot-testing) | `import XCTest` |
| Exit/crash tests (Swift 6.2+) | **Swift Testing** | `import Testing` |
| Analyzing .trace files from Instruments | **xctrace CLI** | N/A (command-line tool) |

## Critical Rules

1. **Default to Swift Testing** for all new unit and integration tests. Never use `XCTestCase` for pure logic tests.
2. **Never mix assertion styles** in a single test function. Do not use `XCTAssertEqual` alongside `#expect`, or vice versa.
3. **Both frameworks can coexist** in the same test target. Use `import Testing` for Swift Testing tests and `import XCTest` for XCTest/XCUITest tests — but keep them in separate files.
4. **Use Swift Testing equivalents**, not XCTest legacy:
   - `#expect(a == b)` not `XCTAssertEqual(a, b)`
   - `#expect(condition)` not `XCTAssertTrue(condition)`
   - `try #require(optional)` not `XCTUnwrap(optional)`
   - `#expect(throws: ErrorType.self) { ... }` not `XCTAssertThrowsError`
   - `confirmation { }` not `XCTestExpectation` + `wait(for:)`
   - `@Test(.disabled("reason"))` not `XCTSkipIf` / `XCTSkipUnless`
5. **Use `init()` for setup** in Swift Testing, not `setUp()` / `setUpWithError()`.
6. **Performance tests require XCTest**. Swift Testing has no `measure {}` equivalent.
7. **UI tests require XCUITest** (which is part of XCTest). Swift Testing cannot drive UI.
8. **Each test gets a fresh instance**. Swift Testing creates a new suite instance per test — do not rely on shared mutable state between tests.
9. **Do not invent assertion syntax.** If you can't recall the exact shape of `#expect(throws:)`, `try #require`, `confirmation`, or `@Test(arguments:)`, read `swift-testing.md` before writing it. Hallucinated APIs compile-fail and waste a build cycle. The cost of looking is one read; the cost of guessing is one cycle.

## Common Mistakes

| Mistake | Why it's wrong | Use instead |
|---|---|---|
| `#expect(throws: SomeError())` | takes an error **type** or **value-matching closure**, not an instance | `#expect(throws: SomeError.self)` or `#expect(throws: SomeError.tooShort) { ... }` |
| `try #require` placed inside `#expect(...)` | `#require` is its own assertion — it doesn't nest | call `let x = try #require(optional)` on its own line, then `#expect(x.foo == ...)` |
| `confirmation { confirm in confirm.fulfill() }` | confused with `XCTestExpectation` | the parameter is **called** like a function: `confirm()` |
| `@Test(arguments: collectionA, collectionB)` for paired inputs | produces a **cartesian product**, not pairs | `@Test(arguments: zip(collectionA, collectionB))` for paired |
| `setUp()` / `setUpWithError()` inside a Swift Testing struct | wrong framework — those are XCTest methods | implement `init()` (synchronous) or `init() async throws` (async) on the suite |
| `XCTUnwrap(optional)` inside a `@Test` function | mixed-framework call | `try #require(optional)` |
| `XCTestExpectation` + `wait(for:timeout:)` inside `@Test` | XCTest pattern in Swift Testing file | `await confirmation("description", expectedCount: 1) { confirm in ...; confirm() }` |
| `measure { ... }` inside `@Test` | Swift Testing has no perf primitive | move perf tests to an `XCTestCase` file and use `measure(metrics:)` with specific `XCTMetric` subclasses |
| `app.staticTexts["Welcome"]` matching localized text | breaks under any non-English locale | use `accessibilityIdentifier` and query with `[.byId("welcome_screen_title")]` (or your project's helper) |
| Running performance tests on simulator | sim CPU/memory metrics are unreliable, sim only supports Duration | physical device, Release config, perf-only test scheme |
| Only auditing accessibility on the first screen | misses regressions on flows | call `app.performAccessibilityAudit(for: [.contrast, .dynamicType])` on every screen |
| Hardcoded `UIColor.black` / `Color.white` | breaks dark mode + dynamic type contrast | semantic: `UIColor.label`, `.systemBackground`, SwiftUI `.primary` |

## Best Practices

### General
- **F.I.R.S.T. principles**: Fast (leverage default parallelism), Isolated (fresh instance per test), Repeatable (control all inputs), Self-Validating (use assertions, never `print`), Timely (write tests alongside production code).
- **Do not weaken encapsulation for testing.** If something is `private`, do not make it `public` just to test it. Test through the public API.
- **Do not randomize test data.** Tests must verify that fixed input produces fixed output. Use deterministic values.
- **Mark XCTest methods as `throws`** instead of using `do/catch` or `try!`. Force unwraps crash the entire suite and produce incomplete reports.
- **Never compare floating-point values for exact equality.** Use a tolerance: `#expect(abs(result - 0.3) < 0.0001)`.

### Swift Testing Specific
- **Prefer `#expect` over `#require`** for most assertions. Use `#require` only when continuing after failure is meaningless (e.g., unwrapping an optional needed by subsequent assertions).
- **Do not overuse `.serialized`.** It masks concurrency bugs and slows tests. Only use it temporarily for legacy non-thread-safe code.
- **Do not add `@MainActor` to tests unnecessarily.** It forces serial execution and defeats parallelism.
- **Apply `.timeLimit()` to async tests** to prevent CI hangs.
- **Use `zip()` for paired test arguments**, not separate collections (which create a cartesian product).
- **Conform parameterized types to `CustomTestStringConvertible`** for readable failure messages.

### XCTest/XCUITest Specific
- **Always use specific `XCTMetric` subclasses** in `measure(metrics:)`, not bare `measure {}`.
- **Run performance and animation tests on physical devices.** Simulators do not produce accurate hitch data and only support the Duration metric.
- **Use a separate test scheme** for performance tests with Release config, debugger disabled, screenshots off, code coverage off, and all diagnostics disabled.
- **Always use `accessibilityIdentifier`** for element queries, never localized display text.
- **Set `continueAfterFailure = false`** in UI test `setUpWithError()`.

## Anti-Patterns to Avoid

- Writing multiple near-identical test functions instead of using `@Test(arguments:)`.
- Using `XCTestCase` subclass with `setUp()`/`tearDown()` for pure logic tests.
- Mixing `import Testing` and `import XCTest` assertions in the same test function.
- Hardcoding timeouts without `waitForExistence` or expectations for async UI.
- Testing on simulator and expecting accurate performance/hitch metrics.
- Using `.serialized` or `@MainActor` as a default — these should be rare exceptions.
- Only testing in light mode — always test both light and dark appearances.
- Using hardcoded colors (`UIColor.black`, `Color.white`) instead of semantic colors.
- Running accessibility audits on only the first screen — audit every screen in the flow.

## Running Tests

Writing the test is half the job. The test must run and pass before the change is considered done.

This repo ships an `iostesting` CLI (in `cli/`) that drives simulators, physical devices, and `.xctest` bundles. When the user asks you to actually run the tests you just wrote, use `iostesting` rather than constructing raw `xcodebuild test` or `xcrun simctl` invocations.

**Build with whatever build tool the project already uses**, then run the resulting `.xctest` bundle:

```bash
# build the test bundle via the project's build tool (xcodebuild, swift build, etc.)
# then drive execution with iostesting:

iostesting sim list --state Booted                                # find or boot a sim
iostesting sim boot "iPhone 17 Pro"                               # idempotent
iostesting test list path/to/MyTests.xctest                       # confirm tests compiled in
iostesting test run path/to/MyTests.xctest --json                 # NDJSON events
iostesting test run path/to/MyTests.xctest --filter MySuite/testThing
```

**When in doubt, ask the binary.** Every command supports `--examples`:

```bash
iostesting test run --examples       # curated snippets — never guess flag shapes
iostesting sim location --examples
iostesting stop --examples
```

**Two backends — pick per test type:**
- **Default `IOSTESTING_BACKEND=simctl`** — shells to `xcrun simctl spawn xctest`. Logic tests only. Works on any Mac with Xcode installed.
- **`IOSTESTING_BACKEND=fb`** — direct linkage against XCTestBootstrap. Runs app-hosted XCTest + Swift Testing bundles end-to-end on iOS 26 simulators. Emits per-case NDJSON events (`caseStarted`/`casePassed`/`caseFailed` with durations + attachments). Set this env var when you need to run real test bundles via iostesting.

**2.0.0 limitations:**
- **XCUITest via the FB backend has known iOS 26 quirks** (DTX handshake stall / `.xctestrun` write fail). Use `xcodebuild test` for UI tests until 2.1.
- **UI verbs beyond `tap` and `swipe`** (`find`/`wait`/`assert`/`type`/`screen+AX-tree`) need FBAccessibilityElement bridging — queued for 2.1.
- **Device runtime control + log streaming** — `device list/install/launch` work via `xcrun devicectl`; richer device ops need FBDeviceControl wired through FBBridge.
- **Performance tests still require physical hardware** for accurate metrics. iostesting cannot make simulator perf numbers meaningful — that constraint is from XCTest itself.

**Decision rule per test type:**
- Unit / logic Swift Testing or XCTest, no host app → `iostesting test run` (default simctl backend is enough). Run after writing.
- App-hosted XCTest + Swift Testing bundles → `IOSTESTING_BACKEND=fb iostesting test run`. Auto-detects the host app from the bundle's `.app/PlugIns/` parent.
- UI tests (XCUITest) → still `xcodebuild test` in 2.0.0. iostesting's XCUITest path lands cleanly in 2.1.
- Performance tests → physical device, Release scheme, `xcodebuild test` directly. Do not run on simulator.

**Config makes flags implicit.** Once `iostesting config set --sim "iPhone 17 Pro" --bundle-id com.example.MyApp` has been run, `--sim` and positional bundle ids become optional on every command. Use `iostesting config show` to see what's bound. For CI, set `IOSTESTING_SIM` and `IOSTESTING_BUNDLE_ID` env vars instead of writing a config file.

**App registry + short IDs.** `iostesting launch` records each launched app and prints a 6-character short ID. `iostesting stop <short-id>` and `iostesting logs --bundle-id <short-id>` resolve sim + bundle automatically — no need to retype them:

```bash
$ iostesting launch com.example.MyApp
Launched com.example.MyApp on iPhone 17 Pro (pid 12345) [id ab12kw]

$ iostesting logs --bundle-id ab12kw       # sim + bundle resolved from registry
$ iostesting stop ab12kw
```

`iostesting apps list` shows the registry; `iostesting apps prune` clears terminated records.

**Physical devices.** `iostesting device list` shows paired devices; `device install` and `device launch` work via `xcrun devicectl`. Device log streaming and richer runtime control land in a follow-up release via FBDeviceControl.

**Other useful sim ops you don't have to remember the simctl flags for:**

```bash
iostesting sim appearance light          # or dark — for screenshot tests
iostesting sim media-add ./fixtures/*.jpg
iostesting sim location --set "37.7749,-122.4194"
iostesting sim open-url myapp://reset-password
iostesting screenshot -o ./shot.png
```

## SpringBoard alerts XCUITest can't reach (iOS 26)

XCUITest's `addUIInterruptionMonitor` is scoped to the app under test. It catches the **initial** CLLocationManager prompt ("When in Use / Once / Don't Allow") but reliably misses SpringBoard-owned modals that fire mid-test — most notably iOS 26's location-upgrade prompt:

> Allow "X" to also use your location even when you are not using the app?
> [Keep Only While Using]   [Change to Always Allow]

The test stalls while the runner tries to interact with elements behind the modal, eventually hitting `--termination-timeout` with "host application process stalled".

**Two layered fixes, both wired into `iostesting test run`:**

1. **Pre-grant the privacy state before the runner launches.** `simctl privacy grant location-always` writes `Authorization=4, AuthorizationUpgradeAvailable=false` into locationd's `clients.plist`. The upgrade prompt then never fires because iOS sees the auth is already at Always:

   ```bash
   IOSTESTING_BACKEND=fb iostesting test run ./MyAppUITests.xctest \
     --privacy-grant all-location
   ```

   The grant MUST happen after the app is installed (locationd needs the bundle path). `iostesting test run` does the install + grant in the right order.

2. **Background watcher with OCR-driven dismissal.** When a prompt is going to fire regardless (notifications, tracking, second-time grants), spawn a watcher that screenshots the sim every 2s, OCRs the screen with Vision, and taps any matching button:

   ```bash
   IOSTESTING_BACKEND=fb iostesting test run ./MyAppUITests.xctest \
     --auto-dismiss-alerts
   ```

   Belt-and-suspenders combination:

   ```bash
   IOSTESTING_BACKEND=fb iostesting test run ./MyAppUITests.xctest \
     --privacy-grant all-location \
     --auto-dismiss-alerts \
     --termination-timeout 300
   ```

Defaults cover the common labels: `Keep Only While Using`, `Allow While Using App`, `Allow Once`, `Don't Allow`, `OK`, `Allow`. Override with `--auto-dismiss-label`.

Standalone alert tools (when not running a full test):

```bash
IOSTESTING_BACKEND=fb iostesting alerts dismiss            # one-shot, exit 2 on no match
IOSTESTING_BACKEND=fb iostesting alerts watch --duration 120 --json
IOSTESTING_BACKEND=fb iostesting privacy grant --all-location com.example.MyApp
```

**When to reach for which:**
- App requires "Always" location for a background task → `--privacy-grant all-location`.
- App requires a one-time When-In-Use grant and you still want to test the prompt path → `--auto-dismiss-alerts` (the test still sees the prompt fire; the watcher handles it if XCUITest's monitor fails).
- App fires a notifications/tracking prompt mid-flow → `--auto-dismiss-alerts` (no `--privacy-grant` for that service exists; simctl doesn't expose notification-permission grants).

**Optional enforcement hook.** The repo ships `hooks/iostesting-guard.sh`, a Claude Code `PreToolUse` hook that blocks `xcrun simctl boot/install/launch/...` and `xcodebuild test` and suggests the `iostesting` equivalent. See `hooks/README.md` for install instructions. Without the hook the skill is advice; with it, it's a contract.

## Analyzing .trace Files

You can read and analyze Xcode Instruments `.trace` files directly. When a user provides a `.trace` file:

1. **Export the TOC** with `xctrace export --input /path/to/file.trace --toc` to discover available data tables.
2. **Export specific tables** to a file using `--xpath` and `--output /tmp/trace_data.xml` (piping large XML loses ref context).
3. **Parse with Python** (`xml.etree.ElementTree`) to resolve the id/ref deduplication system and extract meaningful data.
4. **Suggest code improvements** based on the findings.

### Critical Gotchas
- **Use `time-profile` schema** (symbolicated frames), NOT `time-sample` (raw `kperf-bt` hex addresses). This is the #1 time-waster.
- **`--filter-time` does not exist** — export full data and filter programmatically.
- **Ref resolution is mandatory** — threads, states, and frames use `id="N"`/`ref="N"` deduplication. Build lookup dicts.
- **For hangs**: export `potential-hangs` first for time ranges, then `time-profile` filtered to main thread + Running state.

See the [trace analysis reference](trace-analysis.md) for the complete guide including hang analysis workflow with Python script, .trace file structure, all schemas, and XML format details.

## Reference Files

For detailed patterns and code examples, see:
- [Swift Testing patterns and examples](swift-testing.md)
- [XCTest performance, power, and energy testing](xctest.md)
- [XCUITest UI automation and animation testing](xcuitest.md)
- [Instruments .trace file analysis](trace-analysis.md)
- For running tests via the iostesting CLI: see `../../cli/README.md` in this repo.

## When Generating Tests

1. Ask yourself: "Is this testing logic/behavior, or performance/UI?" Pick the framework accordingly.
2. For Swift Testing: use free functions or structs, not classes. Use `@Test` and `@Suite`.
3. For parameterized tests: always prefer `@Test(arguments:)` over writing multiple similar test functions.
4. For async code: Swift Testing supports `async` natively. Use `confirmation()` for callback-based APIs.
5. For performance: use `measure(metrics:)` with specific `XCTMetric` subclasses, not bare `measure {}`.
6. For UI tests: always use accessibility identifiers, never match on localized strings.
7. For error testing: use `#expect(throws:)` with the specific error value or type.
8. For known bugs: use `withKnownIssue("description") { }` instead of disabling the test.
9. For appearance testing: test both light and dark mode using launch arguments + `overrideUserInterfaceStyle`.
10. For contrast/visibility: run `performAccessibilityAudit(for: .contrast)` in both appearance modes.
11. Use semantic/system colors (`UIColor.label`, `.systemBackground`, SwiftUI `.primary`) — never hardcode colors.
