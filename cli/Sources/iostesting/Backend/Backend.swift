import Foundation

struct Simulator: Codable, Sendable {
    let udid: String
    let name: String
    let runtime: String
    let deviceType: String
    let state: String

    var isBooted: Bool { state == "Booted" }
}

struct LaunchResult: Codable, Sendable {
    let pid: Int32
    let bundleId: String
}

struct TestCase: Codable, Sendable {
    let target: String
    let suite: String
    let name: String

    var triple: String { "\(target)/\(suite)/\(name)" }
}

struct LogEvent: Codable, Sendable {
    let timestamp: String
    let bundleId: String?
    let level: String?
    let message: String
}

enum TestEvent: Codable, Sendable {
    case suiteStarted(name: String)
    case caseStarted(name: String)
    case casePassed(name: String, durationSeconds: Double)
    case caseFailed(name: String, durationSeconds: Double, message: String)
    case caseSkipped(name: String)
    case suiteFinished(name: String, passed: Int, failed: Int, skipped: Int, durationSeconds: Double)
    case runFinished(passed: Int, failed: Int, skipped: Int, durationSeconds: Double)

    private enum CodingKeys: String, CodingKey {
        case event, name, durationSeconds, message, passed, failed, skipped
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .suiteStarted(let name):
            try c.encode("suiteStarted", forKey: .event)
            try c.encode(name, forKey: .name)
        case .caseStarted(let name):
            try c.encode("caseStarted", forKey: .event)
            try c.encode(name, forKey: .name)
        case .casePassed(let name, let d):
            try c.encode("casePassed", forKey: .event)
            try c.encode(name, forKey: .name)
            try c.encode(d, forKey: .durationSeconds)
        case .caseFailed(let name, let d, let msg):
            try c.encode("caseFailed", forKey: .event)
            try c.encode(name, forKey: .name)
            try c.encode(d, forKey: .durationSeconds)
            try c.encode(msg, forKey: .message)
        case .caseSkipped(let name):
            try c.encode("caseSkipped", forKey: .event)
            try c.encode(name, forKey: .name)
        case .suiteFinished(let name, let p, let f, let s, let d):
            try c.encode("suiteFinished", forKey: .event)
            try c.encode(name, forKey: .name)
            try c.encode(p, forKey: .passed)
            try c.encode(f, forKey: .failed)
            try c.encode(s, forKey: .skipped)
            try c.encode(d, forKey: .durationSeconds)
        case .runFinished(let p, let f, let s, let d):
            try c.encode("runFinished", forKey: .event)
            try c.encode(p, forKey: .passed)
            try c.encode(f, forKey: .failed)
            try c.encode(s, forKey: .skipped)
            try c.encode(d, forKey: .durationSeconds)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let event = try c.decode(String.self, forKey: .event)
        switch event {
        case "suiteStarted":
            self = .suiteStarted(name: try c.decode(String.self, forKey: .name))
        case "caseStarted":
            self = .caseStarted(name: try c.decode(String.self, forKey: .name))
        case "casePassed":
            self = .casePassed(
                name: try c.decode(String.self, forKey: .name),
                durationSeconds: try c.decode(Double.self, forKey: .durationSeconds)
            )
        case "caseFailed":
            self = .caseFailed(
                name: try c.decode(String.self, forKey: .name),
                durationSeconds: try c.decode(Double.self, forKey: .durationSeconds),
                message: try c.decode(String.self, forKey: .message)
            )
        case "caseSkipped":
            self = .caseSkipped(name: try c.decode(String.self, forKey: .name))
        case "suiteFinished":
            self = .suiteFinished(
                name: try c.decode(String.self, forKey: .name),
                passed: try c.decode(Int.self, forKey: .passed),
                failed: try c.decode(Int.self, forKey: .failed),
                skipped: try c.decode(Int.self, forKey: .skipped),
                durationSeconds: try c.decode(Double.self, forKey: .durationSeconds)
            )
        case "runFinished":
            self = .runFinished(
                passed: try c.decode(Int.self, forKey: .passed),
                failed: try c.decode(Int.self, forKey: .failed),
                skipped: try c.decode(Int.self, forKey: .skipped),
                durationSeconds: try c.decode(Double.self, forKey: .durationSeconds)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .event, in: c, debugDescription: "Unknown event \(event)")
        }
    }
}

protocol Backend: Sendable {
    func listSimulators() async throws -> [Simulator]
    func resolveSimulator(_ nameOrUDID: String) async throws -> Simulator

    func boot(udid: String) async throws
    func shutdown(udid: String) async throws
    func erase(udid: String) async throws
    func createSimulator(name: String, deviceType: String, runtime: String) async throws -> String

    func install(udid: String, appPath: URL) async throws
    func uninstall(udid: String, bundleId: String) async throws
    func launch(udid: String, bundleId: String, env: [String: String], args: [String], waitForDebugger: Bool) async throws -> LaunchResult
    func terminate(udid: String, bundleIdOrPID: String) async throws

    func screenshot(udid: String, output: URL) async throws

    func streamLogs(
        udid: String,
        bundleId: String?,
        predicate: String?,
        onEvent: @Sendable @escaping (LogEvent) -> Void
    ) async throws

    func listTests(bundlePath: URL) async throws -> [TestCase]
    func runTests(
        udid: String,
        bundlePath: URL,
        hostApp: URL?,
        filters: [String],
        onEvent: @Sendable @escaping (TestEvent) -> Void
    ) async throws

    // MARK: - Sim extras (both backends implement these; FB backend uses framework calls, simctl uses xcrun shellouts)
    func pruneUnavailableSimulators() async throws -> Int
    func addMedia(udid: String, files: [URL]) async throws
    func setLocation(udid: String, latitude: Double, longitude: Double) async throws
    func clearLocation(udid: String) async throws
    func pressButton(udid: String, button: String) async throws
    func setAppearance(udid: String, appearance: String) async throws
    func openURL(udid: String, url: String) async throws
}
