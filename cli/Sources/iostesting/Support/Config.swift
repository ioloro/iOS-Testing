import Foundation

struct Config: Codable, Sendable {
    var sim: String?
    var bundleId: String?

    static let empty = Config(sim: nil, bundleId: nil)
}

enum ConfigScope: String, Sendable {
    case project
    case global
    case env
}

enum ConfigStore {
    static let projectDirName = ".iostesting"
    static let projectFileName = "config.json"

    static var globalDir: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("iostesting", isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config", isDirectory: true).appendingPathComponent("iostesting", isDirectory: true)
    }

    static var globalPath: URL { globalDir.appendingPathComponent(projectFileName) }

    /// Walks up from cwd looking for `.iostesting/config.json`. Returns nil if none found.
    static func locateProjectFile(startingAt start: URL? = nil) -> URL? {
        let fm = FileManager.default
        var dir = (start ?? URL(fileURLWithPath: fm.currentDirectoryPath)).resolvingSymlinksInPath()
        let root = URL(fileURLWithPath: "/")
        while true {
            let candidate = dir.appendingPathComponent(projectDirName).appendingPathComponent(projectFileName)
            if fm.fileExists(atPath: candidate.path) { return candidate }
            if dir.path == root.path { return nil }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    static func projectPathFor(scope: ConfigScope) -> URL {
        switch scope {
        case .global:
            return globalPath
        case .project:
            return locateProjectFile()
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(projectDirName)
                    .appendingPathComponent(projectFileName)
        case .env:
            // `.env` is a virtual scope used only in source attribution; it has no file.
            // Callers that save/load should never pass `.env` here.
            fatalError("projectPathFor(.env) is invalid — env scope has no file")
        }
    }

    static func load(scope: ConfigScope) throws -> Config {
        let url = projectPathFor(scope: scope)
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    /// Resolves the effective config by overlaying project on top of global.
    static func loadEffective() throws -> (config: Config, sources: [String: ConfigScope]) {
        var effective = Config.empty
        var sources: [String: ConfigScope] = [:]
        let global = try load(scope: .global)
        if let v = global.sim { effective.sim = v; sources["sim"] = .global }
        if let v = global.bundleId { effective.bundleId = v; sources["bundleId"] = .global }
        let project = try load(scope: .project)
        if let v = project.sim { effective.sim = v; sources["sim"] = .project }
        if let v = project.bundleId { effective.bundleId = v; sources["bundleId"] = .project }
        return (effective, sources)
    }

    static func save(_ config: Config, scope: ConfigScope) throws -> URL {
        let url = projectPathFor(scope: scope)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func reset(scope: ConfigScope) throws {
        let url = projectPathFor(scope: scope)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum ConfigResolve {
    /// Precedence: explicit arg > env var > project config > global config.
    /// IOSTESTING_SIM and IOSTESTING_BUNDLE_ID let CI provide values without writing a config file.
    static func sim(explicit: String?) throws -> String {
        if let s = explicit, !s.isEmpty { return s }
        if let s = ProcessInfo.processInfo.environment["IOSTESTING_SIM"], !s.isEmpty { return s }
        let effective = try ConfigStore.loadEffective().config
        if let s = effective.sim, !s.isEmpty { return s }
        throw BackendError(message: "No simulator specified. Pass `--sim <name>`, set IOSTESTING_SIM, or run `iostesting config set --sim \"iPhone 17 Pro\"`.")
    }

    static func bundleId(explicit: String?) throws -> String {
        if let b = explicit, !b.isEmpty { return b }
        if let b = ProcessInfo.processInfo.environment["IOSTESTING_BUNDLE_ID"], !b.isEmpty { return b }
        let effective = try ConfigStore.loadEffective().config
        if let b = effective.bundleId, !b.isEmpty { return b }
        throw BackendError(message: "No bundle identifier specified. Pass the bundle id, set IOSTESTING_BUNDLE_ID, or run `iostesting config set --bundle-id <id>`.")
    }
}
