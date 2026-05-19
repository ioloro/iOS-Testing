import ArgumentParser
import Foundation

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Save defaults so you don't have to type --sim and bundle ids on every command.",
        subcommands: [Show.self, Get.self, Set.self, Reset.self]
    )
}

extension ConfigCommand {
    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Show the effective config and where each value came from.")
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.configShow); return }
            var (effective, sources) = try ConfigStore.loadEffective()
            // Env vars take precedence in `iostesting config show` too.
            let env = ProcessInfo.processInfo.environment
            if let s = env["IOSTESTING_SIM"], !s.isEmpty {
                effective.sim = s
                sources["sim"] = .env
            }
            if let b = env["IOSTESTING_BUNDLE_ID"], !b.isEmpty {
                effective.bundleId = b
                sources["bundleId"] = .env
            }
            if json {
                struct Payload: Encodable {
                    let sim: String?
                    let bundleId: String?
                    let sources: [String: String]
                    let projectFile: String?
                    let globalFile: String
                }
                let payload = Payload(
                    sim: effective.sim,
                    bundleId: effective.bundleId,
                    sources: sources.mapValues { $0.rawValue },
                    projectFile: ConfigStore.locateProjectFile()?.path,
                    globalFile: ConfigStore.globalPath.path
                )
                try JSONOutput.emit(payload)
                return
            }
            print("Effective config:")
            print("  sim:        \(effective.sim ?? "<unset>")  [\(sources["sim"]?.rawValue ?? "default")]")
            print("  bundleId:   \(effective.bundleId ?? "<unset>")  [\(sources["bundleId"]?.rawValue ?? "default")]")
            print("")
            print("Project file: \(ConfigStore.locateProjectFile()?.path ?? "<none found>")")
            print("Global file:  \(ConfigStore.globalPath.path)")
            print("Env vars:     IOSTESTING_SIM, IOSTESTING_BUNDLE_ID  (override saved config)")
        }
    }

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "get", abstract: "Print a single config value.")
        @Argument(help: "Key (sim | bundleId).") var key: String = ""
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.configGet); return }
            if key.isEmpty { IOSTesting.fail("Pass a key (sim or bundleId).") }
            let effective = try ConfigStore.loadEffective().config
            switch key {
            case "sim":
                if let v = effective.sim { print(v) }
            case "bundleId", "bundle-id":
                if let v = effective.bundleId { print(v) }
            default:
                IOSTesting.fail("Unknown key '\(key)'. Known keys: sim, bundleId.")
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "set", abstract: "Set one or more config values.")
        @Option(name: .long, help: "Default simulator name or UDID.") var sim: String?
        @Option(name: .long, help: "Default bundle identifier.") var bundleId: String?
        @Flag(name: .long, help: "Write to the global config (~/.config/iostesting/config.json) instead of project.") var global: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.configSet); return }
            if sim == nil && bundleId == nil {
                IOSTesting.fail("Pass at least one of --sim, --bundle-id.")
            }
            let scope: ConfigScope = global ? .global : .project
            var current = try ConfigStore.load(scope: scope)
            if let v = sim { current.sim = v }
            if let v = bundleId { current.bundleId = v }
            let written = try ConfigStore.save(current, scope: scope)
            print("Wrote \(written.path)")
        }
    }

    struct Reset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "reset", abstract: "Delete the config file for a scope.")
        @Flag(name: .long, help: "Reset the global config instead of project.") var global: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.configReset); return }
            let scope: ConfigScope = global ? .global : .project
            try ConfigStore.reset(scope: scope)
            print("Cleared \(scope.rawValue) config.")
        }
    }
}
