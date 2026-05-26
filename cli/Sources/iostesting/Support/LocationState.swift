import Foundation

/// Best-effort bookkeeping for sim location overrides. simctl doesn't expose
/// "what's currently playing" so we maintain a tiny state file keyed by sim
/// UDID. Write-side: every `--set`, `--clear`, `--gpx` invocation updates
/// the record. Read-side: `--status` prints it.
///
/// Drift caveat: if the user runs `xcrun simctl location ...` directly outside
/// iostesting, our record gets stale. Worth less than the convenience of
/// answering "is a track playing?" without rerunning the whole pipeline.
struct LocationStateRecord: Codable, Sendable {
    enum Mode: String, Codable, Sendable {
        case point
        case track
        case cleared
    }

    let udid: String
    let mode: Mode
    let latitude: Double?
    let longitude: Double?
    let waypointCount: Int?
    let intervalSeconds: Double?
    let source: String?      // e.g. the GPX file path
    let updatedAt: Date
}

enum LocationStateStore {
    private static let directoryName = "iostesting"
    private static let fileName = "sim-location.json"

    static var stateFilePath: URL {
        // ~/Library/Application Support/iostesting/sim-location.json
        let fm = FileManager.default
        let base: URL
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            base = appSupport
        } else {
            base = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        }
        return base
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// All recorded sims, keyed by UDID. Order is undefined.
    static func loadAll() -> [String: LocationStateRecord] {
        let url = stateFilePath
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.iso().decode([String: LocationStateRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    static func load(udid: String) -> LocationStateRecord? {
        loadAll()[udid]
    }

    @discardableResult
    static func save(_ record: LocationStateRecord) -> Bool {
        var all = loadAll()
        all[record.udid] = record
        return persist(all)
    }

    @discardableResult
    static func remove(udid: String) -> Bool {
        var all = loadAll()
        all.removeValue(forKey: udid)
        return persist(all)
    }

    private static func persist(_ all: [String: LocationStateRecord]) -> Bool {
        let url = stateFilePath
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder.iso()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(all)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

private extension JSONEncoder {
    static func iso() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static func iso() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
