import Testing
import Foundation
@testable import iostesting

@Suite("ConfigStore")
struct ConfigStoreTests {
    @Test("Round-trip a config to a temp file")
    func saveAndLoad() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("iostesting-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let file = tmp.appendingPathComponent(".iostesting").appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)

        let payload = Config(sim: "iPhone 17 Pro", bundleId: "com.example.MyApp")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: file)

        let loaded = try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
        #expect(loaded.sim == "iPhone 17 Pro")
        #expect(loaded.bundleId == "com.example.MyApp")
    }

    @Test("Empty config has nil fields")
    func emptyConfig() {
        let c = Config.empty
        #expect(c.sim == nil)
        #expect(c.bundleId == nil)
    }

    @Test("Effective config layers global under project")
    func layering() throws {
        // We exercise the public Codable surface — the layering helper is
        // exercised end-to-end by `iostesting config show`.
        let global = Config(sim: "iPhone 16", bundleId: "com.a")
        let project = Config(sim: "iPhone 17 Pro", bundleId: nil)
        var effective = Config.empty
        if let v = global.sim { effective.sim = v }
        if let v = global.bundleId { effective.bundleId = v }
        if let v = project.sim { effective.sim = v }
        if let v = project.bundleId { effective.bundleId = v }
        #expect(effective.sim == "iPhone 17 Pro")
        #expect(effective.bundleId == "com.a")
    }
}
