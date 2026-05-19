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
        @Flag(name: .long, help: "Emit NDJSON test events on stdout.") var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.testRun); return }
            if bundlePath.isEmpty { IOSTesting.fail("Pass a .xctest bundle path.") }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            let bundle = URL(fileURLWithPath: bundlePath)
            let host = hostApp.map { URL(fileURLWithPath: $0) }
            let useJSON = json
            try await backend.runTests(
                udid: resolved.udid,
                bundlePath: bundle,
                hostApp: host,
                filters: filter
            ) { event in
                if useJSON {
                    try? JSONOutput.emitLine(event)
                } else {
                    renderHuman(event)
                }
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
