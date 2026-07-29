# Test Reliability: Concurrency, Timing, and the CI Host

Reference for writing tests that stay green on a loaded, shared, or newer-OS CI
runner — not just on an idle laptop. These are the failures that don't reproduce
locally, "pass locally / crash in CI," or flake one run in ten. Every rule here
came from a real crash log, not a style guide.

The through-line: **assert correctness, never speed or timing; keep the test host
inert; and read the actual crash before you "fix" anything.**

---

## 1. Never assert a wall-clock UPPER bound

An `elapsed < X` assertion tests *how fast the machine is*, not whether the code
is correct. It passes on an idle laptop and fails on a loaded/shared CI runner
where a sub-second operation can take 5+ seconds under contention.

```swift
// ❌ Flaky: asserts speed. A 0.3s timeout op can take seconds under load.
let start = Date()
let ok = await inbox.waitForAll(expected: 5, timeout: 0.3)
#expect(ok == false)
#expect(elapsed >= 0.3)          // ✅ meaningful: it waited the timeout
#expect(elapsed < 1.0)           // ❌ flaky "sanity" bound — DELETE THIS

// ✅ Keep the correctness assertions; let `.timeLimit` guard true hangs.
@Test("times out", .timeLimit(.minutes(1)))
func waitTimesOut() async {
    let ok = await inbox.waitForAll(expected: 5, timeout: 0.3)
    #expect(ok == false)         // the contract
    #expect(elapsed >= 0.3)      // didn't return early
    // no upper bound: `.timeLimit` already catches a real hang
}
```

The `.timeLimit()` trait is the *correct* tool for "it shouldn't hang forever."
A hand-rolled `elapsed < N` upper bound is not — it conflates a hang with a
slow machine.

## 2. Poll until a condition; don't `sleep` a fixed amount

Waiting for background/async work (a periodic flush, a debounce, a drain) with a
fixed `Task.sleep` is a bet that the work finishes within that window. Under load
the background task is starved and the bet loses.

```swift
// ❌ Fixed wait — under-waits a starved periodic task on a busy runner.
try await Task.sleep(for: .milliseconds(500))
#expect(await recorder.count == 5)

// ✅ Poll to a generous ceiling. Fast when idle, tolerant under load.
@discardableResult
func eventually(
    timeout: Duration = .seconds(5),
    poll: Duration = .milliseconds(25),
    _ condition: () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: poll)
    }
    return await condition()
}

await eventually { await recorder.count == 5 }
#expect(await recorder.count == 5)
```

## 3. When timing IS the contract, measure it RELATIVELY

Some tests genuinely verify a duration ("the 0ms drain window is faster than the
250ms default"). An absolute bound is unfixable — pick it low and it flakes under
load; pick it high and it stops distinguishing the two cases. Compare two
measurements on the *same machine* instead: the **difference** cancels out the
shared I/O overhead and stays stable at any load.

```swift
// ✅ The default's fixed sleep is additive on top of whatever overhead the
// runner is under, so the GAP holds on a fast Mac and a contended runner alike.
let baseline = measureStop(drainMs: 250)   // overhead + 250ms
let fast     = measureStop(drainMs: 0)      // overhead
#expect(fast + .milliseconds(100) < baseline)   // gap ≈ 250ms, load-independent
```

## 4. Guarantee "some but not all" by construction, not by racing the clock

A test that wants "partially drained at timeout" by racing a drain rate against a
timeout is inherently timing-dependent. Make the outcome structural instead:

```swift
// ✅ 100 items @ ~20ms can't fully drain in 0.5s even idle (residual guaranteed);
//    decrement-FIRST guarantees ≥1 lands even under load (progress guaranteed).
let box = CountBox(count: 100)
let drainer = Task {
    while true {
        if box.isZero { break }
        box.decrement()                       // decrement first…
        try? await Task.sleep(for: .milliseconds(20))   // …then wait
    }
}
let remaining = await pollUntilZero(timeoutSec: 0.5) { box.count }
#expect(remaining > 0)     // can't fully drain 100 in 0.5s — structural
#expect(remaining < 100)   // ≥1 decrement landed — structural
```

Neither bound depends on an absolute rate — only on "some but not all," which is
true by construction.

---

## 5. Actor isolation and the Swift 6 / iOS 26+ runtime

The single highest-value lesson: **the newer runtime turns illegal actor
isolation into a hard trap** (`EXC_BREAKPOINT` / `SIGTRAP` via
`swift_task_isCurrentExecutor` → `_dispatch_assert_queue_fail`). Older runtimes
silently swapped executors and continued. So a latent bug is invisible for years,
then crashes the moment CI moves to a new simulator runtime — "passes locally,
crashes in CI" with an opaque `Crash: <App>`.

### 5a. A `@MainActor` type's `Codable` must not be decoded off-main

```swift
// ❌ @MainActor makes init(from:) MainActor-isolated. JSON decoding of a network
//    response runs OFF the main thread → hard trap on iOS 27.  Latent PROD crash.
@Observable @MainActor
final class Golfer: @preconcurrency Codable { ... }

// ✅ A wire/model type should be nonisolated. If it must stay a mutable class
//    that something Sendable holds, @unchecked Sendable keeps Sendability
//    (which @MainActor previously provided implicitly) without the isolation.
@Observable
final class Golfer: Codable, @unchecked Sendable { ... }   // decodes off-main safely
```

Rule: **types on the wire (Codable DTOs / models) should be nonisolated.**
`@preconcurrency Codable` silences the *compile* error but the *runtime* check
still fires.

### 5b. A mock callback runs off-main — don't invoke a `@MainActor` closure from it

`URLProtocol.startLoading()`, delegate callbacks, and completion handlers run on
framework background threads. If a test's handler closure is authored inside a
`@MainActor @Suite`, it inherits MainActor isolation, and calling it from the
background thread traps.

```swift
// ✅ Bridge to main before invoking a possibly-MainActor-isolated test handler.
override func startLoading() {
    guard let handler = Self.requestHandler else { ... }
    let result = Thread.isMainThread
        ? Result { try handler(request) }
        : DispatchQueue.main.sync { Result { try handler(request) } }
    ...
}
```

### 5c. The `@unchecked Sendable` box for sharing a continuation with a timeout

A `CheckedContinuation` isn't `Sendable`, but resuming it from any thread is safe.
To let a timeout `Task` and a callback race for it, box it and guard exactly-once
resume with a lock (see §6).

---

## 6. Continuation bridges need a defensive timeout

`withCheckedContinuation` that bridges a callback API (WCSession, CoreBluetooth,
any `reply:/error:` pair) **leaks and hangs the caller forever** if neither
callback ever fires — a wedged peer, a dropped message, or a test double that
records but never calls back. The symptom is
`SWIFT TASK CONTINUATION MISUSE: … leaked its continuation`, and it hangs the CI
job until its timeout.

```swift
// ✅ Race the callback against a timeout; resume exactly once from whichever wins.
private final class ReplyBox<T: Sendable>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    private var cont: CheckedContinuation<T, Error>?
    init(_ c: CheckedContinuation<T, Error>) { cont = c }
    func resume(_ block: (CheckedContinuation<T, Error>) -> Void) {
        let c: CheckedContinuation<T, Error>? = lock.withLock {
            if $0 { return nil }; $0 = true; defer { cont = nil }; return cont
        }
        if let c { block(c) }
    }
}

func sendWithAck(_ msg: Message) async throws {
    try await withCheckedThrowingContinuation { c in
        let box = ReplyBox(c)
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            box.resume { $0.resume(throwing: TransportError.timeout) }
        }
        adapter.send(msg,
            reply: { _ in timeout.cancel(); box.resume { $0.resume() } },
            error: { e in timeout.cancel(); box.resume { $0.resume(throwing: e) } })
    }
}
```

Note `<T: Sendable>` — the compiler flags "sending value risks data races"
otherwise; all real reply payloads (`Void`, dictionaries, `Data?`) are Sendable.

### Mocks must honor the callback contract

A mock that records the call but invokes *neither* the reply nor error handler
hangs the caller (it caused exactly the leak above). A real reachable transport
always invokes one — so must the mock:

```swift
func send(_ msg: Message, reply: ((Reply) -> Void)?, error: ((Error) -> Void)?) {
    record(msg)
    reply?(.init())   // ← deliver the ack a real peer always sends
}
```

---

## 7. Keep the unit-test host inert

The unit-test host **is the app** — its `@main` `App.init()` / `AppDelegate`
runs. If it boots the full service stack, tests inherit its background work:
network `Task`s that hang on a real endpoint, `for await` listeners that never
end, registration gates that park callers, crash-reporting SDKs that install
signal handlers. Any of these can keep the process alive past the iOS watchdog
(~10–23s) or park a test until it times out — and the crash lands on **whatever
test happens to be running**, not the cause.

`XCTestConfigurationFilePath` is set **only in the unit-test host** (not in a
UITest-launched app), which makes it the correct gate:

```swift
// In App.init() / AppDelegate / any startup service:
guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
else { return }   // skip startup network, background listeners, etc. under XCTest
```

Specific offenders seen in the wild:
- **Crash-reporting SDKs (Sentry, etc.):** `start()` installs signal + Mach
  exception handlers that fight XCTest's own crash handling and surface ordinary
  test execution as a spurious `Crash`. Guard `start()` on
  `XCTestConfigurationFilePath` — real app + UI-test runs stay instrumented.
- **Registration / auth gates:** a gate that parks the first authed call until a
  network round-trip resolves will hang every authed call the full timeout when
  the round-trip never happens under test. Open the gate under XCTest.
- **`Transaction.updates` / StoreKit / WCSession listeners:** infinite `for await`
  loops that keep the host alive. Skip them under XCTest.

---

## 8. The CI runner is not your laptop

### Serialize on constrained runners
Swift Testing's default parallelism + Task-group concurrency can saturate a
shared/low-core runner's thread pool, starving background Tasks and tripping the
iOS watchdog (which kills the host, losing dozens of tests to crash-restart).
`-parallel-testing-enabled NO` is slower but stable there. (Note this only
serializes XCTest — it does not tame a test's *own* internal Task-group
concurrency.)

### Retry flaky runner crashes; don't play whack-a-mole with skips
Some crashes are pure runner flakiness — OSLog + dyld + `nw_path_snapshot_path`
lock contention from a volume of network-mock tests, hitting the hang detector at
~10–23s. A **different test is the victim each run**, so skipping named suites
just moves the crash to the next one, and linking a new framework (more dyld/lock
pressure) tips more suites over. Prefer keeping coverage:

```bash
xcodebuild test … -parallel-testing-enabled NO -retry-tests-on-failure -test-iterations 3
```

A test that crash-restarts then passes is recorded as a flaky pass; passing tests
still run once. Root-cause candidates worth trying before accepting retries:
`OS_ACTIVITY_DT_MODE=NO` (kills the OSLog activity-tracing lock contention),
moving mock-network suites onto an SPM test target, or extending the runner hang
timeout.

### `build-for-testing` is a fast per-platform compile gate
`xcodebuild build-for-testing -destination 'generic/platform=…'` compiles the app
**and the test bundle** with no simulator boot. It catches test-target-only
breaks — e.g. an `invalid redeclaration` visible only on watchOS — that an
app-only `build` misses and that host `swift test` (which compiles out
`#if os(watchOS)`) never sees.

### Tier the gate
A gate that builds + runs the full suite on every platform serially is minutes of
PR latency. Split it: a fast PR gate (compile every platform via
`build-for-testing` + a fast host `swift test`) with the exhaustive on-simulator
runs moved to a nightly `schedule`. Keep the ruleset's required check name by
making it a fast aggregate that `needs:` the parallel fast jobs (`if: always()`
so an upstream failure surfaces as a failed — not skipped — required check).

### Swift Testing suite skipping is unreliable — gate at the source
`skippedTests` in an `.xctestplan` and `-skip-testing:` silently **no-op for
nested Swift Testing `@Suite`s** (top-level suites work; nested ones still run).
Don't trust them to quarantine a Swift Testing suite. For deterministic gating,
use a **source-level trait**:

```swift
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RUN_INTEGRATION"] != nil))
struct LiveServerTests { … }
```

---

## 9. Diagnosis discipline

1. **Read the real crash, don't guess.** The runner's `.xcresult` has the failure
   messages and the `.ips` DiagnosticReport has the backtrace:
   ```bash
   xcrun xcresulttool get test-results summary --path Foo.xcresult
   xcrun xcresulttool get test-results tests   --path Foo.xcresult   # per-test + failure msgs
   # ~/Library/Logs/DiagnosticReports/<App>-*.ips → parse JSON for exception + faulting thread
   ```
   `EXC_BREAKPOINT/SIGTRAP` in `swift_task_checkIsolated` → an actor-isolation
   violation (§5). `CONTINUATION MISUSE` → a leaked continuation (§6).
   `_os_unfair_lock_lock_slow` + `withLoadersReadLock` → runner lock contention (§8).
2. **The victim isn't the cause.** A crash "in" `WeatherServiceTests` that shows
   `host-level, no test running` at the restart is a background service dying
   between tests — the last-logged test is coincidental.
3. **Reproduce on the exact failing runtime, then verify locally BEFORE pushing.**
   The crash needed *both* the iOS 27 runtime *and* off-main scheduling; an older
   local sim won't show it. Iterate against the real sim locally instead of a
   push-and-watch-CI loop — each CI round-trip is minutes; a local run is seconds.
4. **A skip/retry that hides a signal must say so.** Silent quarantine reads as
   "covered" when it isn't — log what was skipped and why, with a ticket.
