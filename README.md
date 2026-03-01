# @ioloro/ios-testing

A Claude Code skill for writing correct, modern iOS and macOS tests using Swift Testing, XCTest, and XCUITest.

## What it does

This skill teaches Claude (and other AI) when and how to use each Apple testing framework:

- **Swift Testing** — default for all new unit and integration tests (`@Test`, `#expect`, `@Suite`, parameterized tests)
- **XCTest** — performance benchmarks (`measure {}`, `XCTClockMetric`, `XCTCPUMetric`, `XCTMemoryMetric`, `XCTStorageMetric`), energy/power measurement (`XCTOSSignpostMetric`)
- **XCUITest** — UI automation, accessibility audits, animation hitch testing, scroll performance

## Why

AI models frequently:
- Default to XCTest when Swift Testing should be used
- Mix `XCTAssertEqual` with `#expect` in the same file
- Use bare `measure {}` instead of specific `XCTMetric` subclasses
- Skip parameterized tests in favor of copy-pasted test functions
- Forget about performance, power, and animation testing entirely

This skill fixes all of that.

## Install

```bash
# Via npm
npm install -g @ioloro/ios-testing

# Then enable in Claude Code
/plugin install @ioloro/ios-testing
```

## What's included

| File | Covers |
|------|--------|
| `SKILL.md` | Framework selection rules, critical rules, decision tree |
| `swift-testing.md` | `@Test`, `@Suite`, `#expect`, `#require`, parameterized tests, traits, tags, async patterns, `confirmation()` |
| `xctest.md` | `measure {}`, all `XCTMetric` subclasses, manual measurement, signpost-based energy testing, baselines |
| `xcuitest.md` | Element queries, accessibility identifiers, waiting patterns, launch config, scroll/animation performance, accessibility audits, page object pattern |

## License

MIT
