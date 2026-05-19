import Foundation
import FBBridge

/// FB-framework backend: links the Meta-licensed Objective-C/Swift frameworks
/// directly via the FBBridge ObjC shim. Implements sim lifecycle, app
/// lifecycle, UI automation (tap/swipe), and XCTest listing + running with
/// per-case event streaming.
///
/// Selection: set `IOSTESTING_BACKEND=fb` to use this. Default is SimctlBackend.
/// HybridBackend wraps the two and falls through to simctl for any method
/// still tagged `.notYetImplemented` here.
///
/// To add a new FB-framework-backed method, see STATUS.md "How the bridge
/// pattern works": add ObjC `+` method to FBBridge.h/.m, call it from here,
/// remove the corresponding `.notYetImplemented` line.
struct FBBackend: Backend {
    static func linkedFrameworkSummary() -> String {
        "FBBridge wired via FBSimulatorControlFrameworkLoader.essentialFrameworks"
    }

    // MARK: - Simulators (live)

    func listSimulators() async throws -> [Simulator] {
        // Swift bridges `+(nullable NSArray *)...error:(NSError**)error` into
        // a throwing function returning [Type]. Wrap NSError throws into our
        // bridgeFailed case so HybridBackend doesn't fall through to simctl.
        do {
            let raw = try FBBridge.listSimulators()
            return raw.map { dict in
                Simulator(
                    udid: dict["udid"] ?? "",
                    name: dict["name"] ?? "",
                    runtime: dict["runtime"] ?? "",
                    deviceType: dict["deviceType"] ?? "",
                    state: dict["state"] ?? "Unknown"
                )
            }
        } catch {
            throw FBBackendError.bridgeFailed("listSimulators", error as NSError)
        }
    }

    func resolveSimulator(_ nameOrUDID: String) async throws -> Simulator {
        let sims = try await listSimulators()
        if let exact = sims.first(where: { $0.udid == nameOrUDID }) { return exact }
        let matches = sims.filter { $0.name == nameOrUDID }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            throw FBBackendError.bridgeFailed("multiple simulators named '\(nameOrUDID)'", nil)
        }
        throw FBBackendError.bridgeFailed("no simulator matches '\(nameOrUDID)'", nil)
    }

    func boot(udid: String) async throws {
        do { try FBBridge.bootSimulator(withUDID: udid) }
        catch { throw FBBackendError.bridgeFailed("boot", error as NSError) }
    }

    func shutdown(udid: String) async throws {
        do { try FBBridge.shutdownSimulator(withUDID: udid) }
        catch { throw FBBackendError.bridgeFailed("shutdown", error as NSError) }
    }

    func erase(udid: String) async throws {
        do { try FBBridge.eraseSimulator(withUDID: udid) }
        catch { throw FBBackendError.bridgeFailed("erase", error as NSError) }
    }

    // MARK: - App lifecycle (FB-backed)

    func install(udid: String, appPath: URL) async throws {
        do { _ = try FBBridge.installApp(atPath: appPath.path, onSimulator: udid) }
        catch { throw FBBackendError.bridgeFailed("install", error as NSError) }
    }

    func uninstall(udid: String, bundleId: String) async throws {
        do { try FBBridge.uninstallBundleID(bundleId, onSimulator: udid) }
        catch { throw FBBackendError.bridgeFailed("uninstall", error as NSError) }
    }

    func launch(udid: String, bundleId: String, env: [String: String], args: [String], waitForDebugger: Bool) async throws -> LaunchResult {
        do {
            let pidNum = try FBBridge.launchBundleID(
                bundleId,
                onSimulator: udid,
                arguments: args,
                environment: env,
                waitForDebugger: waitForDebugger
            )
            return LaunchResult(pid: pidNum.int32Value, bundleId: bundleId)
        } catch {
            throw FBBackendError.bridgeFailed("launch", error as NSError)
        }
    }

    func terminate(udid: String, bundleIdOrPID: String) async throws {
        // FB framework variant: by bundle id. PID-based termination falls
        // through to SimctlBackend until we add a kill(2)-style helper.
        if let _ = Int32(bundleIdOrPID) {
            throw FBBackendError.notYetImplemented("terminate-by-pid")
        }
        do { try FBBridge.killBundleID(bundleIdOrPID, onSimulator: udid) }
        catch { throw FBBackendError.bridgeFailed("terminate", error as NSError) }
    }

    // Backend protocol conformance — placeholders for the few methods still
    // queued for follow-up releases (device log streaming, richer UI verbs, etc).
    // Per-method implementations are intentionally scoped out of this session
    // because each one requires constructing the framework's loader chain,
    // bridging FBFuture<T> to Swift Concurrency, and discovering the right
    // entry-point class (FBSimulatorSet via FBSimulatorControl.setWithConfiguration,
    // etc.). The dispatching wrapper in BackendSelector falls back to
    // SimctlBackend for any method that throws .notYetImplemented.

    func createSimulator(name: String, deviceType: String, runtime: String) async throws -> String { throw FBBackendError.notYetImplemented("createSimulator") }
    func screenshot(udid: String, output: URL) async throws { throw FBBackendError.notYetImplemented("screenshot") }
    func streamLogs(udid: String, bundleId: String?, predicate: String?, onEvent: @Sendable @escaping (LogEvent) -> Void) async throws { throw FBBackendError.notYetImplemented("streamLogs") }
    /// If the test bundle is at `.../Foo.app/PlugIns/FooTests.xctest`, returns
    /// the `Foo.app` path. App-hosted XCTest bundles need this for `@rpath/Foo.dylib`
    /// references to resolve.
    private func inferHostAppPath(from bundlePath: URL) -> URL? {
        let components = bundlePath.deletingLastPathComponent().pathComponents
        // .../Something.app/PlugIns
        guard components.count >= 2,
              components.last == "PlugIns",
              components[components.count - 2].hasSuffix(".app") else { return nil }
        return bundlePath.deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Resolves a booted simulator (configured > first booted).
    private func resolveBootedSim() async throws -> Simulator {
        let effective = try ConfigStore.loadEffective().config
        if let saved = effective.sim { return try await resolveSimulator(saved) }
        let sims = try await listSimulators()
        guard let booted = sims.first(where: { $0.isBooted }) else {
            throw FBBackendError.bridgeFailed("requires a booted simulator (saved IOSTESTING_SIM or `iostesting sim boot`)", nil)
        }
        return booted
    }

    func listTests(bundlePath: URL) async throws -> [TestCase] {
        do {
            let resolved = try await resolveBootedSim()
            let hostApp = inferHostAppPath(from: bundlePath)
            let raw = try FBBridge.listTestsInBundle(
                atPath: bundlePath.path,
                hostAppPath: hostApp?.path,
                onSimulator: resolved.udid,
                timeout: 60.0
            )
            let bundleName = bundlePath.deletingPathExtension().lastPathComponent
            return raw.map { name -> TestCase in
                let parts = name.split(separator: "/", maxSplits: 1)
                if parts.count == 2 {
                    return TestCase(target: bundleName, suite: String(parts[0]), name: String(parts[1]))
                }
                return TestCase(target: bundleName, suite: "Unknown", name: name)
            }
        } catch let e as FBBackendError { throw e }
        catch { throw FBBackendError.bridgeFailed("listTests", error as NSError) }
    }

    func runTests(
        udid: String,
        bundlePath: URL,
        hostApp: URL?,
        filters: [String],
        onEvent: @Sendable @escaping (TestEvent) -> Void
    ) async throws {
        let resolved = try await resolveSimulator(udid)
        let effectiveHost = hostApp ?? inferHostAppPath(from: bundlePath)
        // UI test detection: bundles inside `*UITests-Runner.app/PlugIns` are
        // XCUITest. Their host app is the runner; the target app is sibling
        // (e.g. SpinCall.app next to SpinCallUITests-Runner.app).
        let (uiTesting, targetApp) = detectUITestingContext(bundlePath: bundlePath, hostApp: effectiveHost)
        let runState = RunState(onEvent: onEvent)
        do {
            try FBBridge.runTestsInBundle(
                atPath: bundlePath.path,
                hostAppPath: effectiveHost?.path,
                targetAppPath: targetApp?.path,
                uiTesting: uiTesting,
                testsToRun: Set(filters),
                onSimulator: resolved.udid,
                timeout: 120.0,
                onEvent: { dict in
                    runState.handle(rawEvent: dict)
                }
            )
        } catch {
            throw FBBackendError.bridgeFailed("runTests", error as NSError)
        }
    }

    /// If the test bundle lives inside `*UITests-Runner.app/PlugIns`, infer
    /// that this is XCUITest and locate the target app (sibling `.app` next
    /// to the runner). Returns (isUITesting, targetApp).
    private func detectUITestingContext(bundlePath: URL, hostApp: URL?) -> (Bool, URL?) {
        guard let host = hostApp else { return (false, nil) }
        let runnerName = host.lastPathComponent
        guard runnerName.hasSuffix("UITests-Runner.app") else { return (false, nil) }
        // SpinCallUITests-Runner.app → SpinCall.app sibling
        let suffix = "UITests-Runner.app"
        let appName = String(runnerName.dropLast(suffix.count)) + ".app"
        let targetCandidate = host.deletingLastPathComponent().appendingPathComponent(appName)
        if FileManager.default.fileExists(atPath: targetCandidate.path) {
            return (true, targetCandidate)
        }
        return (true, nil)
    }
    func pruneUnavailableSimulators() async throws -> Int { throw FBBackendError.notYetImplemented("pruneUnavailableSimulators") }
    func addMedia(udid: String, files: [URL]) async throws { throw FBBackendError.notYetImplemented("addMedia") }
    func setLocation(udid: String, latitude: Double, longitude: Double) async throws { throw FBBackendError.notYetImplemented("setLocation") }
    func clearLocation(udid: String) async throws { throw FBBackendError.notYetImplemented("clearLocation") }
    func pressButton(udid: String, button: String) async throws { throw FBBackendError.notYetImplemented("pressButton") }
    func setAppearance(udid: String, appearance: String) async throws { throw FBBackendError.notYetImplemented("setAppearance") }
    func openURL(udid: String, url: String) async throws { throw FBBackendError.notYetImplemented("openURL") }
}

/// Bridges the dict events FBBridge pushes into our typed TestEvent enum,
/// guarding the user's @Sendable callback with an NSLock so the framework's
/// reporter (which may call from any queue) can't race the callback.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let onEvent: @Sendable (TestEvent) -> Void

    init(onEvent: @Sendable @escaping (TestEvent) -> Void) {
        self.onEvent = onEvent
    }

    func handle(rawEvent dict: [String: Any]) {
        guard let kind = dict["kind"] as? String else { return }
        let name = (dict["name"] as? String) ?? ""
        let duration = (dict["duration"] as? Double) ?? 0
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case "suiteStarted":
            onEvent(.suiteStarted(name: name))
        case "caseStarted":
            onEvent(.caseStarted(name: name))
        case "casePassed":
            onEvent(.casePassed(name: name, durationSeconds: duration))
        case "caseFailed":
            onEvent(.caseFailed(name: name, durationSeconds: duration, message: "see caseFailureDetails"))
        case "caseSkipped":
            onEvent(.caseSkipped(name: name))
        case "caseFailureDetails":
            // No matching TestEvent today; surface as a failed case with message.
            let msg = (dict["message"] as? String) ?? ""
            onEvent(.caseFailed(name: name, durationSeconds: 0, message: msg))
        case "suiteFinished":
            onEvent(.suiteFinished(name: name, passed: 0, failed: 0, skipped: 0, durationSeconds: duration))
        case "runFinished":
            let passed = (dict["passed"] as? Int) ?? 0
            let failed = (dict["failed"] as? Int) ?? 0
            onEvent(.runFinished(passed: passed, failed: failed, skipped: 0, durationSeconds: duration))
        case "runCrashed":
            let msg = (dict["message"] as? String) ?? "crashed"
            onEvent(.caseFailed(name: "<crashed>", durationSeconds: 0, message: msg))
        case "activityStarted", "activityFinished", "videoRecorded", "osLogSaved",
             "artifactSaved", "testPlanFailed", "output":
            // Side-channel events the typed TestEvent enum doesn't represent.
            // The bridge already JSON-emits them; for human output we skip.
            // (Could be wired through a separate diagnostic callback later.)
            break
        default:
            break
        }
    }
}

enum FBBackendError: Error, CustomStringConvertible {
    case notYetImplemented(String)
    case bridgeFailed(String, NSError?)
    var description: String {
        switch self {
        case .notYetImplemented(let name):
            return "FBBackend.\(name) not yet implemented in this build; falling back to simctl."
        case .bridgeFailed(let op, let err):
            return "FBBackend.\(op) bridge call failed: \(err?.localizedDescription ?? "unknown")"
        }
    }
}

/// Falls through to SimctlBackend for any method the FBBackend hasn't
/// implemented yet. Lets us flip `IOSTESTING_BACKEND=fb` and incrementally
/// take ownership of methods without a big-bang cutover.
struct HybridBackend: Backend {
    let primary: any Backend
    let fallback: any Backend

    private func attempt<T>(_ block: () async throws -> T, fallback fb: () async throws -> T) async throws -> T {
        do { return try await block() }
        catch let e as FBBackendError {
            // Only fall through when the FB path is unwired. Real bridge
            // failures surface to the caller — they mean the frameworks tried
            // but failed, which is genuine information.
            if case .notYetImplemented = e { return try await fb() }
            throw e
        }
    }

    func listSimulators() async throws -> [Simulator] { try await attempt({ try await primary.listSimulators() }, fallback: { try await fallback.listSimulators() }) }
    func resolveSimulator(_ s: String) async throws -> Simulator { try await attempt({ try await primary.resolveSimulator(s) }, fallback: { try await fallback.resolveSimulator(s) }) }
    func boot(udid: String) async throws { try await attempt({ try await primary.boot(udid: udid) }, fallback: { try await fallback.boot(udid: udid) }) }
    func shutdown(udid: String) async throws { try await attempt({ try await primary.shutdown(udid: udid) }, fallback: { try await fallback.shutdown(udid: udid) }) }
    func erase(udid: String) async throws { try await attempt({ try await primary.erase(udid: udid) }, fallback: { try await fallback.erase(udid: udid) }) }
    func createSimulator(name: String, deviceType: String, runtime: String) async throws -> String { try await attempt({ try await primary.createSimulator(name: name, deviceType: deviceType, runtime: runtime) }, fallback: { try await fallback.createSimulator(name: name, deviceType: deviceType, runtime: runtime) }) }
    func install(udid: String, appPath: URL) async throws { try await attempt({ try await primary.install(udid: udid, appPath: appPath) }, fallback: { try await fallback.install(udid: udid, appPath: appPath) }) }
    func uninstall(udid: String, bundleId: String) async throws { try await attempt({ try await primary.uninstall(udid: udid, bundleId: bundleId) }, fallback: { try await fallback.uninstall(udid: udid, bundleId: bundleId) }) }
    func launch(udid: String, bundleId: String, env: [String: String], args: [String], waitForDebugger: Bool) async throws -> LaunchResult { try await attempt({ try await primary.launch(udid: udid, bundleId: bundleId, env: env, args: args, waitForDebugger: waitForDebugger) }, fallback: { try await fallback.launch(udid: udid, bundleId: bundleId, env: env, args: args, waitForDebugger: waitForDebugger) }) }
    func terminate(udid: String, bundleIdOrPID: String) async throws { try await attempt({ try await primary.terminate(udid: udid, bundleIdOrPID: bundleIdOrPID) }, fallback: { try await fallback.terminate(udid: udid, bundleIdOrPID: bundleIdOrPID) }) }
    func screenshot(udid: String, output: URL) async throws { try await attempt({ try await primary.screenshot(udid: udid, output: output) }, fallback: { try await fallback.screenshot(udid: udid, output: output) }) }
    func streamLogs(udid: String, bundleId: String?, predicate: String?, onEvent: @Sendable @escaping (LogEvent) -> Void) async throws { try await attempt({ try await primary.streamLogs(udid: udid, bundleId: bundleId, predicate: predicate, onEvent: onEvent) }, fallback: { try await fallback.streamLogs(udid: udid, bundleId: bundleId, predicate: predicate, onEvent: onEvent) }) }
    func listTests(bundlePath: URL) async throws -> [TestCase] { try await attempt({ try await primary.listTests(bundlePath: bundlePath) }, fallback: { try await fallback.listTests(bundlePath: bundlePath) }) }
    func runTests(udid: String, bundlePath: URL, hostApp: URL?, filters: [String], onEvent: @Sendable @escaping (TestEvent) -> Void) async throws { try await attempt({ try await primary.runTests(udid: udid, bundlePath: bundlePath, hostApp: hostApp, filters: filters, onEvent: onEvent) }, fallback: { try await fallback.runTests(udid: udid, bundlePath: bundlePath, hostApp: hostApp, filters: filters, onEvent: onEvent) }) }
    func pruneUnavailableSimulators() async throws -> Int { try await attempt({ try await primary.pruneUnavailableSimulators() }, fallback: { try await fallback.pruneUnavailableSimulators() }) }
    func addMedia(udid: String, files: [URL]) async throws { try await attempt({ try await primary.addMedia(udid: udid, files: files) }, fallback: { try await fallback.addMedia(udid: udid, files: files) }) }
    func setLocation(udid: String, latitude: Double, longitude: Double) async throws { try await attempt({ try await primary.setLocation(udid: udid, latitude: latitude, longitude: longitude) }, fallback: { try await fallback.setLocation(udid: udid, latitude: latitude, longitude: longitude) }) }
    func clearLocation(udid: String) async throws { try await attempt({ try await primary.clearLocation(udid: udid) }, fallback: { try await fallback.clearLocation(udid: udid) }) }
    func pressButton(udid: String, button: String) async throws { try await attempt({ try await primary.pressButton(udid: udid, button: button) }, fallback: { try await fallback.pressButton(udid: udid, button: button) }) }
    func setAppearance(udid: String, appearance: String) async throws { try await attempt({ try await primary.setAppearance(udid: udid, appearance: appearance) }, fallback: { try await fallback.setAppearance(udid: udid, appearance: appearance) }) }
    func openURL(udid: String, url: String) async throws { try await attempt({ try await primary.openURL(udid: udid, url: url) }, fallback: { try await fallback.openURL(udid: udid, url: url) }) }
}
