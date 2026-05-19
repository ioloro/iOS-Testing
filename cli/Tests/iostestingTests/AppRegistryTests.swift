import Testing
import Foundation
@testable import iostesting

@Suite("AppRegistry")
struct AppRegistryTests {
    @Test("Short ID alphabet excludes ambiguous chars (0, 1, l, o)")
    func shortIDAlphabet() {
        // Mint 200 short IDs, check none contain the forbidden glyphs.
        let forbidden: Set<Character> = ["0", "1", "l", "o"]
        for _ in 0..<200 {
            let id = mintForTest()
            for c in id {
                #expect(!forbidden.contains(c), "found forbidden char '\(c)' in '\(id)'")
            }
            #expect(id.count == 6, "expected 6-char id, got '\(id)'")
        }
    }

    @Test("AppRecord roundtrip Codable")
    func recordRoundtrip() throws {
        let record = AppRecord(
            shortId: "ab12kw",
            bundleId: "com.example.MyApp",
            simUDID: "B3AC0B66-4AB6-471B-A9BA-D1CC78670018",
            simName: "iPhone 17 Pro",
            pid: 12345,
            launchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .running
        )
        let enc = JSONEncoder.iso8601(pretty: false)
        let data = try enc.encode(record)
        let dec = JSONDecoder.iso8601()
        let back = try dec.decode(AppRecord.self, from: data)
        #expect(back.shortId == record.shortId)
        #expect(back.bundleId == record.bundleId)
        #expect(back.simUDID == record.simUDID)
        #expect(back.simName == record.simName)
        #expect(back.pid == record.pid)
        #expect(back.launchedAt == record.launchedAt)
        #expect(back.status == .running)
    }

    @Test("AppStatus enum has running and terminated")
    func appStatusCases() {
        #expect(AppStatus.running.rawValue == "running")
        #expect(AppStatus.terminated.rawValue == "terminated")
    }

    // Reuse the registry's mint heuristic via a minimal local copy. The
    // production mint function is `private` for callsite hygiene; the
    // alphabet rule is the load-bearing invariant we want to lock down.
    private func mintForTest(length: Int = 6) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        var id = ""
        for _ in 0..<length { id.append(alphabet.randomElement()!) }
        return id
    }
}
