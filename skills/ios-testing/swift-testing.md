# Swift Testing Reference

Use `import Testing` for all unit and integration tests. This is the default framework for new tests.

## Basic Test Structure

```swift
import Testing

// Free function — no class or struct required
@Test("User email validation accepts valid emails")
func validEmail() {
    let user = User(email: "test@example.com")
    #expect(user.isValidEmail)
}

// Suite groups related tests
@Suite("Authentication")
struct AuthenticationTests {
    let service: AuthService

    // init() replaces setUp() — called before each test
    init() {
        service = AuthService(store: MockStore())
    }

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

Key points:
- Use `struct` (or free functions), not `class`. Classes are only needed if you require `deinit` for cleanup.
- Each test gets a **fresh instance** of the suite. State does not persist between tests.
- `init()` replaces `setUp()`. For teardown, use `deinit` (requires `class`) or `defer` within the test.

## Assertions

### #expect — soft assertion, test continues on failure

```swift
@Test func softAssertions() {
    let items = fetchItems()
    #expect(items.count == 3)
    #expect(items.first?.name == "Widget")

    // Operators are captured — failure output shows actual values
    let a = 5, b = 10
    #expect(a + b == 15)
}
```

### #require — hard assertion, stops test immediately

Use `#require` only when continuing after failure is meaningless.

```swift
@Test func hardAssertions() throws {
    let items = fetchItems()

    // Unwrap optionals safely (replaces XCTUnwrap)
    let first = try #require(items.first, "Items must not be empty")
    #expect(first.price > 0)
}
```

### Floating-point comparisons

Never compare floating-point values for exact equality:

```swift
// WRONG
#expect(result == 0.3)

// CORRECT
#expect(abs(result - 0.3) < 0.0001)
```

### Collection comparisons

For order-independent comparison, convert to `Set`:

```swift
#expect(Set(tags) == Set(["ios", "swift"]))
```

## Error Testing

```swift
// Exact error value
@Test func specificError() {
    #expect(throws: ValidationError.tooShort) {
        try validate(input: "")
    }
}

// Any error of a type
@Test func errorType() {
    #expect(throws: NetworkError.self) {
        try fetchData(from: "invalid://url")
    }
}

// Verify no error is thrown
@Test func noError() {
    #expect(throws: Never.self) {
        try validate(input: "hello")
    }
}

// Inspect the thrown error
@Test func inspectError() throws {
    let error = try #require(throws: ValidationError.self) {
        try validate(input: -1)
    }
    #expect(error.field == "age")
}
```

## Parameterized Tests

Use `@Test(arguments:)` instead of writing multiple similar test functions.

```swift
// Single parameter with tuples
@Test("Fibonacci sequence", arguments: [
    (0, 0), (1, 1), (2, 1), (3, 2), (4, 3), (5, 5)
])
func fibonacci(input: Int, expected: Int) {
    #expect(fibonacci(input) == expected)
}

// Enum conforming to CaseIterable
enum Priority: CaseIterable { case low, medium, high, critical }

@Test("All priorities have colors", arguments: Priority.allCases)
func priorityHasColor(priority: Priority) {
    #expect(priority.color != nil)
}

// Multiple parameters — cartesian product (all combinations)
@Test("Tax calculation", arguments: ["US", "UK", "DE"], [100.0, 500.0])
func taxCalc(country: String, amount: Double) {
    let tax = calculateTax(country: country, amount: amount)
    #expect(tax >= 0)
}

// Zip for parallel iteration (NOT cartesian product)
// Use zip when inputs and expected outputs are paired
@Test(arguments: zip(["Alice", "Bob"], [30, 25]))
func userAge(name: String, age: Int) {
    let user = User(name: name, age: age)
    #expect(user.isValid)
}
```

For readable failure messages with custom types, conform to `CustomTestStringConvertible`:

```swift
struct TestCase: CustomTestStringConvertible, Sendable {
    let input: String
    let expected: Int
    var testDescription: String { "\(input) → \(expected)" }
}
```

## Traits and Tags

```swift
// Define reusable tags
extension Tag {
    @Tag static var networking: Self
    @Tag static var database: Self
    @Tag static var critical: Self
}

// Apply tags for filtering
@Test(.tags(.networking, .critical))
func apiEndpointReachable() async throws { ... }

// Disable with reason
@Test(.disabled("Server migration in progress"))
func syncWithLegacyServer() { ... }

// Conditional execution
@Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] != nil))
func ciOnlyTest() { ... }

// Link to bug tracker
@Test(.bug("https://github.com/myrepo/issues/42", "Flaky on CI"))
func intermittentFailure() { ... }

// Time limit — apply to all async tests to prevent CI hangs
@Test(.timeLimit(.minutes(2)))
func longRunningOperation() async throws { ... }

// Serialize tests within a suite (run sequentially)
// WARNING: Use sparingly. Overuse masks concurrency bugs and slows execution.
@Suite(.serialized)
struct DatabaseTests {
    @Test func migrate() { ... }
    @Test func seed() { ... }
    @Test func query() { ... }
}
```

Tags let you categorize tests across suite boundaries. Unlike suites (rigid hierarchy), tags are flexible labels. Use tags for CI filtering (`.critical`, `.slow`) and suites for organizing related tests.

Note: combining tags in a filter runs tests with ALL specified tags (AND logic, not OR).

## Async Patterns

```swift
// Async tests are first-class
@Test func asyncFetch() async throws {
    let data = try await service.fetchData()
    #expect(data.count > 0)
}

// confirmation() replaces XCTestExpectation
@Test func notificationFires() async {
    await confirmation { confirm in
        NotificationCenter.default.addObserver(
            forName: .dataDidUpdate, object: nil, queue: .main
        ) { _ in
            confirm()
        }
        service.triggerUpdate()
    }
}

// Must be confirmed exactly N times
@Test func allStepsComplete() async throws {
    try await confirmation(expectedCount: 3) { confirm in
        let pipeline = Pipeline(onStep: { _ in confirm() })
        try await pipeline.run()
    }
}

// Range-based confirmation (Swift 6.2+)
@Test func variableEventCount() async {
    await confirmation(expectedCount: 2...5) { confirm in
        let stream = EventStream()
        for await _ in stream { confirm() }
    }
}

// Verify a callback is NEVER called
@Test func neverCalled() async {
    await confirmation(expectedCount: 0) { confirm in
        let handler = EventHandler(onError: { _ in confirm() })
        handler.processValid()
    }
}

// Bridging completion-handler APIs
@Test func legacyCallbackAPI() async {
    await confirmation { confirm in
        legacyFetch { result in
            #expect(result.isSuccess)
            confirm()
        }
    }
}
```

## Known Issues

Use `withKnownIssue` instead of disabling a test. It reports the failure without counting against test results, and flags an "unexpected success" when the underlying bug is fixed:

```swift
@Test func parserHandlesTimezones() {
    withKnownIssue("Parser doesn't handle timezone offsets yet") {
        let date = DateParser.parse("2025-12-01T10:00:00+05:30")
        #expect(date != nil)
    }
}
```

## Exit Tests (Swift 6.2+)

Test fatal conditions by running code in a subprocess:

```swift
@Test func outOfBoundsAccessCrashes() async {
    await #expect(processExitsWith: .failure) {
        let array = [1, 2, 3]
        _ = array[10]
    }
}
```

Currently supported on macOS, Linux, FreeBSD, OpenBSD, and Windows.

## Custom Test Scoping Traits (Advanced)

Encapsulate reusable setup/teardown logic with `TestScoping`:

```swift
struct DatabaseTrait: TestTrait, TestScoping {
    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing body: @Sendable () async throws -> Void
    ) async throws {
        let db = try TestDatabase.createInMemory()
        try await TestDatabaseKey.$current.withValue(db) {
            try await body()
        }
    }
}

extension TestTrait where Self == DatabaseTrait {
    static var database: Self { .init() }
}

// Usage
@Test(.database)
func queryReturnsResults() async throws { ... }
```

## Attachments (Swift 6.2+)

Embed supplementary diagnostic data with tests:

```swift
@Test func imageProcessing() throws {
    let result = process(image)
    #expect(result.isValid)
    // Attach data for debugging failures
    Attachment(result.debugDescription, named: "processing-result").attach()
}
```

## What Swift Testing Cannot Do

These still require XCTest:
- Performance benchmarks (`measure {}`, `XCTMetric`)
- UI testing (`XCUIApplication`, `XCUIElement`)
- KVO/KVP expectations
- Objective-C test code
