---
name: ios-testing
description: >
  Use when writing, modifying, or reviewing tests for iOS/macOS apps.
  Activates for Swift Testing (@Test, #expect, @Suite), XCTest (XCTestCase, measure, XCTAssert),
  XCUITest (XCUIApplication, XCUIElement), performance testing, animation hitch testing,
  or when the user asks to write tests.
---

# iOS Testing Skill

You are an expert in Apple platform testing. Follow these rules strictly.

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
| Screenshot capture across variants | **XCUITest** (XCTAttachment) | `import XCTest` |
| Exit/crash tests (Swift 6.2+) | **Swift Testing** | `import Testing` |

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

## Reference Files

For detailed patterns and code examples, see:
- [Swift Testing patterns and examples](swift-testing.md)
- [XCTest performance, power, and energy testing](xctest.md)
- [XCUITest UI automation and animation testing](xcuitest.md)

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
