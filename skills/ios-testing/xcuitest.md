# XCUITest UI Automation and Animation Testing Reference

Use `import XCTest` for all UI tests. XCUITest is part of the XCTest framework.

## Test Structure

```swift
import XCTest

class LoginUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false  // Always set this
        app.launch()
    }
}
```

## Element Queries

Always use `accessibilityIdentifier`, never localized display text.

```swift
// SwiftUI
Button("Submit") { ... }.accessibilityIdentifier("submitButton")

// UIKit
button.accessibilityIdentifier = "submitButton"

// Querying
let submit = app.buttons["submitButton"]                          // By identifier
let firstField = app.textFields.firstMatch                        // By type
let deleteBtn = app.cells["userCell"].buttons["delete"]           // Descendant
let predicate = NSPredicate(format: "label CONTAINS[c] 'save'")  // Predicate
let saveBtn = app.buttons.matching(predicate).firstMatch
```

## Waiting for Elements

Never interact without ensuring existence first — this is the #1 cause of flaky tests.

```swift
// Simple appearance check
XCTAssertTrue(label.waitForExistence(timeout: 10), "Should appear within 10s")

// Complex condition (e.g., element becomes enabled)
let predicate = NSPredicate(format: "isEnabled == true")
let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["submit"])
XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)

// Wait for disappearance
let gone = NSPredicate(format: "exists == false")
XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: spinner)], timeout: 10)
```

## Launch Arguments and Environment

```swift
app.launchArguments = ["--uitesting", "--reset-state", "-AppleLanguages", "(en)"]
app.launchEnvironment = ["API_BASE_URL": "http://localhost:8080", "ANIMATION_SPEED": "0"]
app.launch()
// Check in app: CommandLine.arguments.contains("--uitesting")
```

## Animation and Scroll Performance

**Physical device required.** Simulators only report Duration.

```swift
// Scroll deceleration with manual stop for state reset
func testScrollDeceleration() {
    let options = XCTMeasureOptions()
    options.invocationOptions = [.manuallyStop]
    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric], options: options) {
        app.collectionViews.firstMatch.swipeUp(velocity: .fast)
        stopMeasuring()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)  // Reset
    }
}

// Navigation transition
func testNavigationTransition() {
    measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric]) {
        app.buttons["showDetail"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
```

Available sub-metrics: `.navigationTransitionMetric`, `.customNavigationTransitionMetric`, `.scrollDecelerationMetric`, `.scrollDraggingMetric`.

### Hitch Metrics (physical device only)

| Metric | Description |
|--------|-------------|
| Hitch time ratio | `hitch_duration / animation_duration` (ms/s) — preferred over FPS |

**Thresholds:** < 5 ms/s good, 5–10 ms/s investigate, >= 10 ms/s take action.

### Custom Animation Signpost

```swift
// App code: use .animationBegin (not .begin) for hitch metrics
os_signpost(.animationBegin, log: renderLog, name: "CardFlip")
UIView.animate(withDuration: 0.3) { ... } completion: { _ in
    os_signpost(.end, log: renderLog, name: "CardFlip")
}

// Test code
func testCardFlipHitchRate() {
    let metric = XCTOSSignpostMetric(subsystem: "com.myapp", category: "PointsOfInterest", name: "CardFlip")
    measure(metrics: [metric]) {
        app.buttons["flipCard"].tap()
        _ = app.staticTexts["flipped"].waitForExistence(timeout: 2)
    }
}
```

## Light/Dark Mode Testing

XCUITest has no built-in appearance API. Use launch arguments with a DEBUG-guarded override.

**App code:**
```swift
#if DEBUG
// In App struct .onAppear or SceneDelegate:
if CommandLine.arguments.contains("--dark-mode") {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .forEach { $0.overrideUserInterfaceStyle = .dark }
}
#endif
```

**Test code — test both appearances systematically:**
```swift
class AppearanceTests: XCTestCase {
    func verifyScreen(app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["welcomeLabel"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: .contrast)
    }

    func testLightMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--light-mode"]
        app.launch()
        try verifyScreen(app: app)
    }

    func testDarkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-mode"]
        app.launch()
        try verifyScreen(app: app)
    }
}
```

**Snapshot testing** (swift-snapshot-testing):
```swift
let controller = UIHostingController(rootView: SettingsView())
controller.overrideUserInterfaceStyle = .dark
assertSnapshot(of: controller, as: .image(on: .iPhone13Pro))
// Or with traits: assertSnapshot(of: controller, as: .image(on: .iPhone13Pro, traits: UITraitCollection(userInterfaceStyle: .dark)))
```

**Common dark mode issues:** invisible text on wrong background, hardcoded colors instead of semantic (`UIColor.label`), missing dark mode image variants, contrast failures in one mode.

## Accessibility Audits (iOS 17+)

| Type | Checks |
|------|--------|
| `.contrast` | Color contrast ratios (WCAG 2.1) |
| `.elementDetection` | Interactive elements discoverable |
| `.hitRegion` | Minimum touch target sizes |
| `.sufficientElementDescription` | Meaningful accessibility labels |
| `.dynamicType` | Respects system font size |
| `.textClipped` | Text not truncated |
| `.trait` | Correct accessibility traits |

```swift
// Full audit
try app.performAccessibilityAudit()

// Specific types
try app.performAccessibilityAudit(for: [.contrast, .dynamicType])

// Exclude types
try app.performAccessibilityAudit(for: .all.subtracting(.sufficientElementDescription))

// Ignore known issues (return true to suppress)
try app.performAccessibilityAudit { issue in
    issue.element?.label.contains("Price") == true && issue.auditType == .hitRegion
}
```

**Multi-screen:** Audits only check visible elements. Navigate to each screen and audit:
```swift
try app.performAccessibilityAudit()
app.buttons["settingsButton"].tap()
try app.performAccessibilityAudit()
```

## Page Object Pattern

```swift
struct LoginPage {
    let app: XCUIApplication
    var usernameField: XCUIElement { app.textFields["usernameField"] }
    var passwordField: XCUIElement { app.secureTextFields["passwordField"] }
    var loginButton: XCUIElement { app.buttons["loginButton"] }

    func login(username: String, password: String) {
        usernameField.tap(); usernameField.typeText(username)
        passwordField.tap(); passwordField.typeText(password)
        loginButton.tap()
    }
}
```

## Preventing Flaky Tests

| Cause | Fix |
|-------|-----|
| Element not yet visible | `waitForExistence(timeout:)` before interacting |
| Animations in progress | Disable via launch env or wait for completion |
| Hardcoded sleep | Replace with `waitForExistence` or predicate expectations |
| Localized string matching | Use `accessibilityIdentifier` |
| Shared state | Reset via launch arguments |
| Network dependency | Mock data via launch environment |
