import ArgumentParser
import Foundation

struct Screenshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "screenshot", abstract: "Capture a PNG screenshot from a simulator.")
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
    @Option(name: [.short, .long], help: "Output PNG path.") var output: String = "./screenshot.png"
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.screenshot); return }
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
        let url = URL(fileURLWithPath: output)
        try await backend.screenshot(udid: resolved.udid, output: url)
        if json {
            try JSONOutput.emit(PathOutput(path: url.path, udid: resolved.udid))
        } else {
            print("Wrote \(url.path)")
        }
    }
}
