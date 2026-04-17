# Swift Testing Reference

Use `import Testing` for all unit and integration tests. This is the default framework for new tests.

## Basic Test Structure

```swift
import Testing

@Suite("Authentication")
struct AuthenticationTests {
    let service: AuthService

    init() { service = AuthService(store: MockStore()) }  // init() replaces setUp()

    @Test func loginSucceeds() async throws {
        let result = try await service.login(user: "admin", pass: "secret")
        #expect(result.isAuthenticated)
    }

    @Test func loginFailsWithBadPassword() async throws {
        #expect(throws: AuthError.invalidCredentials) {
            try await service.login(user: "admin", pass: "wrong")
        }
    }
}
```

Key: Use `struct` (or free functions), not `class`. Each test gets a **fresh instance**. Use `deinit` (requires `class`) or `defer` for teardown.

## Assertions

```swift
// #expect — soft assertion, test continues on failure
#expect(items.count == 3)
#expect(items.first?.name == "Widget")

// #require — hard assertion, stops test. Use only when continuing is meaningless.
let first = try #require(items.first, "Items must not be empty")
#expect(first.price > 0)

// Floating-point: never exact equality
#expect(abs(result - 0.3) < 0.0001)

// Order-independent collection
#expect(Set(tags) == Set(["ios", "swift"]))
```

## Error Testing

```swift
#expect(throws: ValidationError.tooShort) { try validate(input: "") }     // Exact value
#expect(throws: NetworkError.self) { try fetchData(from: "bad://url") }   // Any of type
#expect(throws: Never.self) { try validate(input: "hello") }              // No error

// Inspect thrown error
let error = try #require(throws: ValidationError.self) { try validate(input: -1) }
#expect(error.field == "age")
```

## Parameterized Tests

```swift
// Tuples
@Test("Fibonacci", arguments: [(0, 0), (1, 1), (2, 1), (3, 2), (5, 5)])
func fibonacci(input: Int, expected: Int) { #expect(fibonacci(input) == expected) }

// CaseIterable enum
@Test("All priorities have colors", arguments: Priority.allCases)
func priorityHasColor(priority: Priority) { #expect(priority.color != nil) }

// Multiple params = cartesian product
@Test("Tax", arguments: ["US", "UK"], [100.0, 500.0])
func taxCalc(country: String, amount: Double) { #expect(calculateTax(country: country, amount: amount) >= 0) }

// zip() for paired iteration (NOT cartesian)
@Test(arguments: zip(["Alice", "Bob"], [30, 25]))
func userAge(name: String, age: Int) { #expect(User(name: name, age: age).isValid) }
```

For readable failures, conform to `CustomTestStringConvertible`:
```swift
struct TestCase: CustomTestStringConvertible, Sendable {
    let input: String; let expected: Int
    var testDescription: String { "\(input) → \(expected)" }
}
```

## Traits and Tags

```swift
extension Tag { @Tag static var networking: Self; @Tag static var critical: Self }

@Test(.tags(.networking, .critical)) func apiReachable() async throws { ... }
@Test(.disabled("Server migration")) func syncLegacy() { ... }
@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] != nil)) func ciOnly() { ... }
@Test(.bug("https://github.com/repo/issues/42")) func intermittent() { ... }
@Test(.timeLimit(.minutes(2))) func longOp() async throws { ... }  // Apply to all async tests

// Serialize within a suite (WARNING: use sparingly — masks concurrency bugs)
@Suite(.serialized) struct DatabaseTests { ... }
```

Tags = flexible cross-suite labels. Combining in filter = AND logic.

## Async Patterns

```swift
// Async is first-class
@Test func asyncFetch() async throws {
    let data = try await service.fetchData()
    #expect(data.count > 0)
}

// confirmation() replaces XCTestExpectation
@Test func notificationFires() async {
    await confirmation { confirm in
        NotificationCenter.default.addObserver(forName: .dataDidUpdate, object: nil, queue: .main) { _ in confirm() }
        service.triggerUpdate()
    }
}

// Must be confirmed exactly N times / range (Swift 6.2+) / never
await confirmation(expectedCount: 3) { confirm in ... }
await confirmation(expectedCount: 2...5) { confirm in ... }
await confirmation(expectedCount: 0) { confirm in ... }  // Verify NEVER called
```

## Known Issues

```swift
withKnownIssue("Parser doesn't handle timezones yet") {
    #expect(DateParser.parse("2025-12-01T10:00:00+05:30") != nil)
}
```
Reports failure without counting against results. Flags "unexpected success" when bug is fixed.

## Exit Tests (Swift 6.2+)

```swift
@Test func outOfBoundsAccessCrashes() async {
    await #expect(processExitsWith: .failure) { _ = [1, 2, 3][10] }
}
```

## Custom Test Scoping Traits (Advanced)

```swift
struct DatabaseTrait: TestTrait, TestScoping {
    func provideScope(for test: Test, testCase: Test.Case?,
                      performing body: @Sendable () async throws -> Void) async throws {
        let db = try TestDatabase.createInMemory()
        try await TestDatabaseKey.$current.withValue(db) { try await body() }
    }
}
extension TestTrait where Self == DatabaseTrait { static var database: Self { .init() } }

@Test(.database) func queryReturnsResults() async throws { ... }
```

## Attachments (Swift 6.2+)

```swift
Attachment(result.debugDescription, named: "processing-result").attach()
```

## What Swift Testing Cannot Do

These require XCTest: performance benchmarks (`measure {}`), UI testing (`XCUIApplication`), KVO expectations, Objective-C test code.
