# XCTest Performance, Power, and Energy Testing Reference

Use `import XCTest` for performance benchmarks. Swift Testing has no `measure {}` equivalent.

## XCTMetric Subclasses

| Metric | Measures |
|--------|----------|
| `XCTClockMetric` | Wall-clock elapsed time |
| `XCTCPUMetric` | CPU time, cycles, instructions retired |
| `XCTMemoryMetric` | Physical memory (peak, average) |
| `XCTStorageMetric` | Disk I/O (bytes written, bytes read) |
| `XCTOSSignpostMetric` | Duration of `os_signpost` intervals, animation hitch metrics |
| `XCTHitchMetric` | UI responsiveness and fluidity (Xcode 26+) |

## Basic Performance Tests

Always use specific `XCTMetric` subclasses rather than bare `measure {}`. Bare `measure {}` only records wall-clock time. Specific metrics give richer, more actionable data.

```swift
import XCTest

class SortPerformanceTests: XCTestCase {

    // WRONG — bare measure only records clock time
    func testSort_bad() {
        measure { data.sort() }
    }

    // CORRECT — explicit metrics
    func testSortPerformance() {
        var data = (0..<10_000).map { _ in Int.random(in: 0...100_000) }
        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric()
        ]) {
            data.sort()
        }
    }

    // Multiple metrics simultaneously for correlation
    func testComplexOperation() {
        measure(metrics: [
            XCTClockMetric(),
            XCTCPUMetric(),
            XCTMemoryMetric(),
            XCTStorageMetric()
        ]) {
            performComplexOperation()
        }
    }

    // Custom iteration count (default is 5)
    func testWithOptions() {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(options: options) {
            loadLargeDataset()
        }
    }
}
```

## Manual Start/Stop Measurement

Use when setup code within the block should not be measured:

```swift
func testProcessingOnly() {
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        // Setup — NOT measured
        let data = generateTestData()

        startMeasuring()
        processData(data)
        stopMeasuring()

        // Teardown — NOT measured
    }
}
```

## Baselines

Baselines are set through Xcode, not in code:

1. Run the performance test once.
2. Click the grey diamond in the gutter next to the test.
3. Click **Set Baseline** in the popover.
4. Subsequent runs fail if the result exceeds baseline + allowed deviation (default 10%).
5. Baselines are per-device configuration — a baseline recorded on one device model cannot be used on another.
6. Baseline files are stored in `xcshareddata` inside the `.xcodeproj`.

## Energy and Power Testing

Apple does not provide a dedicated energy metric. Energy is measured indirectly through signpost duration, CPU activity, and tooling outside of XCTest.

### Using XCTOSSignpostMetric for Code Sections

Instrument your app code with `os_signpost`, then measure that interval in tests.

**Step 1: Add signposts to your app code**

```swift
import os

extension OSLog {
    static let imageProcessing = OSLog(
        subsystem: "com.myapp",
        category: "ImageProcessing"
    )
}

func processImage(_ image: UIImage) -> UIImage {
    os_signpost(.begin, log: .imageProcessing, name: "ProcessImage")
    let result = applyFilters(to: image)
    os_signpost(.end, log: .imageProcessing, name: "ProcessImage")
    return result
}
```

**Step 2: Measure in tests**

```swift
class EnergyTests: XCTestCase {

    func testImageProcessingPerformance() {
        let metric = XCTOSSignpostMetric(
            subsystem: "com.myapp",
            category: "ImageProcessing",
            name: "ProcessImage"
        )

        measure(metrics: [metric]) {
            let app = XCUIApplication()
            app.launch()
            app.buttons["processImage"].tap()
        }
    }
}
```

### Application Launch Performance

```swift
func testLaunchPerformance() {
    measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
        XCUIApplication().launch()
    }
}
```

### Combining Metrics for Power Analysis

Combine signpost metrics with CPU and memory to understand power impact:

```swift
func testPowerProfile() {
    let signpostMetric = XCTOSSignpostMetric(
        subsystem: "com.myapp",
        category: "Sync",
        name: "FullSync"
    )

    measure(metrics: [
        signpostMetric,
        XCTCPUMetric(),
        XCTMemoryMetric()
    ]) {
        let app = XCUIApplication()
        app.launch()
        app.buttons["startSync"].tap()
        let done = app.staticTexts["syncComplete"]
        _ = done.waitForExistence(timeout: 30)
    }
}
```

### Power Measurement Beyond XCTest

For deeper power analysis, use these complementary tools:

- **Xcode Energy Gauge** (Debug Navigator): Live energy impact while debugging (Low / High / Very High). Blue bars = your app's work, red bars = system resources your app forced active.
- **Power Profiler** (Instruments, Xcode 17+): Records power traces. Use for before/after comparisons and establishing baselines.
- **MetricKit** (`MXAppRunTimeMetric`, `MXCPUMetric`): Production energy diagnostics from real users. Useful for catching issues that only appear in the wild.
- **Xcode Organizer**: Aggregated energy metrics from App Store users.

The recommended workflow: XCTest metrics during development → MetricKit in beta/release → Xcode Organizer in production.

## Test Scheme Configuration for Performance Tests

Performance tests require a specific scheme configuration for accurate results:

1. **Use a separate test scheme** dedicated to performance tests.
2. **Select Release build configuration** — debug builds include overhead.
3. **Disable the debugger** — it adds latency.
4. **Disable automatic screenshot collection**.
5. **Turn off code coverage** — it instruments code and affects timing.
6. **Disable all diagnostics**: Runtime Sanitization, Runtime API Checking, Memory Management diagnostics.

## Best Practices

- Always use specific `XCTMetric` subclasses — bare `measure {}` gives limited data.
- Combine multiple metrics in a single `measure()` call to correlate results.
- **Run on physical devices** — simulators are not representative for performance.
- Use `startMeasuring()` / `stopMeasuring()` to exclude setup and teardown.
- Isolate what you are measuring — avoid combining multiple operations in one test.
- Run tests multiple times to account for system variation.
- Accept that hitch metric baselines may need higher standard deviation tolerance (~400%) due to natural variance.

## Gotchas

- Hitch-related metrics (count, duration, ratio) can have high standard deviation, causing baseline failures. Increase max standard deviation tolerance if needed.
- Baselines are device-specific. A baseline from iPhone 15 Pro won't apply to iPhone 14.
- Simulator only supports Duration — frame rate, hitch count, and other animation metrics require a real device.
- The first iteration of `measure {}` is not counted (it's a warmup run).
