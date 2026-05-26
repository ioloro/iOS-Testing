# @ioloro/ios-testing

Three-layer productization for iOS/macOS test work in Claude Code: a **skill** that teaches the model to write correct modern tests, a **Swift CLI** that runs them, and an optional **enforcement hook** that blocks the old way.

- **Skill** — Swift Testing, XCTest, XCUITest, performance/accessibility/animation testing, and Instruments .trace analysis.
- **CLI** (`iostesting`) — drive simulators, devices, and `.xctest` bundles. Build-tool agnostic.
- **Hook** — optional Claude Code `PreToolUse` hook that blocks `xcodebuild test` and `xcrun simctl boot/install/launch/...` and suggests the `iostesting` equivalent.

## What it does

This skill teaches Claude when and how to use each Apple testing framework:

- **Swift Testing** — default for all new unit and integration tests (`@Test`, `#expect`, `@Suite`, parameterized tests)
- **XCTest** — performance benchmarks (`measure {}`, `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTStorageMetric`), energy/power measurement (`XCTOSSignpostMetric`)
- **XCUITest** — UI automation, accessibility audits, animation hitch testing, scroll performance, screenshot capture
- **Instruments .trace analysis** — export and analyze Time Profiler, System Trace, Allocations, and other trace data without leaving the terminal

The CLI then runs the tests Claude writes. The hook stops Claude from drifting back to raw `xcodebuild test`.

## Examples

Here are things you can ask Claude to do with this installed:

### Writing tests
- "Write tests for my UserService class"
- "Add parameterized tests for all the edge cases in this parser"
- "Convert these XCTest tests to Swift Testing"
- "Test that this function throws ValidationError.tooShort for empty input"

### Running tests
- "Run the tests on the iPhone 17 Pro simulator"
- "Run just the UserServiceTests in MyAppTests.xctest"
- "Boot the sim, launch the app, take a screenshot in light mode and another in dark mode"

### Performance and energy
- "Add a performance test that measures CPU and memory for this sort operation"
- "Set up signpost-based measurement for my image processing pipeline"
- "Add scroll deceleration hitch testing for my collection view"

### UI testing
- "Write UI tests for the login flow"
- "Add accessibility audits for contrast and dynamic type on every screen"
- "Set up screenshot capture across light mode, dark mode, and all themes"

### Trace file analysis
- "Analyze this .trace file and tell me why the app is slow"
- "Look at the time-sample data and find the hottest call stacks"
- "What's blocking the main thread in this System Trace?"

## Why

AI models frequently:
- Default to XCTest when Swift Testing should be used
- Mix `XCTAssertEqual` with `#expect` in the same file
- Use bare `measure {}` instead of specific `XCTMetric` subclasses
- Invent assertion syntax for `#expect(throws:)` or `confirmation` from memory
- Skip parameterized tests in favor of copy-pasted test functions
- Reach for raw `xcodebuild test` or `xcrun simctl` when a dedicated CLI exists
- Forget about performance, power, and animation testing entirely
- Can't analyze .trace files without manual xctrace export/XML parsing

This package fixes all of that across three reinforcing layers.

## Install

### Skill

```bash
npm install -g @ioloro/ios-testing
```

The skill installs to `~/.claude/plugins/` and activates on test-related requests.

### CLI

```bash
cd cli
swift build -c release
# Copy or symlink .build/release/iostesting to a directory on PATH

# One-time: merge iostesting's permission allowlist into ~/.claude/settings.json
# so Claude Code stops prompting for `xcrun simctl spawn`, `swift build`, etc.
iostesting setup
```

Requires Xcode 14+ and Swift 6 (tested on Swift 6.3 / Xcode 26.4).

`iostesting setup` is idempotent. It preserves unknown keys + the order of any pre-existing `permissions.allow` entries, and only appends the curated iostesting list (no MCP entries, no machine-specific paths). Run with `--dry-run` to preview the diff.

### Hook (optional)

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [{ "command": "/absolute/path/to/ios-testing/hooks/iostesting-guard.sh", "type": "command" }], "matcher": "Bash" }
    ]
  }
}
```

Then restart Claude Code. See [`hooks/README.md`](hooks/README.md) for details.

## What's included

### Skill (`skills/ios-testing/`)

| File | Covers |
|------|--------|
| `SKILL.md` | Framework selection, critical rules, common-mistakes table, anti-hallucination rules, iostesting handoff |
| `swift-testing.md` | `@Test`, `@Suite`, `#expect`, `#require`, parameterized tests, traits, tags, async patterns, `confirmation()`, exit tests, attachments, custom scoping traits |
| `xctest.md` | `measure {}`, all `XCTMetric` subclasses, manual measurement, signpost-based energy testing, baselines, power profiling |
| `xcuitest.md` | Element queries, waiting patterns, launch config, scroll/animation performance, hitch metrics, accessibility audits, screenshot capture, multi-variant screenshot testing, real device testing, screenshot extraction and review website generation, page object pattern |
| `trace-analysis.md` | Instruments .trace file structure, JSON export workflow, all common schemas by template, XML format reference, analysis patterns |
| `trace2json.py` | Python 3 script that exports .trace files to self-contained JSON — resolves id/ref deduplication, flattens backtraces, caps output size |

### CLI (`cli/`)

The `iostesting` Swift CLI runs the tests Claude writes. 13 top-level commands, 30 leaves:

```
config show / get / set / reset                       # eliminate boilerplate
sim list / boot / shutdown / erase / create / prune
sim media-add / location / button / appearance / open-url
install / uninstall / launch / stop                   # short-id registry
logs                                                  # short-id resolution
screenshot
apps list / prune                                     # the registry
device list / install / launch                        # via xcrun devicectl
test list / run                                       # NDJSON event stream
licenses
setup                                                 # merge permissions into ~/.claude/settings.json
```

Every command supports `--json` (or NDJSON for streaming) and `--examples` (anti-hallucination escape valve). Config is project (`./.iostesting/config.json`) or global (`~/.config/iostesting/config.json`), with `IOSTESTING_SIM` / `IOSTESTING_BUNDLE_ID` env vars for stateless CI invocation.

2.0.0 ships two backends behind a single CLI. The default (`IOSTESTING_BACKEND=simctl`) shells out to `xcrun simctl` / `xcrun devicectl` and works on any Mac with Xcode 14+. Opt into `IOSTESTING_BACKEND=fb` for direct linkage against the Meta-licensed `FBControlCore` / `FBSimulatorControl` / `FBDeviceControl` / `XCTestBootstrap` frameworks (see `scripts/fetch-frameworks.sh`) — unlocks UI automation (`tap`, `swipe`), Swift Testing bundles end-to-end on iOS 26 simulators, and full app lifecycle via direct framework calls. A `HybridBackend` falls through to simctl for methods not yet wired through FB.

See [`cli/README.md`](cli/README.md) for the full surface, limitations, and per-command examples.

### Hook (`hooks/`)

Optional Claude Code `PreToolUse` hook (`iostesting-guard.sh`) that blocks raw `xcrun simctl boot/install/launch/...` and `xcodebuild test` invocations and suggests the `iostesting` equivalent. The skill is advice; the hook is enforcement.

See [`hooks/README.md`](hooks/README.md) for install instructions and the full block list.

## Highlights

### Skill
- **Trace file analysis** — `trace2json.py` exports any .trace file to JSON in one command, then Claude reads and analyzes it directly
- **Multi-variant screenshot pipeline** — capture every screen across themes, appearances, and user types with structured naming
- **Screenshot review website** — automatically generates an HTML gallery grouping screenshots by screen with side-by-side variant comparison
- **Real device testing** — UDID-based destinations, signing setup, fresh install for NUX/onboarding capture
- **System sheet handling** — dismiss Sign In with Apple, TCC prompts, and notification banners on real devices
- **Accessibility audits** — automated contrast, hit region, dynamic type, and text clipping checks (iOS 17+)
- **Animation hitch testing** — `XCTOSSignpostMetric` sub-metrics for scroll deceleration, dragging, navigation transitions
- **Parameterized tests** — tuples, `CaseIterable`, cartesian products, `zip()` patterns
- **Exit tests** — process crash verification (Swift 6.2+)
- **Page object pattern** — encapsulated screen interactions for maintainable UI tests
- **Common-mistakes table + anti-hallucination rule** — catches the LLM-classic `#expect(throws: SomeError())` / `setUp()` inside Swift Testing / `confirmation { confirm.fulfill() }` mixups

### CLI
- **App registry + short IDs** — `iostesting apps` tracks every launched app. `iostesting stop ab12kw` resolves sim and bundle automatically
- **Saved config + env vars** — set `--sim` and bundle id once per project or per CI job; never type them again
- **NDJSON test events** — `iostesting test run --json` streams per-case pass/fail/duration for agent consumption
- **`--examples` everywhere** — every command prints curated snippets when in doubt, no hallucination required
- **Light/dark appearance toggle + camera-roll injection + location override** — the productization touches that make screenshot tests painless
- **MIT throughout** — third-party notices embedded and printable via `iostesting licenses`

### Hook
- Blocks `xcodebuild test` / `simctl boot/install/launch/screenshot/spawn-log/spawn-xctest` with iostesting suggestions
- Allows `xcodebuild build` / `build-for-testing` / `simctl list` / `simctl runtime` / `notarytool` — only the commands iostesting actually replaces
- Handles `sudo`/`env`/`bash -c "..."` wrappers; only blocks when the tool is in command position

## Versioning

This repo ships under one version (skill + CLI + hook). See [`CHANGELOG.md`](CHANGELOG.md) for the full history. Current version: **1.2.0**.

## License

MIT.
