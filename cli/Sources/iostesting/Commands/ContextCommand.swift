import ArgumentParser
import Foundation

struct Context: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "context",
        abstract: "Discover schemes, configs, and targets for an Xcode project or workspace in the current directory."
    )

    @Option(name: [.short, .long], help: "Project or workspace path (.xcodeproj / .xcworkspace). Auto-detected if omitted.") var project: String?
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.context); return }
        let target = try locateProject(explicit: project)
        let info = try await dumpProject(target: target)
        if json {
            try JSONOutput.emit(info)
            return
        }
        print("Project: \(info.path)")
        if !info.workspace.isEmpty { print("Workspace: \(info.workspace)") }
        print("")
        print("Targets:")
        for t in info.targets { print("  \(t)") }
        print("")
        print("Configurations:")
        for c in info.configurations { print("  \(c)") }
        print("")
        print("Schemes:")
        for s in info.schemes { print("  \(s)") }
    }

    private func locateProject(explicit: String?) throws -> URL {
        if let p = explicit { return URL(fileURLWithPath: p) }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: cwd.path)) ?? []
        if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return cwd.appendingPathComponent(ws)
        }
        if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return cwd.appendingPathComponent(proj)
        }
        IOSTesting.fail("No .xcworkspace or .xcodeproj in \(cwd.path). Pass --project explicitly.")
    }

    private func dumpProject(target: URL) async throws -> ProjectInfo {
        let isWorkspace = target.pathExtension == "xcworkspace"
        var args = ["-list", "-json"]
        if isWorkspace {
            args.append(contentsOf: ["-workspace", target.path])
        } else {
            args.append(contentsOf: ["-project", target.path])
        }
        let output = try await Shell.runChecked("/usr/bin/xcodebuild", args)
        guard let data = output.data(using: .utf8) else {
            throw BackendError(message: "xcodebuild -list returned non-utf8 output")
        }
        // xcodebuild -list -json wraps the payload under "project" for projects
        // and under "workspace" for workspaces.
        struct ProjectEnvelope: Decodable {
            struct Project: Decodable {
                let name: String
                let targets: [String]?
                let configurations: [String]?
                let schemes: [String]?
            }
            let project: Project?
        }
        struct WorkspaceEnvelope: Decodable {
            struct Workspace: Decodable {
                let name: String
                let schemes: [String]?
            }
            let workspace: Workspace?
        }
        if isWorkspace {
            let env = try JSONDecoder().decode(WorkspaceEnvelope.self, from: data)
            return ProjectInfo(
                path: target.path,
                workspace: env.workspace?.name ?? "",
                targets: [],
                configurations: [],
                schemes: env.workspace?.schemes ?? []
            )
        } else {
            let env = try JSONDecoder().decode(ProjectEnvelope.self, from: data)
            return ProjectInfo(
                path: target.path,
                workspace: "",
                targets: env.project?.targets ?? [],
                configurations: env.project?.configurations ?? [],
                schemes: env.project?.schemes ?? []
            )
        }
    }

    struct ProjectInfo: Codable {
        let path: String
        let workspace: String
        let targets: [String]
        let configurations: [String]
        let schemes: [String]
    }
}
