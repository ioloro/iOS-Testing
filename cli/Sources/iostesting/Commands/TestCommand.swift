import ArgumentParser
import Foundation

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Inspect and run XCTest bundles. Build the bundle with your build tool of choice; iostesting drives the execution.",
        subcommands: [List.self, Run.self]
    )
}

extension Test {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List test cases discovered inside an .xctest bundle.")
        @Argument(help: "Path to .xctest bundle.") var bundlePath: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.testList); return }
            if bundlePath.isEmpty { IOSTesting.fail("Pass a .xctest bundle path.") }
            let url = URL(fileURLWithPath: bundlePath)
            let cases = try await backend.listTests(bundlePath: url)
            if json {
                try JSONOutput.emit(cases)
                return
            }
            for c in cases {
                print(c.triple)
            }
            print("(\(cases.count) tests)")
        }
    }

    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run an .xctest bundle on a simulator. Default backend (simctl) runs logic tests via `simctl spawn xctest`. Set IOSTESTING_BACKEND=fb for app-hosted XCTest + Swift Testing via XCTestBootstrap."
        )
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Path to .xctest bundle.") var bundlePath: String = ""
        @Option(name: .long, parsing: .upToNextOption, help: "Test filter (e.g. \"MySuite/testThing\"). Repeatable.") var filter: [String] = []
        @Option(name: .long, help: "Host .app bundle for app-hosted XCTest. Only supported via IOSTESTING_BACKEND=fb (simctl backend is logic-only).") var hostApp: String?
        @Option(name: .long, help: "Seconds to wait for the host app to terminate after the test method exits (FB backend only). Default 120. Bump when the app holds background subscriptions or in-flight requests.") var terminationTimeout: Double = 120.0
        @Option(name: .long, parsing: .upToNextOption, help: "Set a launchd env var on the sim before running (KEY=VALUE). Equivalent to `iostesting sim env --set`. Repeatable.") var simEnv: [String] = []
        @Option(name: .long, parsing: .upToNextOption, help: "Pre-grant a simctl privacy service for the target app BEFORE the runner launches (e.g. `location-always`, `notifications`). Use `all-location` shorthand to grant both `location` and `location-always` (preempts iOS 26's 'also use location' upgrade prompt). Requires --auto-dismiss-bundle-id or `iostesting config` to know which app. Repeatable.") var privacyGrant: [String] = []
        @Option(name: .long, help: "Bundle id of the target app for --privacy-grant / --auto-dismiss. Falls back to `iostesting config bundleId` or env IOSTESTING_BUNDLE_ID. Inferred from the runner app for UI tests (drops the `UITests-Runner` suffix).") var autoDismissBundleId: String?
        @Flag(name: .long, help: "Spawn a background watcher that screenshots the sim every 2s, OCRs for known system-alert button labels (e.g. 'Keep Only While Using', 'Allow While Using App'), and taps them via HID. Catches SpringBoard-owned modals that XCUITest's addUIInterruptionMonitor cannot reach (iOS 26 'also use location' upgrade prompt, etc.). Requires the FB backend.") var autoDismissAlerts: Bool = false
        @Option(name: .long, parsing: .upToNextOption, help: "Custom button label(s) for --auto-dismiss-alerts to look for. Repeatable. If omitted, uses a curated default list.") var autoDismissLabel: [String] = []
        @Flag(name: .long, help: "Emit NDJSON test events on stdout.") var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.testRun); return }
            if bundlePath.isEmpty { IOSTesting.fail("Pass a .xctest bundle path.") }
            if terminationTimeout <= 0 || terminationTimeout > 600 {
                IOSTesting.fail("--termination-timeout must be > 0 and <= 600 (got \(terminationTimeout)).")
            }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))

            // Stage 0: pre-flight env injection. Setting launchd vars before
            // the runner launches means the host app inherits them on first
            // boot — matches `xcrun simctl spawn ... launchctl setenv ...`.
            for entry in simEnv {
                guard let eq = entry.firstIndex(of: "=") else {
                    IOSTesting.fail("--sim-env entries must be KEY=VALUE; got '\(entry)'")
                }
                let key = String(entry[..<eq])
                let value = String(entry[entry.index(after: eq)...])
                if key.isEmpty { IOSTesting.fail("--sim-env entry '\(entry)' has empty KEY.") }
                try await backend.setSimEnv(udid: resolved.udid, key: key, value: value)
            }

            let bundle = URL(fileURLWithPath: bundlePath)
            let host = hostApp.map { URL(fileURLWithPath: $0) }
            let useJSON = json
            let terminationTimeoutValue = terminationTimeout

            // Stage 0.5: pre-grant privacy services BEFORE the runner launches.
            // Order matters: we resolve the target bundle id (drop the
            // UITests-Runner suffix for XCUITest bundles), then write
            // locationd/TCC state via simctl. On iOS 26 this is the only
            // reliable way to suppress the "also use location" upgrade
            // prompt — XCUITest's interruption monitor cannot reach
            // SpringBoard-owned modals.
            let targetBid = resolveTargetBundleId(
                explicit: autoDismissBundleId,
                hostApp: host
            )
            for service in privacyGrant {
                guard let bid = targetBid else {
                    IOSTesting.fail("--privacy-grant needs a target bundle id. Pass --auto-dismiss-bundle-id, set IOSTESTING_BUNDLE_ID, or run `iostesting config set --bundle-id ...`.")
                }
                try await applyPrivacyGrant(service: service, udid: resolved.udid, bundleId: bid)
            }

            // Stage 0.75: spawn the alert-watcher subprocess (if requested).
            // Runs alongside the test for its duration; killed on completion.
            // We use a child `iostesting alerts watch` invocation so the
            // watcher inherits the same FB backend bootstrap path as this
            // process (single binary, no library duplication).
            let watcherProcess: Process? = autoDismissAlerts
                ? spawnAlertWatcher(
                    udid: resolved.udid,
                    durationSeconds: terminationTimeoutValue + 60,
                    labels: autoDismissLabel,
                    json: useJSON
                )
                : nil
            defer {
                if let p = watcherProcess, p.isRunning {
                    p.terminate()
                }
            }

            try await backend.runTests(
                udid: resolved.udid,
                bundlePath: bundle,
                hostApp: host,
                filters: filter,
                terminationTimeoutSeconds: terminationTimeoutValue
            ) { event in
                if useJSON {
                    try? JSONOutput.emitLine(event)
                } else {
                    renderHuman(event)
                }
            }
        }

        // Apply a single privacy grant. Accepts `all-location` as shorthand
        // for granting both `location` AND `location-always`.
        private func applyPrivacyGrant(service: String, udid: String, bundleId: String) async throws {
            if service == "all-location" {
                _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", udid, "grant", "location", bundleId])
                _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", udid, "grant", "location-always", bundleId])
                FileHandle.standardError.write(Data("test run: pre-granted location + location-always to \(bundleId)\n".utf8))
                return
            }
            _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", udid, "grant", service, bundleId])
            FileHandle.standardError.write(Data("test run: pre-granted \(service) to \(bundleId)\n".utf8))
        }

        /// Resolves the target app bundle id for privacy grants and the alert
        /// watcher. Strategy:
        ///   1. Explicit --auto-dismiss-bundle-id wins.
        ///   2. IOSTESTING_BUNDLE_ID env var.
        ///   3. ./iostesting config bundleId.
        ///   4. Derive from the host runner: `FooUITests-Runner.app` → `Foo`,
        ///      then guess the bundle id via the sibling Foo.app's Info.plist
        ///      CFBundleIdentifier. Best-effort — falls through to nil if any
        ///      step fails.
        private func resolveTargetBundleId(explicit: String?, hostApp: URL?) -> String? {
            if let b = explicit, !b.isEmpty { return b }
            if let b = ProcessInfo.processInfo.environment["IOSTESTING_BUNDLE_ID"], !b.isEmpty { return b }
            if let cfg = (try? ConfigStore.loadEffective().config.bundleId), !cfg.isEmpty { return cfg }
            // Last-ditch: parse Info.plist from the sibling target app of a
            // UITests-Runner host.
            guard let host = hostApp else { return nil }
            let runnerName = host.lastPathComponent
            guard runnerName.hasSuffix("UITests-Runner.app") else { return nil }
            let suffix = "UITests-Runner.app"
            let appName = String(runnerName.dropLast(suffix.count)) + ".app"
            let targetApp = host.deletingLastPathComponent().appendingPathComponent(appName)
            let plistURL = targetApp.appendingPathComponent("Info.plist")
            guard let data = try? Data(contentsOf: plistURL) else { return nil }
            guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
            return plist["CFBundleIdentifier"] as? String
        }

        /// Spawn `iostesting alerts watch` as a child process so the watcher
        /// runs concurrently with the test. The child is terminated when the
        /// test run finishes (via the defer in `run()`).
        private func spawnAlertWatcher(
            udid: String,
            durationSeconds: Double,
            labels: [String],
            json: Bool
        ) -> Process? {
            let myExec = ProcessInfo.processInfo.arguments.first.map { URL(fileURLWithPath: $0) }
                ?? URL(fileURLWithPath: "/usr/local/bin/iostesting")
            var args = ["alerts", "watch",
                        "--sim", udid,
                        "--duration", String(durationSeconds),
                        "--interval", "2.0"]
            for l in labels {
                args.append("--label")
                args.append(l)
            }
            if json { args.append("--json") }
            let p = Process()
            p.executableURL = myExec
            p.arguments = args
            // Inherit the FB backend (the watcher's FBSimulatorHID.tap needs it).
            var env = ProcessInfo.processInfo.environment
            env["IOSTESTING_BACKEND"] = "fb"
            p.environment = env
            // Watcher emits diagnostics to stderr; piping its stdout/stderr to
            // ours keeps the agent-facing output coherent.
            p.standardOutput = FileHandle.standardError  // status lines go to stderr
            p.standardError = FileHandle.standardError
            do {
                try p.run()
                FileHandle.standardError.write(Data("test run: spawned alert watcher (pid \(p.processIdentifier), duration \(durationSeconds)s)\n".utf8))
                return p
            } catch {
                FileHandle.standardError.write(Data("test run: failed to spawn alert watcher: \((error as NSError).localizedDescription)\n".utf8))
                return nil
            }
        }

        private func renderHuman(_ event: TestEvent) {
            switch event {
            case .suiteStarted(let name):
                print("▸ \(name)")
            case .caseStarted:
                break
            case .casePassed(let name, let d):
                print("  ✓ \(name) (\(String(format: "%.3f", d))s)")
            case .caseFailed(let name, let d, _):
                print("  ✗ \(name) (\(String(format: "%.3f", d))s)")
            case .caseSkipped(let name):
                print("  - \(name) (skipped)")
            case .suiteFinished(let name, let p, let f, let s, let d):
                print("◂ \(name): \(p) passed, \(f) failed, \(s) skipped (\(String(format: "%.3f", d))s)")
            case .runFinished(let p, let f, let s, let d):
                print("")
                print("\(p) passed, \(f) failed, \(s) skipped in \(String(format: "%.3f", d))s")
            }
        }
    }
}
