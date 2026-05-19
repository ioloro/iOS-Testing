import Foundation

struct AppRecord: Codable, Sendable {
    let shortId: String
    let bundleId: String
    let simUDID: String
    let simName: String
    let pid: Int32
    let launchedAt: Date
    var status: AppStatus
}

enum AppStatus: String, Codable, Sendable {
    case running
    case terminated
}

struct AppRegistryFile: Codable, Sendable {
    var apps: [AppRecord]
}

enum AppRegistry {
    static var registryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("iostesting", isDirectory: true).appendingPathComponent("apps.json")
    }

    private static let lock = NSLock()

    static func load() throws -> AppRegistryFile {
        lock.lock()
        defer { lock.unlock() }
        let url = registryURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AppRegistryFile(apps: [])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.iso8601().decode(AppRegistryFile.self, from: data)
    }

    static func save(_ file: AppRegistryFile) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = registryURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder.iso8601(pretty: true)
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    static func record(bundleId: String, simUDID: String, simName: String, pid: Int32) throws -> AppRecord {
        var file = try load()
        let shortId = mintShortID(existing: Set(file.apps.map(\.shortId)))
        let record = AppRecord(
            shortId: shortId,
            bundleId: bundleId,
            simUDID: simUDID,
            simName: simName,
            pid: pid,
            launchedAt: Date(),
            status: .running
        )
        file.apps.append(record)
        try save(file)
        return record
    }

    /// Locate by short ID or PID. Returns the most recent matching record.
    static func find(byShortId shortId: String) throws -> AppRecord? {
        let file = try load()
        return file.apps.last(where: { $0.shortId == shortId })
    }

    static func markTerminated(matching predicate: (AppRecord) -> Bool) throws {
        var file = try load()
        for i in file.apps.indices where predicate(file.apps[i]) {
            file.apps[i].status = .terminated
        }
        try save(file)
    }

    static func prune() throws -> Int {
        var file = try load()
        let before = file.apps.count
        file.apps.removeAll { $0.status == .terminated }
        let removed = before - file.apps.count
        try save(file)
        return removed
    }

    // MARK: - Short ID minting

    private static let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789") // no 0/o/l/1 to avoid confusion

    private static func mintShortID(existing: Set<String>, length: Int = 6) -> String {
        for _ in 0..<32 {
            var id = ""
            for _ in 0..<length {
                id.append(alphabet.randomElement()!)
            }
            if !existing.contains(id) { return id }
        }
        // Fallback: timestamp-derived ID
        return String(Int(Date().timeIntervalSince1970 * 1000) % 0xFFFFFF, radix: 36)
    }
}

extension JSONEncoder {
    static func iso8601(pretty: Bool) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
