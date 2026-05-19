import ArgumentParser
import Foundation

struct Logs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "logs", abstract: "Stream logs from a simulator. Ctrl-C to stop.")
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` or the short-id's sim if omitted.") var sim: String?
    @Option(name: .long, help: "Filter by bundle identifier OR short ID from `iostesting apps`. Defaults to `iostesting config` bundleId.") var bundleId: String?
    @Option(name: .long, help: "Raw NSPredicate string (overrides --bundle-id).") var predicate: String?
    @Flag(name: .long, help: "Emit NDJSON, one event per line.") var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.logs); return }
        // Short-ID resolution: if --bundle-id is a known short ID, use its sim + bundle.
        var effectiveSimSource = sim
        var effectiveBundle = bundleId
        if let raw = bundleId, let record = try? AppRegistry.find(byShortId: raw) {
            effectiveBundle = record.bundleId
            effectiveSimSource = effectiveSimSource ?? record.simUDID
        }
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: effectiveSimSource))
        let useJSON = json
        let resolvedBundle = effectiveBundle ?? (try? ConfigStore.loadEffective().config.bundleId)
        try await backend.streamLogs(
            udid: resolved.udid,
            bundleId: resolvedBundle,
            predicate: predicate
        ) { event in
            if useJSON {
                try? JSONOutput.emitLine(event)
            } else {
                let ts = event.timestamp.isEmpty ? "" : "\(event.timestamp) "
                let lvl = event.level.map { "[\($0)] " } ?? ""
                let bid = event.bundleId.map { "(\($0)) " } ?? ""
                print("\(ts)\(lvl)\(bid)\(event.message)")
            }
        }
    }
}
