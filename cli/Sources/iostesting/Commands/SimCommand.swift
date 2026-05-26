import ArgumentParser
import Foundation

struct Sim: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sim",
        abstract: "Simulator lifecycle, IO, and state.",
        subcommands: [
            List.self, Boot.self, Shutdown.self, Erase.self, Create.self,
            Prune.self, MediaAdd.self, Location.self, Button.self, Appearance.self, OpenURL.self,
            Env.self
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
        static let configuration = CommandConfiguration(commandName: "location", abstract: "Override, clear, replay, or report the simulator's location.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, help: "Set a single location, e.g. \"37.7749,-122.4194\".") var set: String?
        @Flag(name: .long, help: "Clear the override and resume real-or-default behavior.") var clear: Bool = false
        @Option(name: .long, help: "Path to a GPX file. Track points are replayed as a location feed.") var gpx: String?
        @Option(name: .long, help: "Seconds between waypoints when replaying a track. Default 1.") var interval: Double = 1.0
        @Option(name: .long, help: "Cap the number of waypoints fed to simctl. Default 1500.") var maxWaypoints: Int = 1500
        @Flag(name: .long, help: "Print the recorded location state for the resolved sim and exit.") var status: Bool = false
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simLocation); return }
            // Mode count check: exactly one of --status / --clear / --set / --gpx.
            let modes = [status, clear, set != nil, gpx != nil].filter { $0 }.count
            guard modes == 1 else {
                IOSTesting.fail("Pass exactly one of --set, --clear, --gpx, or --status.")
            }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))

            if status {
                try runStatus(udid: resolved.udid, name: resolved.name)
                return
            }
            if clear {
                try await backend.clearLocation(udid: resolved.udid)
                LocationStateStore.save(LocationStateRecord(
                    udid: resolved.udid,
                    mode: .cleared,
                    latitude: nil,
                    longitude: nil,
                    waypointCount: nil,
                    intervalSeconds: nil,
                    source: nil,
                    updatedAt: Date()
                ))
                if json {
                    struct R: Encodable { let udid: String; let cleared: Bool }
                    try JSONOutput.emit(R(udid: resolved.udid, cleared: true))
                } else {
                    print("Cleared location on \(resolved.name)")
                }
                return
            }
            if let gpxPath = gpx {
                try await runGPX(path: gpxPath, udid: resolved.udid, name: resolved.name)
                return
            }
            guard let raw = set else { return }
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else {
                IOSTesting.fail("--set expects 'lat,lon' (got '\(raw)').")
            }
            try await backend.setLocation(udid: resolved.udid, latitude: lat, longitude: lon)
            LocationStateStore.save(LocationStateRecord(
                udid: resolved.udid,
                mode: .point,
                latitude: lat,
                longitude: lon,
                waypointCount: 1,
                intervalSeconds: nil,
                source: nil,
                updatedAt: Date()
            ))
            if json {
                struct R: Encodable { let udid: String; let latitude: Double; let longitude: Double }
                try JSONOutput.emit(R(udid: resolved.udid, latitude: lat, longitude: lon))
            } else {
                print("Set location \(lat),\(lon) on \(resolved.name)")
            }
        }

        private func runGPX(path: String, udid: String, name: String) async throws {
            guard interval > 0 else { IOSTesting.fail("--interval must be greater than 0.") }
            guard maxWaypoints > 0 else { IOSTesting.fail("--max-waypoints must be greater than 0.") }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let waypoints: [GPXParser.Waypoint]
            do {
                waypoints = try GPXParser.parse(fileAt: url)
            } catch {
                IOSTesting.fail("\(error)")
            }
            let capped = waypoints.count > maxWaypoints ? Array(waypoints.prefix(maxWaypoints)) : waypoints
            let tuples: [(latitude: Double, longitude: Double)] = capped.map { ($0.latitude, $0.longitude) }
            try await backend.startLocationTrack(udid: udid, waypoints: tuples, intervalSeconds: interval)
            LocationStateStore.save(LocationStateRecord(
                udid: udid,
                mode: .track,
                latitude: tuples.first?.latitude,
                longitude: tuples.first?.longitude,
                waypointCount: tuples.count,
                intervalSeconds: interval,
                source: url.path,
                updatedAt: Date()
            ))
            if json {
                struct R: Encodable {
                    let udid: String
                    let waypoints: Int
                    let intervalSeconds: Double
                    let gpx: String
                    let truncated: Bool
                    let totalInFile: Int
                }
                try JSONOutput.emit(R(
                    udid: udid,
                    waypoints: tuples.count,
                    intervalSeconds: interval,
                    gpx: url.path,
                    truncated: waypoints.count > tuples.count,
                    totalInFile: waypoints.count
                ))
            } else {
                let truncatedNote = waypoints.count > tuples.count ? " (truncated from \(waypoints.count))" : ""
                print("Replaying \(tuples.count) waypoints from \(url.lastPathComponent)\(truncatedNote) at \(interval)s intervals on \(name)")
            }
        }

        private func runStatus(udid: String, name: String) throws {
            let record = LocationStateStore.load(udid: udid)
            if json {
                struct R: Encodable {
                    let udid: String
                    let mode: String?
                    let latitude: Double?
                    let longitude: Double?
                    let waypointCount: Int?
                    let intervalSeconds: Double?
                    let source: String?
                    let updatedAt: String?
                }
                let payload = R(
                    udid: udid,
                    mode: record?.mode.rawValue,
                    latitude: record?.latitude,
                    longitude: record?.longitude,
                    waypointCount: record?.waypointCount,
                    intervalSeconds: record?.intervalSeconds,
                    source: record?.source,
                    updatedAt: record.map { ISO8601DateFormatter().string(from: $0.updatedAt) }
                )
                try JSONOutput.emit(payload)
                return
            }
            guard let record else {
                print("No iostesting-managed location state for \(name) (\(udid)). Note: status only reflects iostesting writes; raw simctl calls are invisible.")
                return
            }
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            let when = formatter.string(from: record.updatedAt)
            switch record.mode {
            case .cleared:
                print("Location cleared on \(name) at \(when).")
            case .point:
                let lat = record.latitude.map { String($0) } ?? "?"
                let lon = record.longitude.map { String($0) } ?? "?"
                print("Single-point override \(lat),\(lon) on \(name) (set at \(when)).")
            case .track:
                let count = record.waypointCount ?? 0
                let interval = record.intervalSeconds ?? 0
                let src = record.source.map { " from \($0)" } ?? ""
                print("Track replay: \(count) waypoints at \(interval)s\(src) on \(name) (started \(when)).")
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

    struct Env: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "env",
            abstract: "Set or unset a launchd environment variable on a booted simulator. Newly-launched processes inherit the value; existing processes are unaffected."
        )
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, help: "Set KEY=VALUE. Repeatable.", transform: { $0 }) var set: [String] = []
        @Option(name: .long, help: "Unset KEY. Repeatable.") var unset: [String] = []
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.simEnv); return }
            if set.isEmpty && unset.isEmpty {
                IOSTesting.fail("Pass --set KEY=VALUE and/or --unset KEY at least once.")
            }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            var setApplied: [(String, String)] = []
            for entry in set {
                guard let eq = entry.firstIndex(of: "=") else {
                    IOSTesting.fail("--set entries must be KEY=VALUE; got '\(entry)'")
                }
                let key = String(entry[..<eq])
                let value = String(entry[entry.index(after: eq)...])
                if key.isEmpty { IOSTesting.fail("--set entry '\(entry)' has empty KEY.") }
                try await backend.setSimEnv(udid: resolved.udid, key: key, value: value)
                setApplied.append((key, value))
            }
            for key in unset {
                if key.isEmpty { IOSTesting.fail("--unset key may not be empty.") }
                try await backend.unsetSimEnv(udid: resolved.udid, key: key)
            }
            if json {
                struct R: Encodable {
                    let udid: String
                    let setKeys: [String]
                    let unsetKeys: [String]
                }
                try JSONOutput.emit(R(
                    udid: resolved.udid,
                    setKeys: setApplied.map { $0.0 },
                    unsetKeys: unset
                ))
            } else {
                for (k, _) in setApplied { print("set \(k) on \(resolved.name)") }
                for k in unset { print("unset \(k) on \(resolved.name)") }
            }
        }
    }
}
