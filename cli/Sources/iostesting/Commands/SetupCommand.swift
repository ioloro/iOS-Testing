import ArgumentParser
import Foundation

/// `iostesting setup` — merge the curated iostesting permission allowlist into
/// ~/.claude/settings.json. Claude Code plugins cannot ship permission allowlists
/// via their manifest (only `agent` and `subagentStatusLine` keys are supported),
/// so each fresh install of @ioloro/ios-testing otherwise produces permission
/// prompts for `xcrun simctl spawn`, `xcodebuild build-for-testing`, etc. This
/// command performs that one-time merge.
struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install iostesting Claude Code permissions into ~/.claude/settings.json. Idempotent."
    )

    @Flag(name: .long, help: "Show the diff without writing.") var dryRun: Bool = false
    @Flag(name: .long, help: "Print the merged settings file to stdout and exit (no write).") var print: Bool = false
    @Option(name: .long, help: "Override settings file location (for testing).") var path: String?
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    /// The curated set of Bash patterns iostesting + its companion skill needs.
    /// All are read-only or local-side-effect-only (DerivedData, .build/, the
    /// user's own keychain). No MCP entries — those belong to other plugins.
    /// No full-path forms — those are machine-specific.
    static let iostestingPermissions: [String] = [
        "Bash(xcrun simctl spawn:*)",
        "Bash(xcrun simctl location:*)",
        "Bash(xcrun simctl list:*)",
        "Bash(xcrun simctl privacy:*)",
        "Bash(xcrun simctl io:*)",
        "Bash(swift build:*)",
        "Bash(xcodebuild build-for-testing:*)",
        "Bash(iostesting:*)",
        "Bash(log show:*)",
        "Bash(find-generic-password:*)"
    ]

    func run() async throws {
        if examples { Swift.print(Examples.setup); return }

        let settingsURL = resolveSettingsURL()
        let fm = FileManager.default

        // Parse existing settings (or start fresh).
        var root: [String: Any]
        if fm.fileExists(atPath: settingsURL.path) {
            let data: Data
            do {
                data = try Data(contentsOf: settingsURL)
            } catch {
                IOSTesting.fail("Failed to read \(settingsURL.path): \(error.localizedDescription)")
            }
            if data.isEmpty {
                root = [:]
            } else {
                do {
                    let parsed = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let dict = parsed as? [String: Any] else {
                        IOSTesting.fail("\(settingsURL.path) is not a JSON object at the root.")
                    }
                    root = dict
                } catch {
                    IOSTesting.fail("Failed to parse \(settingsURL.path): \(error.localizedDescription)")
                }
            }
        } else {
            root = [:]
        }

        // Compute merge under permissions.allow, preserving unknown keys.
        let merge = SetupCommand.mergePermissions(
            into: root,
            adding: SetupCommand.iostestingPermissions
        )
        let added = merge.added
        let alreadyPresent = merge.alreadyPresent
        root = merge.root

        // Serialize (sorted keys, pretty-printed) for a stable, diffable file.
        // The existing file may have been hand-formatted; this rewrites it in
        // canonical form on first run, which is acceptable for a config file.
        let outData: Data
        do {
            outData = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            IOSTesting.fail("Failed to serialize merged settings: \(error.localizedDescription)")
        }

        if self.print {
            if let s = String(data: outData, encoding: .utf8) {
                Swift.print(s)
            }
            return
        }

        if json {
            struct R: Encodable {
                let path: String
                let added: [String]
                let alreadyPresent: [String]
                let dryRun: Bool
                let wrote: Bool
            }
            let payload = R(
                path: settingsURL.path,
                added: added,
                alreadyPresent: alreadyPresent,
                dryRun: dryRun,
                wrote: !dryRun && !added.isEmpty
            )
            try JSONOutput.emit(payload)
            return
        }

        // Human-readable diff.
        Swift.print("Permissions \(dryRun ? "preview" : "updated") at \(settingsURL.path):")
        if added.isEmpty {
            Swift.print("  (no changes. All \(SetupCommand.iostestingPermissions.count) iostesting entries already present.)")
        } else {
            for entry in added { Swift.print("  + \(entry)") }
            if !alreadyPresent.isEmpty {
                Swift.print("  (\(alreadyPresent.count) entr\(alreadyPresent.count == 1 ? "y" : "ies") already present, no changes to those)")
            }
        }

        // Write if not dry-run and there are changes (or the file didn't exist
        // and needs to be created with the new entries).
        if !dryRun {
            if !added.isEmpty || !fm.fileExists(atPath: settingsURL.path) {
                do {
                    try fm.createDirectory(
                        at: settingsURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try outData.write(to: settingsURL, options: .atomic)
                } catch {
                    IOSTesting.fail("Failed to write \(settingsURL.path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func resolveSettingsURL() -> URL {
        if let p = path, !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/settings.json")
    }

    /// Pure merge helper. Given a parsed settings root and a list of entries to
    /// install, returns a new root plus the diff. Preserves unknown top-level
    /// keys, preserves unknown keys inside `permissions`, and never reorders
    /// pre-existing `allow` entries.
    static func mergePermissions(
        into root: [String: Any],
        adding entries: [String]
    ) -> (root: [String: Any], added: [String], alreadyPresent: [String]) {
        var root = root
        var permissions = (root["permissions"] as? [String: Any]) ?? [:]
        let existingAllow = (permissions["allow"] as? [String]) ?? []
        let existingSet = Set(existingAllow)

        var added: [String] = []
        var mergedAllow = existingAllow
        for entry in entries where !existingSet.contains(entry) {
            mergedAllow.append(entry)
            added.append(entry)
        }
        let alreadyPresent = entries.filter { existingSet.contains($0) }

        permissions["allow"] = mergedAllow
        root["permissions"] = permissions
        return (root, added, alreadyPresent)
    }
}
