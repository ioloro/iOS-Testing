import Foundation

enum JSONOutput {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static let lineEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    static func emit<T: Encodable>(_ value: T) throws {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    static func emitLine<T: Encodable>(_ value: T) throws {
        let data = try lineEncoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

struct SimulatorAction: Encodable {
    let udid: String
    let name: String
    let action: String
    let state: String?
    let extra: [String: String]?

    init(udid: String, name: String, action: String, state: String? = nil, extra: [String: String]? = nil) {
        self.udid = udid
        self.name = name
        self.action = action
        self.state = state
        self.extra = extra
    }
}

struct PathOutput: Encodable {
    let path: String
    let udid: String?
}

struct InstallOutput: Encodable {
    let udid: String
    let installed: String
}

struct UninstallOutput: Encodable {
    let udid: String
    let uninstalled: String
}

struct StopOutput: Encodable {
    let udid: String
    let stopped: String
}

struct CreatedSimOutput: Encodable {
    let udid: String
    let name: String
}
