import Foundation

struct BackendError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct SimctlBackend: Backend {
    private let xcrun = "/usr/bin/xcrun"

    // MARK: - Simulators

    func listSimulators() async throws -> [Simulator] {
        let json = try await Shell.runChecked(xcrun, ["simctl", "list", "devices", "available", "--json"])
        guard let data = json.data(using: .utf8) else {
            throw BackendError(message: "simctl list returned non-utf8 output")
        }
        let listing = try JSONDecoder().decode(SimctlListing.self, from: data)
        var sims: [Simulator] = []
        for (runtimeKey, devices) in listing.devices {
            let shortRuntimeName = shortRuntime(runtimeKey)
            for device in devices {
                sims.append(Simulator(
                    udid: device.udid,
                    name: device.name,
                    runtime: shortRuntimeName,
                    deviceType: shortDeviceType(device.deviceTypeIdentifier ?? ""),
                    state: device.state
                ))
            }
        }
        sims.sort { lhs, rhs in
            lhs.runtime == rhs.runtime ? lhs.name < rhs.name : lhs.runtime < rhs.runtime
        }
        return sims
    }

    func resolveSimulator(_ nameOrUDID: String) async throws -> Simulator {
        let sims = try await listSimulators()
        if let exactUDID = sims.first(where: { $0.udid == nameOrUDID }) {
            return exactUDID
        }
        let matches = sims.filter { $0.name == nameOrUDID }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 {
            let runtimes = matches.map(\.runtime).joined(separator: ", ")
            throw BackendError(message: "Multiple simulators named '\(nameOrUDID)' (runtimes: \(runtimes)). Pass a UDID to disambiguate.")
        }
        throw BackendError(message: "No simulator matches '\(nameOrUDID)'. Try `iostesting sim list`.")
    }

    func boot(udid: String) async throws {
        _ = try await runSimctlExpectingIdempotent(["boot", udid], allowingMessage: "Unable to boot device in current state: Booted")
    }

    func shutdown(udid: String) async throws {
        _ = try await runSimctlExpectingIdempotent(["shutdown", udid], allowingMessage: "Unable to shutdown device in current state: Shutdown")
    }

    func erase(udid: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "erase", udid])
    }

    func createSimulator(name: String, deviceType: String, runtime: String) async throws -> String {
        let out = try await Shell.runChecked(xcrun, ["simctl", "create", name, deviceType, runtime])
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Apps

    func install(udid: String, appPath: URL) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "install", udid, appPath.path])
    }

    func uninstall(udid: String, bundleId: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "uninstall", udid, bundleId])
    }

    func launch(udid: String, bundleId: String, env: [String: String], args: [String], waitForDebugger: Bool) async throws -> LaunchResult {
        var argv: [String] = ["simctl", "launch"]
        if waitForDebugger { argv.append("--wait-for-debugger") }
        argv.append("--terminate-running-process")
        argv.append(udid)
        argv.append(bundleId)
        argv.append(contentsOf: args)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrun)
        process.arguments = argv
        var environ = ProcessInfo.processInfo.environment
        for (k, v) in env {
            environ["SIMCTL_CHILD_\(k)"] = v
        }
        process.environment = environ

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: outData, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let stderr = String(data: errData, encoding: .utf8) ?? ""
            throw BackendError(message: "launch failed: \(stderr.isEmpty ? stdout : stderr)")
        }
        // simctl launch prints "<bundle-id>: <pid>"
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        let pid = Int32(parts.last ?? "0") ?? 0
        return LaunchResult(pid: pid, bundleId: bundleId)
    }

    func terminate(udid: String, bundleIdOrPID: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "terminate", udid, bundleIdOrPID])
    }

    // MARK: - Screenshot

    func screenshot(udid: String, output: URL) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "io", udid, "screenshot", output.path])
    }

    // MARK: - Logs

    func streamLogs(
        udid: String,
        bundleId: String?,
        predicate: String?,
        onEvent: @Sendable @escaping (LogEvent) -> Void
    ) async throws {
        var args = ["simctl", "spawn", udid, "log", "stream", "--style", "ndjson", "--level", "default"]
        if let p = predicate {
            args.append(contentsOf: ["--predicate", p])
        } else if let b = bundleId {
            args.append(contentsOf: ["--predicate", "subsystem CONTAINS \"\(b)\" OR processImagePath CONTAINS \"\(b)\""])
        }
        _ = try await Shell.stream(xcrun, args) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
            if let entry = try? JSONDecoder().decode(OSLogNDJSON.self, from: data) {
                let event = LogEvent(
                    timestamp: entry.timestamp ?? "",
                    bundleId: entry.subsystem,
                    level: entry.messageType,
                    message: entry.eventMessage ?? ""
                )
                onEvent(event)
            }
        }
    }

    // MARK: - Tests

    func listTests(bundlePath: URL) async throws -> [TestCase] {
        let target = bundlePath.deletingPathExtension().lastPathComponent
        let nm = try await Shell.runChecked("/usr/bin/nm", ["-gU", bundlePath.appendingPathComponent(target).path])
        var cases: [TestCase] = []
        for raw in nm.split(separator: "\n") {
            guard let openBracket = raw.firstIndex(of: "[") else { continue }
            guard let closeBracket = raw.firstIndex(of: "]") else { continue }
            let inside = raw[raw.index(after: openBracket)..<closeBracket]
            let parts = inside.split(separator: " ")
            guard parts.count == 2 else { continue }
            let suite = String(parts[0])
            let name = String(parts[1])
            guard name.hasPrefix("test") else { continue }
            cases.append(TestCase(target: target, suite: suite, name: name))
        }
        return cases.sorted { $0.triple < $1.triple }
    }

    func runTests(
        udid: String,
        bundlePath: URL,
        hostApp: URL?,
        filters: [String],
        terminationTimeoutSeconds: Double,
        onEvent: @Sendable @escaping (TestEvent) -> Void
    ) async throws {
        if hostApp != nil {
            throw BackendError(message: "Host-app tests via the simctl backend are logic-only. Set IOSTESTING_BACKEND=fb to run app-hosted tests via XCTestBootstrap.")
        }
        // simctl logic-only runs don't expose a separate post-test termination
        // wait — that knob is FB-backend specific. Accepted for API symmetry.
        _ = terminationTimeoutSeconds
        var args = ["simctl", "spawn", udid, "xctest"]
        for f in filters {
            args.append(contentsOf: ["-XCTest", f])
        }
        args.append(bundlePath.path)

        let state = TestRunState(onEvent: onEvent)
        _ = try await Shell.stream(xcrun, args) { line in
            state.consume(line)
        }
        let summary = state.finish()
        if summary.failed > 0 {
            throw BackendError(message: "\(summary.failed) test\(summary.failed == 1 ? "" : "s") failed")
        }
    }

    // MARK: - Sim extras

    func pruneUnavailableSimulators() async throws -> Int {
        // Get current count, run delete, return delta. simctl doesn't tell us how many it removed.
        let before = try await listSimulators().count
        _ = try await Shell.run(xcrun, ["simctl", "delete", "unavailable"])
        let after = try await listSimulators().count
        return max(0, before - after)
    }

    func addMedia(udid: String, files: [URL]) async throws {
        var args = ["simctl", "addmedia", udid]
        args.append(contentsOf: files.map(\.path))
        _ = try await Shell.runChecked(xcrun, args)
    }

    func setLocation(udid: String, latitude: Double, longitude: Double) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "location", udid, "set", "\(latitude),\(longitude)"])
    }

    func clearLocation(udid: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "location", udid, "clear"])
    }

    func startLocationTrack(udid: String, waypoints: [(latitude: Double, longitude: Double)], intervalSeconds: Double) async throws {
        guard !waypoints.isEmpty else {
            throw BackendError(message: "startLocationTrack requires at least one waypoint")
        }
        // simctl's `start` requires >=2 waypoints. With exactly one waypoint we
        // can't interpolate — fall through to `set` for a one-shot override.
        if waypoints.count == 1 {
            try await setLocation(udid: udid, latitude: waypoints[0].latitude, longitude: waypoints[0].longitude)
            return
        }
        // `simctl location <udid> start [--interval=N] <lat,lon> <lat,lon>...`
        var args = ["simctl", "location", udid, "start"]
        // Note: simctl wants the value glued via `=` (e.g. `--interval=1.0`).
        args.append("--interval=\(intervalSeconds)")
        for pt in waypoints {
            args.append("\(pt.latitude),\(pt.longitude)")
        }
        _ = try await Shell.runChecked(xcrun, args)
    }

    func pressButton(udid: String, button: String) async throws {
        // Map friendly names to simctl io button names.
        let mapped: String
        switch button.lowercased() {
        case "home": mapped = "home"
        case "lock", "power", "sleep": mapped = "lock"
        case "siri": mapped = "siri"
        case "side", "side-button": mapped = "side"
        case "apple-pay", "applepay": mapped = "apple-pay"
        default: mapped = button
        }
        _ = try await Shell.runChecked(xcrun, ["simctl", "io", udid, "button", mapped])
    }

    func setAppearance(udid: String, appearance: String) async throws {
        let v = appearance.lowercased()
        guard v == "light" || v == "dark" else {
            throw BackendError(message: "appearance must be 'light' or 'dark', got '\(appearance)'")
        }
        _ = try await Shell.runChecked(xcrun, ["simctl", "ui", udid, "appearance", v])
    }

    func openURL(udid: String, url: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "openurl", udid, url])
    }

    func setSimEnv(udid: String, key: String, value: String) async throws {
        // `simctl spawn <udid> launchctl setenv KEY VALUE` bridges KEY=VALUE into
        // the sim's launchd environment so newly-spawned processes inherit it.
        // Existing processes are unaffected.
        _ = try await Shell.runChecked(xcrun, ["simctl", "spawn", udid, "launchctl", "setenv", key, value])
    }

    func unsetSimEnv(udid: String, key: String) async throws {
        _ = try await Shell.runChecked(xcrun, ["simctl", "spawn", udid, "launchctl", "unsetenv", key])
    }

    // MARK: - Helpers

    private struct SimctlListing: Decodable {
        let devices: [String: [Device]]
        struct Device: Decodable {
            let udid: String
            let name: String
            let state: String
            let deviceTypeIdentifier: String?
        }
    }

    private struct OSLogNDJSON: Decodable {
        let timestamp: String?
        let eventMessage: String?
        let subsystem: String?
        let messageType: String?
    }

    private func runSimctlExpectingIdempotent(_ args: [String], allowingMessage: String) async throws -> String {
        let result = try await Shell.run(xcrun, ["simctl"] + args)
        if result.isSuccess { return result.stdout }
        if result.stderr.contains(allowingMessage) { return "" }
        throw ShellError.nonZeroExit(
            command: "xcrun simctl " + args.joined(separator: " "),
            exitCode: result.exitCode,
            stderr: result.stderr
        )
    }

    private func shortRuntime(_ key: String) -> String {
        // "com.apple.CoreSimulator.SimRuntime.iOS-26-4" -> "iOS 26.4"
        guard let last = key.split(separator: ".").last else { return key }
        let parts = last.split(separator: "-")
        guard let platform = parts.first else { return String(last) }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? String(platform) : "\(platform) \(version)"
    }

    private func shortDeviceType(_ key: String) -> String {
        guard let last = key.split(separator: ".").last else { return key }
        return String(last).replacingOccurrences(of: "-", with: " ")
    }
}

// MARK: - Test run state (Sendable via internal lock)

private final class TestRunState: @unchecked Sendable {
    struct Summary {
        let passed: Int
        let failed: Int
        let skipped: Int
        let durationSeconds: Double
    }

    private let lock = NSLock()
    private let onEvent: @Sendable (TestEvent) -> Void
    private let runStart = Date()
    private var passed = 0
    private var failed = 0
    private var skipped = 0
    private var currentCaseStart = Date()
    private var suiteStartByName: [String: Date] = [:]
    private var suiteCountsByName: [String: (passed: Int, failed: Int, skipped: Int)] = [:]

    init(onEvent: @Sendable @escaping (TestEvent) -> Void) {
        self.onEvent = onEvent
    }

    func consume(_ line: String) {
        if line.hasPrefix("Test Suite '") {
            guard let suiteName = Self.extractQuoted(line) else { return }
            if line.contains("' started at") {
                lock.lock()
                suiteStartByName[suiteName] = Date()
                suiteCountsByName[suiteName] = (0, 0, 0)
                lock.unlock()
                onEvent(.suiteStarted(name: suiteName))
            } else if line.contains("' passed at") || line.contains("' failed at") {
                lock.lock()
                let counts = suiteCountsByName[suiteName] ?? (0, 0, 0)
                let start = suiteStartByName[suiteName] ?? Date()
                lock.unlock()
                let elapsed = Date().timeIntervalSince(start)
                onEvent(.suiteFinished(
                    name: suiteName,
                    passed: counts.passed,
                    failed: counts.failed,
                    skipped: counts.skipped,
                    durationSeconds: elapsed
                ))
            }
            return
        }
        if line.hasPrefix("Test Case '") {
            guard let name = Self.extractTestCaseName(line) else { return }
            if line.contains("' started.") {
                lock.lock()
                currentCaseStart = Date()
                lock.unlock()
                onEvent(.caseStarted(name: name))
            } else if line.contains("' passed (") {
                lock.lock()
                let elapsed = Date().timeIntervalSince(currentCaseStart)
                passed += 1
                if let suite = Self.suiteFromCase(name) {
                    var counts = suiteCountsByName[suite] ?? (0, 0, 0)
                    counts.passed += 1
                    suiteCountsByName[suite] = counts
                }
                lock.unlock()
                onEvent(.casePassed(name: name, durationSeconds: elapsed))
            } else if line.contains("' failed (") {
                lock.lock()
                let elapsed = Date().timeIntervalSince(currentCaseStart)
                failed += 1
                if let suite = Self.suiteFromCase(name) {
                    var counts = suiteCountsByName[suite] ?? (0, 0, 0)
                    counts.failed += 1
                    suiteCountsByName[suite] = counts
                }
                lock.unlock()
                onEvent(.caseFailed(name: name, durationSeconds: elapsed, message: "see stderr"))
            }
            return
        }
    }

    func finish() -> Summary {
        lock.lock()
        let p = passed, f = failed, s = skipped
        lock.unlock()
        let elapsed = Date().timeIntervalSince(runStart)
        onEvent(.runFinished(passed: p, failed: f, skipped: s, durationSeconds: elapsed))
        return Summary(passed: p, failed: f, skipped: s, durationSeconds: elapsed)
    }

    private static func extractQuoted(_ line: String) -> String? {
        guard let first = line.firstIndex(of: "'") else { return nil }
        let afterFirst = line.index(after: first)
        guard let second = line[afterFirst...].firstIndex(of: "'") else { return nil }
        return String(line[afterFirst..<second])
    }

    private static func extractTestCaseName(_ line: String) -> String? {
        guard let openBracket = line.firstIndex(of: "[") else { return nil }
        guard let closeBracket = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: openBracket)..<closeBracket]
        return String(inside)
    }

    private static func suiteFromCase(_ name: String) -> String? {
        let parts = name.split(separator: " ")
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }
}
