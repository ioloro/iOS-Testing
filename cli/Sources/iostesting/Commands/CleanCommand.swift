import ArgumentParser
import Foundation

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Clean test/build artifacts. By default removes Xcode DerivedData; flags target other surfaces."
    )

    @Flag(name: .long, help: "Remove Xcode DerivedData (~/Library/Developer/Xcode/DerivedData). Default behavior.") var derivedData: Bool = false
    @Flag(name: .long, help: "Remove the iostesting app registry at ~/Library/Application Support/iostesting/.") var registry: Bool = false
    @Flag(name: .long, help: "Remove the project config at ./.iostesting/.") var projectConfig: Bool = false
    @Flag(name: .long, help: "Remove everything iostesting and Xcode-related (DerivedData + registry + project config).") var all: Bool = false
    @Flag(name: .long, help: "Print what would be removed without removing.") var dryRun: Bool = false
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.clean); return }
        // If no flag specified, default to --derived-data.
        let cleanDerived = derivedData || all || (!registry && !projectConfig && !all)
        let cleanRegistry = registry || all
        let cleanProject = projectConfig || all

        var targets: [(label: String, url: URL)] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        if cleanDerived {
            targets.append(("DerivedData", home.appendingPathComponent("Library/Developer/Xcode/DerivedData")))
        }
        if cleanRegistry {
            targets.append(("iostesting registry", AppRegistry.registryURL.deletingLastPathComponent()))
        }
        if cleanProject {
            if let url = ConfigStore.locateProjectFile() {
                targets.append(("project config", url.deletingLastPathComponent()))
            }
        }

        var removed: [String] = []
        var skipped: [String] = []
        let fm = FileManager.default
        for (label, url) in targets {
            if !fm.fileExists(atPath: url.path) {
                skipped.append("\(label): not present (\(url.path))")
                continue
            }
            if dryRun {
                skipped.append("\(label): \(url.path) [would remove, --dry-run]")
                continue
            }
            do {
                try fm.removeItem(at: url)
                removed.append("\(label): \(url.path)")
            } catch {
                skipped.append("\(label): failed to remove (\(error.localizedDescription))")
            }
        }

        if json {
            struct R: Encodable { let removed: [String]; let skipped: [String]; let dryRun: Bool }
            try JSONOutput.emit(R(removed: removed, skipped: skipped, dryRun: dryRun))
            return
        }
        for line in removed { print("removed: \(line)") }
        for line in skipped { print("skipped: \(line)") }
        if removed.isEmpty && skipped.isEmpty {
            print("Nothing to clean.")
        }
    }
}
