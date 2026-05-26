import Testing
import Foundation
@testable import iostesting

@Suite("SetupCommand")
struct SetupCommandTests {
    @Test("Merging into an empty root appends every iostesting entry, in declaration order")
    func emptyRoot() {
        let entries = SetupCommand.iostestingPermissions
        let result = SetupCommand.mergePermissions(into: [:], adding: entries)
        let permissions = result.root["permissions"] as? [String: Any]
        let allow = permissions?["allow"] as? [String]
        #expect(allow == entries, "allow should equal the entries list in order")
        #expect(result.added == entries, "every entry is reported as added")
        #expect(result.alreadyPresent.isEmpty, "nothing should be already-present")
    }

    @Test("Merging twice is a no-op the second time")
    func idempotent() {
        let entries = SetupCommand.iostestingPermissions
        let first = SetupCommand.mergePermissions(into: [:], adding: entries)
        let second = SetupCommand.mergePermissions(into: first.root, adding: entries)
        #expect(second.added.isEmpty, "second merge should add nothing")
        #expect(second.alreadyPresent == entries, "second merge should report all as already-present")
        let allow = (second.root["permissions"] as? [String: Any])?["allow"] as? [String]
        #expect(allow == entries, "allow list is unchanged on the second merge")
    }

    @Test("Existing allow entries are preserved in their original order, iostesting entries appended")
    func preservesExistingOrder() {
        let preExisting: [String] = [
            "Bash(git status:*)",
            "Bash(git log:*)",
            "Bash(iostesting:*)"
        ]
        let root: [String: Any] = [
            "permissions": ["allow": preExisting]
        ]
        let result = SetupCommand.mergePermissions(
            into: root,
            adding: SetupCommand.iostestingPermissions
        )
        let allow = (result.root["permissions"] as? [String: Any])?["allow"] as? [String]
        #expect(allow?.prefix(preExisting.count).elementsEqual(preExisting) == true,
                "pre-existing entries must keep their order at the front")
        // iostesting:* was already present so it should not be re-added.
        #expect(result.added.contains("Bash(iostesting:*)") == false,
                "already-present iostesting entry must not be duplicated")
        #expect(result.alreadyPresent.contains("Bash(iostesting:*)"),
                "iostesting:* should be reported as already present")
    }

    @Test("Unknown top-level keys are preserved")
    func preservesUnknownTopLevelKeys() {
        let root: [String: Any] = [
            "effortLevel": "medium",
            "enabledPlugins": ["ios-testing@ioloro": true],
            "mcpServers": ["custom-server": ["command": "/usr/local/bin/server"]]
        ]
        let result = SetupCommand.mergePermissions(
            into: root,
            adding: SetupCommand.iostestingPermissions
        )
        #expect(result.root["effortLevel"] as? String == "medium")
        #expect((result.root["enabledPlugins"] as? [String: Any])?["ios-testing@ioloro"] as? Bool == true)
        #expect((result.root["mcpServers"] as? [String: Any])?["custom-server"] != nil)
    }

    @Test("Unknown keys inside permissions are preserved (e.g. deny)")
    func preservesPermissionsSiblingKeys() {
        let root: [String: Any] = [
            "permissions": [
                "allow": ["Bash(git status:*)"],
                "deny": ["Bash(rm -rf:*)"]
            ]
        ]
        let result = SetupCommand.mergePermissions(
            into: root,
            adding: SetupCommand.iostestingPermissions
        )
        let permissions = result.root["permissions"] as? [String: Any]
        let deny = permissions?["deny"] as? [String]
        #expect(deny == ["Bash(rm -rf:*)"], "sibling key 'deny' must survive the merge")
    }

    @Test("Curated list contains exactly the 8 expected entries, no MCP or full-path forms")
    func curatedListShape() {
        let entries = SetupCommand.iostestingPermissions
        #expect(entries.count == 8, "expected 8 curated permissions, got \(entries.count)")
        for entry in entries {
            #expect(entry.hasPrefix("Bash("), "every entry should be a Bash(...) pattern, got '\(entry)'")
            #expect(!entry.contains("mcp__"), "no MCP entries should be in the curated list")
            #expect(!entry.contains("/Users/"), "no machine-specific full paths should be in the curated list")
        }
        // Spot-check a couple of key entries the curated list MUST include.
        let must = [
            "Bash(xcrun simctl spawn:*)",
            "Bash(xcrun simctl location:*)",
            "Bash(xcodebuild build-for-testing:*)",
            "Bash(iostesting:*)"
        ]
        for entry in must {
            #expect(entries.contains(entry), "curated list missing required entry '\(entry)'")
        }
    }

    @Test("End-to-end: write then re-merge from disk is a no-op")
    func endToEndWriteAndReread() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iostesting-setup-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let settingsURL = tmpDir.appendingPathComponent("settings.json")

        // Seed with a hand-edited-looking file.
        let seed: [String: Any] = [
            "effortLevel": "medium",
            "permissions": ["allow": ["Bash(git status:*)"]]
        ]
        let seedData = try JSONSerialization.data(
            withJSONObject: seed,
            options: [.prettyPrinted, .sortedKeys]
        )
        try seedData.write(to: settingsURL)

        // First merge (loaded from disk via JSONSerialization).
        let raw1 = try Data(contentsOf: settingsURL)
        let parsed1 = try JSONSerialization.jsonObject(with: raw1) as! [String: Any]
        let merge1 = SetupCommand.mergePermissions(
            into: parsed1,
            adding: SetupCommand.iostestingPermissions
        )
        #expect(merge1.added.count == SetupCommand.iostestingPermissions.count)

        let out1 = try JSONSerialization.data(
            withJSONObject: merge1.root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try out1.write(to: settingsURL, options: .atomic)

        // Second merge against the just-written file: nothing should change.
        let raw2 = try Data(contentsOf: settingsURL)
        let parsed2 = try JSONSerialization.jsonObject(with: raw2) as! [String: Any]
        let merge2 = SetupCommand.mergePermissions(
            into: parsed2,
            adding: SetupCommand.iostestingPermissions
        )
        #expect(merge2.added.isEmpty, "second pass against persisted file must be a no-op")
        #expect(parsed2["effortLevel"] as? String == "medium", "hand-edited top-level keys survive a write round-trip")
    }
}
