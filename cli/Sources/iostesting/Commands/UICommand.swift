import ArgumentParser
import Foundation
import FBBridge

struct UI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ui",
        abstract: "UI automation on a simulator. Requires IOSTESTING_BACKEND=fb (FB framework backed).",
        subcommands: [Tap.self, Swipe.self]
    )
}

extension UI {
    struct Tap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tap", abstract: "Tap at point coordinates (no @2x scaling).")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, help: "X coordinate (point space).") var x: Double
        @Option(name: .long, help: "Y coordinate (point space).") var y: Double
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.uiTap); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            do { try FBBridge.tapAt(x: x, y: y, onSimulator: resolved.udid) }
            catch { IOSTesting.fail("tap failed: \((error as NSError).localizedDescription)") }
            print("tap (\(x),\(y)) on \(resolved.name)")
        }
    }

    struct Swipe: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "swipe", abstract: "Swipe from (x1,y1) to (x2,y2).")
        @Option(name: [.short, .long], help: "Simulator name or UDID.") var sim: String?
        @Option(name: .long) var x1: Double
        @Option(name: .long) var y1: Double
        @Option(name: .long) var x2: Double
        @Option(name: .long) var y2: Double
        @Option(name: .long, help: "Swipe duration in seconds.") var duration: Double = 0.3
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.uiSwipe); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            do {
                try FBBridge.swipeFrom(x: x1, y: y1, toX: x2, y: y2,
                                       duration: duration, onSimulator: resolved.udid)
            } catch {
                IOSTesting.fail("swipe failed: \((error as NSError).localizedDescription)")
            }
            print("swipe (\(x1),\(y1)) → (\(x2),\(y2)) on \(resolved.name)")
        }
    }
}
