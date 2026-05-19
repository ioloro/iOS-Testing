import ArgumentParser
import Foundation

struct Sim: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Simulator lifecycle, IO, and state.",
        subcommands: [
            List.self, Boot.self, Shutdown.self, Erase.self, Create.self,
            Prune.self, MediaAdd.self, Location.self, Button.self, Appearance.self, OpenURL.self
        ]
    )
}

extension Sim {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List available simulators.")
        @Flag(name: .long) var json: Bool = false
        @Option(name: .long, help: "Only show simulators in this state (e.g. Booted, Shutdown).") var state: String?
        @Option(name: .long, help: "Filter by runtime substring (e.g. \"iOS 26\").") var runtime: String?
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simList); return }
            var sims = try await backend.listSimulators()
            if let state { sims = sims.filter { $0.state == state } }
            if let runtime { sims = sims.filter { $0.runtime.contains(runtime) } }
            if json {
                try JSONOutput.emit(sims)
                return
            }
            for s in sims {
                let marker = s.isBooted ? "●" : " "
                print("\(marker) \(s.name.padding(toLength: 30, withPad: " ", startingAt: 0))  \(s.runtime.padding(toLength: 14, withPad: " ", startingAt: 0))  \(s.state.padding(toLength: 10, withPad: " ", startingAt: 0))  \(s.udid)")
            }
        }
    }

    struct Boot: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "boot", abstract: "Boot a simulator. Idempotent.")
        @Argument(help: "Simulator name or UDID.") var nameOrUDID: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simBoot); return }
            if nameOrUDID.isEmpty { IOSTesting.fail("Missing required argument: <name-or-udid>.") }
            let sim = try await backend.resolveSimulator(nameOrUDID)
            try await backend.boot(udid: sim.udid)
            if json {
                try JSONOutput.emit(SimulatorAction(udid: sim.udid, name: sim.name, action: "boot", state: "Booted"))
            } else {
                print("Booted \(sim.name) (\(sim.udid))")
            }
        }
    }

    struct Shutdown: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "shutdown", abstract: "Shut down a simulator. Idempotent.")
        @Argument(help: "Simulator name or UDID.") var nameOrUDID: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simShutdown); return }
            if nameOrUDID.isEmpty { IOSTesting.fail("Missing required argument: <name-or-udid>.") }
            let sim = try await backend.resolveSimulator(nameOrUDID)
            try await backend.shutdown(udid: sim.udid)
            if json {
                try JSONOutput.emit(SimulatorAction(udid: sim.udid, name: sim.name, action: "shutdown", state: "Shutdown"))
            } else {
                print("Shut down \(sim.name) (\(sim.udid))")
            }
        }
    }

    struct Erase: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "erase", abstract: "Erase a simulator. Destructive.")
        @Argument(help: "Simulator name or UDID.") var nameOrUDID: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simErase); return }
            if nameOrUDID.isEmpty { IOSTesting.fail("Missing required argument: <name-or-udid>.") }
            let sim = try await backend.resolveSimulator(nameOrUDID)
            try await backend.erase(udid: sim.udid)
            if json {
                try JSONOutput.emit(SimulatorAction(udid: sim.udid, name: sim.name, action: "erase"))
            } else {
                print("Erased \(sim.name) (\(sim.udid))")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new simulator.")
        @Option(name: .long, help: "Display name.") var name: String = ""
        @Option(name: .long, help: "Device type identifier (e.g. \"iPhone 17 Pro\" or \"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\").") var deviceType: String = ""
        @Option(name: .long, help: "Runtime identifier (e.g. \"iOS26.2\" or full identifier).") var runtime: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simCreate); return }
            if name.isEmpty || deviceType.isEmpty || runtime.isEmpty {
                IOSTesting.fail("--name, --device-type, and --runtime are required.")
            }
            let udid = try await backend.createSimulator(name: name, deviceType: deviceType, runtime: runtime)
            if json {
                try JSONOutput.emit(CreatedSimOutput(udid: udid, name: name))
            } else {
                print("Created \(name) (\(udid))")
            }
        }
    }

    struct Prune: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "prune", abstract: "Delete simulators marked unavailable.")
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simPrune); return }
            let removed = try await backend.pruneUnavailableSimulators()
            if json {
                struct R: Encodable { let removed: Int }
                try JSONOutput.emit(R(removed: removed))
            } else {
                print("Pruned \(removed) unavailable simulator\(removed == 1 ? "" : "s").")
            }
        }
    }

    struct MediaAdd: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "media-add", abstract: "Add photos or videos to the camera roll.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "One or more file paths.") var files: [String] = []
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simMediaAdd); return }
            if files.isEmpty { IOSTesting.fail("Pass at least one file path.") }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            let urls = files.map { URL(fileURLWithPath: $0) }
            try await backend.addMedia(udid: resolved.udid, files: urls)
            if json {
                struct R: Encodable { let udid: String; let added: [String] }
                try JSONOutput.emit(R(udid: resolved.udid, added: files))
            } else {
                print("Added \(files.count) item\(files.count == 1 ? "" : "s") to camera roll on \(resolved.name)")
            }
        }
    }

    struct Location: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "location", abstract: "Override or clear the simulator's location.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, help: "Set location, e.g. \"37.7749,-122.4194\".") var set: String?
        @Flag(name: .long, help: "Clear the override and resume real-or-default behavior.") var clear: Bool = false
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simLocation); return }
            guard set != nil || clear else {
                IOSTesting.fail("Pass --set lat,lon or --clear.")
            }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            if clear {
                try await backend.clearLocation(udid: resolved.udid)
                if json {
                    struct R: Encodable { let udid: String; let cleared: Bool }
                    try JSONOutput.emit(R(udid: resolved.udid, cleared: true))
                } else {
                    print("Cleared location on \(resolved.name)")
                }
                return
            }
            guard let raw = set else { return }
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
                IOSTesting.fail("--set expects 'lat,lon' (got '\(raw)').")
            }
            try await backend.setLocation(udid: resolved.udid, latitude: lat, longitude: lon)
            if json {
                struct R: Encodable { let udid: String; let latitude: Double; let longitude: Double }
                try JSONOutput.emit(R(udid: resolved.udid, latitude: lat, longitude: lon))
            } else {
                print("Set location \(lat),\(lon) on \(resolved.name)")
            }
        }
    }

    struct Button: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "button", abstract: "Press a hardware button (home/lock/siri/side/apple-pay).")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Button name: home, lock, siri, side, apple-pay.") var name: String = ""
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simButton); return }
            if name.isEmpty { IOSTesting.fail("Pass a button name (home, lock, siri, side, apple-pay).") }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            try await backend.pressButton(udid: resolved.udid, button: name)
            print("Pressed \(name) on \(resolved.name)")
        }
    }

    struct Appearance: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "appearance", abstract: "Set the simulator appearance to light or dark.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Appearance: light | dark.") var appearance: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simAppearance); return }
            if appearance.isEmpty { IOSTesting.fail("Pass an appearance: light or dark.") }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            try await backend.setAppearance(udid: resolved.udid, appearance: appearance)
            if json {
                struct R: Encodable { let udid: String; let appearance: String }
                try JSONOutput.emit(R(udid: resolved.udid, appearance: appearance.lowercased()))
            } else {
                print("Set \(appearance.lowercased()) appearance on \(resolved.name)")
            }
        }
    }

    struct OpenURL: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "open-url", abstract: "Open a URL (universal link or scheme) on the simulator.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "URL to open.") var url: String = ""
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simOpenURL); return }
            if url.isEmpty { IOSTesting.fail("Pass a URL.") }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            try await backend.openURL(udid: resolved.udid, url: url)
            print("Opened \(url) on \(resolved.name)")
        }
    }
}
