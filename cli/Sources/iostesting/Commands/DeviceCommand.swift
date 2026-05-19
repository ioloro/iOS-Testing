import ArgumentParser
import Foundation

struct Device: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "device",
        abstract: "Physical iOS devices via `xcrun devicectl`. A follow-up release will swap to FBDeviceControl for log streaming + richer device ops.",
        subcommands: [List.self, Install.self, Launch.self]
    )
}

struct DeviceInfo: Codable, Sendable {
    let identifier: String
    let name: String
    let platform: String?
    let osVersion: String?
    let state: String?
}

extension Device {
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List paired devices.")
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.deviceList); return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("iostesting-devices-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: tmp) }
            _ = try await Shell.runChecked("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", tmp.path, "--quiet"])
            let data = try Data(contentsOf: tmp)
            let parsed = try parseDeviceList(data: data)
            if json {
                try JSONOutput.emit(parsed)
                return
            }
            if parsed.isEmpty {
                print("No paired devices. Pair via Xcode > Window > Devices and Simulators.")
                return
            }
            for d in parsed {
                let plat = d.platform ?? "?"
                let os = d.osVersion ?? "?"
                let st = d.state ?? "?"
                print("\(d.identifier)  \(d.name.padding(toLength: 24, withPad: " ", startingAt: 0))  \(plat) \(os)  \(st)")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "install", abstract: "Install a built .app or .ipa onto a device.")
        @Option(name: [.short, .long], help: "Device identifier from `iostesting device list`.") var device: String = ""
        @Argument(help: "Path to .app or .ipa.") var appPath: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.deviceInstall); return }
            if device.isEmpty || appPath.isEmpty { IOSTesting.fail("--device and <app-path> are required.") }
            _ = try await Shell.runChecked("/usr/bin/xcrun", [
                "devicectl", "device", "install", "app",
                "--device", device,
                appPath
            ])
            if json {
                struct R: Encodable { let device: String; let installed: String }
                try JSONOutput.emit(R(device: device, installed: appPath))
            } else {
                print("Installed \(URL(fileURLWithPath: appPath).lastPathComponent) on device \(device)")
            }
        }
    }

    struct Launch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "launch", abstract: "Launch an installed app on a device.")
        @Option(name: [.short, .long], help: "Device identifier.") var device: String = ""
        @Argument(help: "Bundle identifier.") var bundleId: String = ""
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.deviceLaunch); return }
            if device.isEmpty || bundleId.isEmpty { IOSTesting.fail("--device and <bundle-id> are required.") }
            _ = try await Shell.runChecked("/usr/bin/xcrun", [
                "devicectl", "device", "process", "launch",
                "--device", device,
                bundleId
            ])
            if json {
                struct R: Encodable { let device: String; let launched: String }
                try JSONOutput.emit(R(device: device, launched: bundleId))
            } else {
                print("Launched \(bundleId) on device \(device)")
            }
        }
    }
}

private func parseDeviceList(data: Data) throws -> [DeviceInfo] {
    // devicectl's --json-output format: { "result": { "devices": [ {...} ] }, "info": {...} }
    struct Envelope: Decodable {
        struct Result: Decodable {
            let devices: [Device]?
        }
        struct Device: Decodable {
            let identifier: String?
            let deviceProperties: Properties?
            let hardwareProperties: Hardware?
            let connectionProperties: Connection?
        }
        struct Properties: Decodable {
            let name: String?
            let osVersionNumber: String?
        }
        struct Hardware: Decodable {
            let platform: String?
        }
        struct Connection: Decodable {
            let tunnelState: String?
        }
        let result: Result?
    }
    let env = try JSONDecoder().decode(Envelope.self, from: data)
    return (env.result?.devices ?? []).compactMap { d in
        guard let id = d.identifier else { return nil }
        return DeviceInfo(
            identifier: id,
            name: d.deviceProperties?.name ?? "?",
            platform: d.hardwareProperties?.platform,
            osVersion: d.deviceProperties?.osVersionNumber,
            state: d.connectionProperties?.tunnelState
        )
    }
}
