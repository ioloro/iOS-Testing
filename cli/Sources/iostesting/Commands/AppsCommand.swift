import ArgumentParser
import Foundation

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "apps",
        abstract: "List apps launched by iostesting. Each gets a short ID so you don't need to retype bundle and sim.",
        subcommands: [List.self, Prune.self]
    )

    static let configurationDefaultSubcommand = List.self
}

extension Apps {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List recorded apps.")
        @Flag(name: .long, help: "Include terminated apps.") var all: Bool = false
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.appsList); return }
            let file = try AppRegistry.load()
            let visible = all ? file.apps : file.apps.filter { $0.status == .running }
            if json {
                try JSONOutput.emit(visible)
                return
            }
            if visible.isEmpty {
                print("No \(all ? "" : "running ")apps recorded.")
                return
            }
            for a in visible {
                let mark = a.status == .running ? "●" : "○"
                let bundle = a.bundleId.padding(toLength: 36, withPad: " ", startingAt: 0)
                let sim = a.simName.padding(toLength: 20, withPad: " ", startingAt: 0)
                print("\(mark) \(a.shortId)  \(bundle)  \(sim)  pid \(a.pid)  \(a.status.rawValue)")
            }
        }
    }

    struct Prune: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "prune", abstract: "Remove terminated apps from the registry.")
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.appsPrune); return }
            let removed = try AppRegistry.prune()
            if json {
                struct R: Encodable { let removed: Int }
                try JSONOutput.emit(R(removed: removed))
            } else {
                print("Removed \(removed) terminated record\(removed == 1 ? "" : "s").")
            }
        }
    }
}
