# XCUITest UI Automation and Animation Testing Reference

Use `import XCTest` for all UI tests. XCUITest is part of the XCTest framework.

## Test Structure

```swift
import XCTest

class LoginUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false  // Always set this — UI tests should stop on first failure
        app.launch()
    }
}
```

## Element Queries

Always prefer accessibility identifiers over localized strings. Localized strings break with different languages.

### Setting Identifiers

```swift
// SwiftUI
Button("Submit") { ... }
    .accessibilityIdentifier("submitButton")

List(items) { item in
    Text(item.name)
        .accessibilityIdentifier("item_\(item.id)")
}
.accessibilityIdentifier("itemsList")

// UIKit
button.accessibilityIdentifier = "submitButton"
```

### Querying Elements

```swift
// By accessibility identifier (most reliable)
let submit = app.buttons["submitButton"]

// By label text (avoid for localized apps)
let welcome = app.staticTexts["Welcome"]

// By type
let firstField = app.textFields.firstMatch
let allButtons = app.buttons.allElementsBoundByIndex

// Descendant queries
let deleteBtn = app.cells["userCell"].buttons["delete"]

// Predicate-based
let predicate = NSPredicate(format: "label CONTAINS[c] 'save'")
let saveBtn = app.buttons.matching(predicate).firstMatch

// Other element types
let navBar = app.navigationBars["Settings"]
let toggle = app.switches["darkModeToggle"]
let slider = app.sliders["volumeSlider"]
```

## Waiting for Elements

Never interact with an element without ensuring it exists first. This is the #1 cause of flaky UI tests.

```swift
// waitForExistence — preferred for simple appearance checks
func testAsyncLoad() {
    app.buttons["loadData"].tap()

    let label = app.staticTexts["dataLoaded"]
    XCTAssertTrue(label.waitForExistence(timeout: 10), "Data should load within 10s")
}

// Predicate expectation — for complex conditions
func testButtonBecomesEnabled() {
    let predicate = NSPredicate(format: "isEnabled == true")
    let expectation = XCTNSPredicateExpectation(
        predicate: predicate,
        object: app.buttons["submitButton"]
    )
    let result = XCTWaiter.wait(for: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed)
}

// Wait for element to disappear
func testSpinnerDisappears() {
    let spinner = app.activityIndicators["loadingSpinner"]
    let gone = NSPredicate(format: "exists == false")
    let expectation = XCTNSPredicateExpectation(predicate: gone, object: spinner)
    XCTWaiter.wait(for: [expectation], timeout: 10)
}
```

## Launch Arguments and Environment

Use launch arguments to put the app into a known, testable state:

```swift
func testWithMockData() {
    app.launchArguments = [
        "--uitesting",
        "--reset-state",
        "-AppleLanguages", "(en)"
    ]
    app.launchEnvironment = [
        "API_BASE_URL": "http://localhost:8080",
        "USE_MOCK_DATA": "1",
        "ANIMATION_SPEED": "0"  // Disable animations for faster, less flaky tests
    ]
    app.launch()
}

// In your app code, check:
// CommandLine.arguments.contains("--uitesting")
// ProcessInfo.processInfo.environment["USE_MOCK_DATA"] == "1"
```

## Animation and Scroll Performance Testing

**Important:** Animation and scroll metrics require a physical device. Simulators only report Duration.

### Scroll Performance

```swift
class ScrollPerformanceTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    // Scroll deceleration phase only
    func testScrollDeceleration() {
        let measureOptions = XCTMeasureOptions()
        measureOptions.invocationOptions = [.manuallyStop]

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric],
                options: measureOptions) {
            app.collectionViews.firstMatch.swipeUp(velocity: .fast)
            stopMeasuring()
            // Reset state for next iteration
            app.collectionViews.firstMatch.swipeDown(velocity: .fast)
        }
    }

    // Scroll dragging phase
    func testScrollDragging() {
        measure(metrics: [XCTOSSignpostMetric.scrollDraggingMetric]) {
            app.scrollViews.firstMatch.swipeUp()
        }
    }

    // Navigation transition
    func testNavigationTransition() {
        measure(metrics: [XCTOSSignpostMetric.navigationTransitionMetric]) {
            app.buttons["showDetail"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
    }
}
```

### Available UIKit Sub-Metrics

```swift
extension XCTOSSignpostMetric {
    open class var navigationTransitionMetric: XCTMetric { get }
    open class var customNavigationTransitionMetric: XCTMetric { get }
    open class var scrollDecelerationMetric: XCTMetric { get }
    open class var scrollDraggingMetric: XCTMetric { get }
}
```

### Hitch Metrics

When using animation signpost metrics on a real device, Xcode automatically reports:

| Metric | Description |
|--------|-------------|
| Duration | Total animation time |
| Frame rate | Measured fps |
| Frame count | Total frames rendered |
| Hitch count | Number of hitches |
| Hitch total duration | Cumulative time spent hitching |
| Hitch time ratio | `hitch_duration / animation_duration` (ms/s) |

**Hitch quality thresholds** (Apple guideline):
- **< 5 ms/s**: Good
- **5–10 ms/s**: Users notice hitches — investigate
- **>= 10 ms/s**: Distracting — take immediate action

The hitch time ratio is preferred over FPS because it normalizes across different durations and is meaningful even when the app intentionally runs at lower frame rates (e.g., 30fps video, 24fps animation).

### Custom Animation Signpost

**Step 1: Instrument your app**

```swift
import os

let renderLog = OSLog(subsystem: "com.myapp", category: .pointsOfInterest)

func animateCardFlip() {
    os_signpost(.animationBegin, log: renderLog, name: "CardFlip")
    UIView.animate(withDuration: 0.3) {
        // animation
    } completion: { _ in
        os_signpost(.end, log: renderLog, name: "CardFlip")
    }
}
```

Note: Use `.animationBegin` (not `.begin`) for animation signposts. This tells the system to collect hitch metrics for the interval.

**Step 2: Measure in tests**

```swift
func testCardFlipHitchRate() {
    let metric = XCTOSSignpostMetric(
        subsystem: "com.myapp",
        category: "PointsOfInterest",
        name: "CardFlip"
    )

    measure(metrics: [metric]) {
        app.buttons["flipCard"].tap()
        _ = app.staticTexts["flipped"].waitForExistence(timeout: 2)
    }
}
```

### Resetting State Between Iterations

Always reset scroll/navigation state between iterations using manual stop:

```swift
func testScrollPerformance() {
    let measureOptions = XCTMeasureOptions()
    measureOptions.invocationOptions = [.manuallyStop]

    measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric],
            options: measureOptions) {
        app.collectionViews.firstMatch.swipeUp(velocity: .fast)
        stopMeasuring()
        app.collectionViews.firstMatch.swipeDown(velocity: .fast)  // Reset
    }
}
```

## Light/Dark Mode Appearance Testing

XCUITest does not have a built-in API to switch appearance. Use a launch argument that your app checks at startup to override the interface style.

### Step 1: Add Appearance Override to Your App

```swift
// In your App struct or SceneDelegate — guard behind a DEBUG flag
#if DEBUG
func applyTestAppearance(to window: UIWindow?) {
    if CommandLine.arguments.contains("--dark-mode") {
        window?.overrideUserInterfaceStyle = .dark
    } else if CommandLine.arguments.contains("--light-mode") {
        window?.overrideUserInterfaceStyle = .light
    }
}
#endif
```

For SwiftUI, apply in your `App` body or use a `WindowGroup` modifier:

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if DEBUG
                .onAppear {
                    if CommandLine.arguments.contains("--dark-mode") {
                        UIApplication.shared.connectedScenes
                            .compactMap { $0 as? UIWindowScene }
                            .flatMap(\.windows)
                            .forEach { $0.overrideUserInterfaceStyle = .dark }
                    }
                }
                #endif
        }
    }
}
```

### Step 2: Launch with Appearance in Tests

```swift
class DarkModeUITests: XCTestCase {
    func testDarkModeLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-mode"]
        app.launch()

        // Test your UI in dark mode
        XCTAssertTrue(app.staticTexts["welcomeLabel"].exists)
        try app.performAccessibilityAudit(for: .contrast)
    }

    func testLightModeLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--light-mode"]
        app.launch()

        XCTAssertTrue(app.staticTexts["welcomeLabel"].exists)
        try app.performAccessibilityAudit(for: .contrast)
    }
}
```

### Testing Both Appearances Systematically

Run the same test logic against both appearances to catch mode-specific issues:

```swift
class AppearanceTests: XCTestCase {

    func verifyMainScreen(app: XCUIApplication) throws {
        XCTAssertTrue(app.staticTexts["welcomeLabel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["getStarted"].exists)

        // Contrast audit catches colors that pass in one mode but fail in another
        try app.performAccessibilityAudit(for: .contrast)
    }

    func testMainScreen_lightMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--light-mode"]
        app.launch()
        try verifyMainScreen(app: app)
    }

    func testMainScreen_darkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-mode"]
        app.launch()
        try verifyMainScreen(app: app)
    }
}
```

### Snapshot Testing for Appearance (Unit Test Target)

For pixel-level verification of both appearances, use snapshot testing (e.g., [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)):

```swift
import SnapshotTesting
import XCTest

class AppearanceSnapshotTests: XCTestCase {

    func testSettingsScreen_lightMode() {
        let controller = UIHostingController(rootView: SettingsView())
        controller.overrideUserInterfaceStyle = .light
        assertSnapshot(of: controller, as: .image(on: .iPhone13Pro))
    }

    func testSettingsScreen_darkMode() {
        let controller = UIHostingController(rootView: SettingsView())
        controller.overrideUserInterfaceStyle = .dark
        assertSnapshot(of: controller, as: .image(on: .iPhone13Pro))
    }
}
```

You can also pass traits directly:

```swift
let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
assertSnapshot(of: controller, as: .image(on: .iPhone13Pro, traits: darkTraits))
```

### Common Dark Mode Issues to Test For

- Text that is readable in light mode but invisible against dark backgrounds (and vice versa).
- Hardcoded colors (e.g., `UIColor.black`) instead of semantic colors (`UIColor.label`, `UIColor.systemBackground`).
- Images or icons that lack dark mode variants.
- Contrast ratios that pass in one mode but fail in the other — `.contrast` audit catches this.
- Separator lines or borders that disappear in one mode.

## Accessibility Audits (iOS 17+ / Xcode 15+)

Automated accessibility testing without third-party tools.

### Available Audit Types

| Type | Checks |
|------|--------|
| `.contrast` | Sufficient color contrast between text and backgrounds |
| `.elementDetection` | All interactive elements are discoverable |
| `.hitRegion` | Interactive elements meet minimum touch target sizes |
| `.sufficientElementDescription` | Elements have meaningful accessibility labels |
| `.dynamicType` | Text respects system font size adjustments |
| `.textClipped` | Text is not clipped or truncated |
| `.trait` | Elements have correct accessibility traits |

### Basic Audit

```swift
func testAccessibility() throws {
    app.launch()
    try app.performAccessibilityAudit()
}
```

### Audit Specific Types

```swift
func testContrastAndDynamicType() throws {
    app.launch()
    try app.performAccessibilityAudit(for: [.contrast, .dynamicType])
}
```

### Exclude Specific Types

```swift
func testAccessibilityWithExclusions() throws {
    app.launch()
    try app.performAccessibilityAudit(
        for: .all.subtracting(.sufficientElementDescription)
    )
}
```

### Ignore Known Issues

Return `true` from the closure to ignore an issue:

```swift
func testAccessibilityIgnoringKnown() throws {
    app.launch()
    try app.performAccessibilityAudit { issue in
        // Ignore hit region issues on price labels (intentionally small)
        if let element = issue.element,
           element.label.contains("Price"),
           issue.auditType == .hitRegion {
            return true  // ignore this issue
        }
        return false  // fail on everything else
    }
}
```

### Contrast and Visibility Testing

The `.contrast` audit checks that text and interactive elements meet minimum contrast ratios. Run it in **both** light and dark mode to catch mode-specific failures.

```swift
class ContrastTests: XCTestCase {

    func testContrast_lightMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--light-mode"]
        app.launch()
        try app.performAccessibilityAudit(for: .contrast)
    }

    func testContrast_darkMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--dark-mode"]
        app.launch()
        try app.performAccessibilityAudit(for: .contrast)
    }

    // Test that text is not clipped at large Dynamic Type sizes
    func testTextVisibility_largestType() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--accessibility-size-xxxl"]
        app.launch()
        try app.performAccessibilityAudit(for: [.textClipped, .dynamicType])
    }

    // Full visibility audit: contrast + clipping + dynamic type
    func testFullVisibility() throws {
        let app = XCUIApplication()
        app.launch()
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .dynamicType])
    }
}
```

**What `.contrast` checks:** The audit validates that foreground/background color pairs meet Apple's minimum contrast ratio requirements, aligned with WCAG 2.1 guidelines. It detects issues like light gray text on white backgrounds, or dark text on dark mode backgrounds.

**What `.textClipped` checks:** Detects text that overflows its container and is cut off — common when Dynamic Type is enabled at larger sizes or when labels have fixed widths.

**What `.dynamicType` checks:** Ensures text elements respond to the user's preferred font size rather than using hardcoded sizes.

**Combine with appearance testing:** Always run contrast audits in both light and dark mode. A color that passes in light mode may fail in dark mode. The systematic approach:

```swift
// Run this on every screen, in both appearances
func auditVisibility(app: XCUIApplication) throws {
    try app.performAccessibilityAudit(for: [.contrast, .textClipped, .dynamicType])
}
```

### Multi-Screen Audit Pattern

Audits only check elements currently on screen. Navigate through your app to audit every screen:

```swift
func testAccessibilityAcrossAllScreens() throws {
    let app = XCUIApplication()
    app.launch()

    // Audit main screen
    try app.performAccessibilityAudit()

    // Navigate to settings and audit
    app.buttons["settingsButton"].tap()
    try app.performAccessibilityAudit()

    // Navigate to profile and audit
    app.buttons["profileButton"].tap()
    try app.performAccessibilityAudit()
}
```

### CI/CD Integration

Run accessibility audits from the command line:

```bash
xcodebuild test \
  -project MyApp.xcodeproj \
  -scheme AccessibilityTests \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0' \
  -derivedDataPath derived_data
```

Results are available as `.xcresult` bundles in `derived_data/Logs/Test/`.

### Best Practices for Accessibility and Visibility Testing

- **Run audits on every screen**, not just the main screen.
- **Audit in both light and dark mode** — contrast failures are often mode-specific.
- **Audit after navigation** to catch issues on secondary screens.
- **Use `.all` by default** and only exclude types with documented justification.
- **Review failures in Xcode's Report Navigator** — it includes element screenshots.
- **Use semantic colors** (`UIColor.label`, `UIColor.systemBackground`, SwiftUI `.primary`, `.background`) instead of hardcoded colors.
- **Use Dynamic Type** (`.largeTitle`, `.body`) and never hardcode font sizes.
- **Set `continueAfterFailure = true`** in accessibility-specific tests to report all issues rather than stopping at the first.
- **Pair automated audits with manual VoiceOver testing** — automated audits catch structural issues but cannot verify that the VoiceOver reading order makes sense.

## Page Object Pattern

Encapsulate screen interactions for reuse and readability. This makes tests resilient to UI changes — if a button moves, you update the page object, not every test.

```swift
struct LoginPage {
    let app: XCUIApplication

    var usernameField: XCUIElement { app.textFields["usernameField"] }
    var passwordField: XCUIElement { app.secureTextFields["passwordField"] }
    var loginButton: XCUIElement { app.buttons["loginButton"] }
    var errorLabel: XCUIElement { app.staticTexts["errorLabel"] }

    func login(username: String, password: String) {
        usernameField.tap()
        usernameField.typeText(username)
        passwordField.tap()
        passwordField.typeText(password)
        loginButton.tap()
    }
}

// Usage
func testLoginFlow() {
    let page = LoginPage(app: app)
    page.login(username: "admin", password: "wrong")
    XCTAssertTrue(page.errorLabel.waitForExistence(timeout: 3))
}
```

## Preventing Flaky Tests

The most common causes and fixes:

| Cause | Fix |
|-------|-----|
| Element not yet visible | Use `waitForExistence(timeout:)` before interacting |
| Animations in progress | Disable animations via launch environment or wait for completion |
| Hardcoded sleep/delays | Replace with `waitForExistence` or predicate expectations |
| Localized string matching | Use `accessibilityIdentifier` instead |
| Shared state between tests | Reset app state via launch arguments |
| Network dependency | Use mock data via launch environment |

## Best Practices

- **Always use `accessibilityIdentifier`**, never match on display text.
- **Set `continueAfterFailure = false`** in `setUpWithError()`.
- **Use launch arguments** to put the app into a known state.
- **Use `swipeUp(velocity: .fast)`** for scroll tests to generate enough frames for meaningful metrics.
- **Run animation/scroll tests on physical devices** — simulators don't produce accurate hitch data.
- **Reset state between measure iterations** using `manuallyStop` and a reset action.
- **Use a separate test scheme** for performance tests with Release config and diagnostics disabled.
- **Triage flaky tests promptly** — look for race conditions, missing waits, or missing accessibility identifiers.
- **Use descriptive test names** that explain the scenario being tested, not just the method under test.
