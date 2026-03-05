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

## Screenshot Capture and Review

Capture screenshots of every screen across appearance variants, themes, and user types. This is essential for visual QA, design review, and App Store submissions.

### Taking Screenshots in Tests

Use `XCUIScreen.main.screenshot()` for full-device captures. Always set `.keepAlways` — without it, Xcode deletes attachments from passing tests.

```swift
func takeScreenshot(name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways  // Critical: keeps screenshots even when tests pass
    add(attachment)
}
```

Use `XCUIScreen.main` instead of `app.screenshot()` — it captures the full device screen including status bar and system UI.

### Multi-Variant Screenshot Test Pattern

Define variants as structs and run the same walkthrough across all combinations:

```swift
final class AppearanceScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    private struct Variant {
        let theme: String       // e.g. "original", "georgia"
        let appearance: String  // "light" or "dark"
        let modeArg: String     // "--light-mode" or "--dark-mode"
        var suffix: String { "\(theme)_\(appearance)" }
    }

    private static let variants = [
        Variant(theme: "original", appearance: "light", modeArg: "--light-mode"),
        Variant(theme: "original", appearance: "dark",  modeArg: "--dark-mode"),
        Variant(theme: "georgia",  appearance: "light", modeArg: "--light-mode"),
        Variant(theme: "georgia",  appearance: "dark",  modeArg: "--dark-mode"),
    ]

    // One test method per variant — each appears separately in test results
    func testCapture_OriginalLight() { captureAllScreens(variant: Self.variants[0]) }
    func testCapture_OriginalDark()  { captureAllScreens(variant: Self.variants[1]) }
    func testCapture_GeorgiaLight()  { captureAllScreens(variant: Self.variants[2]) }
    func testCapture_GeorgiaDark()   { captureAllScreens(variant: Self.variants[3]) }

    private func captureAllScreens(variant: Variant) {
        continueAfterFailure = true  // Don't stop on first failure — capture everything possible
        let v = variant.suffix

        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--theme", variant.theme, variant.modeArg]
        app.launch()

        // Navigate to each screen and capture
        navigateToTab("Play")
        takeScreenshot(name: "01_Play/01_Default_\(v)")

        navigateToTab("Settings")
        takeScreenshot(name: "02_Settings/01_Default_\(v)")
        // ... continue for each screen
    }
}
```

Key points:
- **One test method per variant** so each runs independently and appears in results separately.
- **Set `continueAfterFailure = true`** in screenshot tests — you want to capture as many screens as possible even if one navigation fails.
- **Use structured names** with section prefixes (`01_Play/`, `02_Settings/`) for organized export.

### User-Type Variants

For premium-gated or role-specific screens, add user type to the matrix:

```swift
private enum UserType: String {
    case subscriber, gamePass, guest

    var launchArgs: [String] {
        switch self {
        case .subscriber: return ["--simulate-subscription"]
        case .gamePass:   return ["--initial-game-credits", "3"]
        case .guest:      return []
        }
    }
}

// Test: 4 variants x 3 user types = 12 test methods for premium screens
func testCapture_OriginalLight_Subscriber() {
    capturePremiumScreens(variant: Self.variants[0], userType: .subscriber)
}
```

### Test Base Class for Screenshot Tests

Extract common utilities into a base class:

```swift
class UITestBase: XCTestCase {
    var app: XCUIApplication!

    enum Timeout {
        static let short: TimeInterval = 2.0
        static let medium: TimeInterval = 5.0
        static let long: TimeInterval = 10.0
    }

    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func navigateToTab(_ name: String) {
        let tabId = "tab-\(name.lowercased())"
        let button = app.buttons[tabId]
        guard button.waitForExistence(timeout: Timeout.short) else {
            XCTFail("Tab '\(name)' not found")
            return
        }
        button.tap()
    }

    func dismissSheet() {
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        top.press(forDuration: 0.1, thenDragTo: bottom)
    }

    func scrollToElement(_ element: XCUIElement, maxScrolls: Int = 10) {
        let container = app.scrollViews.firstMatch
        for _ in 0..<maxScrolls {
            if element.isHittable { return }
            container.swipeUp()
        }
    }
}
```

## Running Tests on Real Devices

### Device Destination

List connected devices:

```bash
xctrace list devices
```

Run tests targeting a specific device by UDID (most reliable):

```bash
xcodebuild test \
  -scheme MyApp \
  -destination 'platform=iOS,id=00008140-0011256C3EA2801C' \
  -only-testing:MyAppUITests/AppearanceScreenshotTests \
  -resultBundlePath ./TestResults.xcresult
```

If only one device of a type is connected, you can use the name:

```bash
-destination 'platform=iOS,name=John Marc's iPhone'
```

**Important:** With multiple iPhones connected, use the UDID to avoid ambiguity.

### Signing for Test Targets

Both the app target and the UI test target need signing. In Xcode:
1. Select your project > UI test target > **Signing & Capabilities**
2. Set the same team and let Xcode manage provisioning

### Fresh Install for NUX/Onboarding Capture

To capture the true New User Experience (first launch, permission dialogs, onboarding), uninstall the app before running tests:

```bash
# Uninstall the app (uses devicectl for real devices)
xcrun devicectl device uninstall app \
  --device 00008140-0011256C3EA2801C \
  com.myapp.MyApp

# Then run tests — xcodebuild will do a fresh install
xcodebuild test \
  -scheme MyApp \
  -destination 'platform=iOS,id=00008140-0011256C3EA2801C' \
  -only-testing:MyAppUITests/AppearanceScreenshotTests \
  -resultBundlePath ./TestResults.xcresult
```

**Why not uninstall inside the test?** After `app.launch()`, xcodebuild has already installed the app. If you uninstall mid-test, the next `app.launch()` fails because the test runner doesn't reinstall. Always uninstall *before* `xcodebuild test`.

For simulators, use `simctl` instead:

```bash
xcrun simctl uninstall booted com.myapp.MyApp
```

## Extracting Screenshots from Test Results

### Export Attachments

After tests complete, extract all screenshots from the `.xcresult` bundle:

```bash
xcrun xcresulttool export attachments \
  --path ./TestResults.xcresult \
  --output-path ./Screenshots
```

This exports all attachments as PNG files with UUID filenames and generates a `manifest.json` with metadata.

### Manifest Structure

The manifest maps UUID filenames to human-readable suggested names:

```json
[
  {
    "attachments": [
      {
        "exportedFileName": "F61C0A79-406F-4E57-8901-F05996D7F4E4.png",
        "suggestedHumanReadableName": "01_Play01_Default_original_light_0_UUID.png",
        "timestamp": 1772731322.385,
        "isAssociatedWithFailure": false
      }
    ],
    "testIdentifier": "AppearanceScreenshotTests/testCapture_OriginalLight()"
  }
]
```

### Rename Screenshots

Use the manifest to create human-readable filenames:

```python
#!/usr/bin/env python3
import json, os, re, shutil

with open("Screenshots/manifest.json") as f:
    data = json.load(f)

for entry in data:
    for item in entry.get("attachments", []):
        src = f"Screenshots/{item['exportedFileName']}"
        suggested = item["suggestedHumanReadableName"]
        # Strip trailing _0_UUID.png
        clean = re.sub(r"_\d+_[A-F0-9-]+\.png$", ".png", suggested)
        clean = clean.replace("/", "_")
        if os.path.exists(src):
            shutil.copy2(src, f"Screenshots/{clean}")
```

### Generate a Screenshot Review Website

After renaming screenshots, generate a static HTML page so stakeholders can browse all captured screens in a browser. The script groups images by screen name (the portion before the variant suffix) and displays variants side by side.

```python
#!/usr/bin/env python3
"""Generate an HTML gallery from renamed screenshots and open it in the default browser."""
import os, re, webbrowser
from collections import defaultdict
from pathlib import Path

SCREENSHOTS_DIR = "Screenshots"
OUTPUT_FILE = os.path.join(SCREENSHOTS_DIR, "index.html")

def build_gallery():
    images = sorted(
        f for f in os.listdir(SCREENSHOTS_DIR)
        if f.endswith(".png") and not re.match(r"^[A-F0-9-]{36}\.png$", f)  # skip UUID originals
    )

    # Group by screen: strip variant suffix (e.g. _original_light.png) to get screen name
    groups = defaultdict(list)
    for img in images:
        # Screen name is everything up to the last two underscore-separated segments before .png
        # e.g. "01_Play_01_Default_original_light.png" → screen "01_Play_01_Default"
        stem = Path(img).stem
        parts = stem.rsplit("_", 2)
        screen = parts[0] if len(parts) >= 3 else stem
        groups[screen].append(img)

    html_parts = [
        "<!DOCTYPE html>",
        "<html><head><meta charset='utf-8'>",
        "<title>Screenshot Review</title>",
        "<style>",
        "  body { font-family: -apple-system, system-ui, sans-serif; margin: 2rem; background: #f5f5f7; }",
        "  h1 { font-size: 1.5rem; }",
        "  h2 { font-size: 1.1rem; margin-top: 2rem; border-bottom: 1px solid #ccc; padding-bottom: 0.3rem; }",
        "  .grid { display: flex; flex-wrap: wrap; gap: 1rem; }",
        "  .card { background: #fff; border-radius: 8px; padding: 0.5rem; box-shadow: 0 1px 3px rgba(0,0,0,0.12); }",
        "  .card img { max-height: 500px; border-radius: 4px; display: block; }",
        "  .card .label { font-size: 0.75rem; color: #666; margin-top: 0.3rem; text-align: center; }",
        "</style></head><body>",
        "<h1>Screenshot Review</h1>",
    ]

    for screen, imgs in groups.items():
        html_parts.append(f"<h2>{screen.replace('_', ' ')}</h2>")
        html_parts.append("<div class='grid'>")
        for img in imgs:
            label = Path(img).stem.replace(screen + "_", "").replace("_", " ")
            html_parts.append(
                f"<div class='card'><img src='{img}' alt='{img}'>"
                f"<div class='label'>{label}</div></div>"
            )
        html_parts.append("</div>")

    html_parts.append("</body></html>")

    with open(OUTPUT_FILE, "w") as f:
        f.write("\n".join(html_parts))

    webbrowser.open(f"file://{os.path.abspath(OUTPUT_FILE)}")
    print(f"Opened {OUTPUT_FILE}")

if __name__ == "__main__":
    build_gallery()
```

Run it after extracting and renaming:

```bash
# Full pipeline: export → rename → generate website
xcrun xcresulttool export attachments \
  --path ./TestResults.xcresult \
  --output-path ./Screenshots

python3 rename_screenshots.py   # the rename script from above
python3 generate_gallery.py     # generates Screenshots/index.html and opens it
```

The generated page groups screenshots by screen, shows variant labels (theme + appearance) beneath each image, and automatically opens in the default browser.

### Other xcresulttool Commands

```bash
# Test summary (pass/fail counts)
xcrun xcresulttool get test-results summary --path ./TestResults.xcresult

# List all tests
xcrun xcresulttool get test-results tests --path ./TestResults.xcresult

# Export only failure attachments
xcrun xcresulttool export attachments \
  --path ./TestResults.xcresult \
  --output-path ./FailureScreenshots \
  --only-failures
```

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
