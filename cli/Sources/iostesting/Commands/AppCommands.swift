import ArgumentParser
import Foundation

struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install", abstract: "Install a .app onto a simulator.")
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
    @Argument(help: "Path to .app bundle.") var appPath: String = ""
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.install); return }
        if appPath.isEmpty { IOSTesting.fail("Missing required argument: <app-path>.") }
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
        let url = URL(fileURLWithPath: appPath)
        try await backend.install(udid: resolved.udid, appPath: url)
        if json {
            try JSONOutput.emit(InstallOutput(udid: resolved.udid, installed: appPath))
        } else {
            print("Installed \(url.lastPathComponent) on \(resolved.name)")
        }
    }
}

struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "uninstall", abstract: "Uninstall an app from a simulator.")
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
    @Argument(help: "Bundle identifier. Falls back to `iostesting config` if omitted.") var bundleId: String?
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.uninstall); return }
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
        let bid = try ConfigResolve.bundleId(explicit: bundleId)
        try await backend.uninstall(udid: resolved.udid, bundleId: bid)
        if json {
            try JSONOutput.emit(UninstallOutput(udid: resolved.udid, uninstalled: bid))
        } else {
            print("Uninstalled \(bid) from \(resolved.name)")
        }
    }
}

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "launch", abstract: "Launch an installed app on a simulator.")
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
    @Argument(help: "Bundle identifier. Falls back to `iostesting config` if omitted.") var bundleId: String?
    @Option(name: .long, parsing: .upToNextOption, help: "Environment variables (KEY=VALUE), forwarded as SIMCTL_CHILD_*. Repeatable.") var env: [String] = []
    @Option(name: .customLong("arg"), parsing: .upToNextOption, help: "Launch arguments forwarded to the app. Repeatable.") var arguments: [String] = []
    @Flag(name: .long, help: "Suspend on launch and wait for a debugger to attach.") var waitForDebugger: Bool = false
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.launch); return }
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
        let bid = try ConfigResolve.bundleId(explicit: bundleId)
        var envDict: [String: String] = [:]
        for entry in env {
            guard let eq = entry.firstIndex(of: "=") else {
                IOSTesting.fail("--env entries must be KEY=VALUE; got '\(entry)'")
            }
            envDict[String(entry[..<eq])] = String(entry[entry.index(after: eq)...])
        }
        let result = try await backend.launch(
            udid: resolved.udid,
            bundleId: bid,
            env: envDict,
            args: arguments,
            waitForDebugger: waitForDebugger
        )
        let record = try? AppRegistry.record(
            bundleId: bid,
            simUDID: resolved.udid,
            simName: resolved.name,
            pid: result.pid
        )
        if json {
            struct LaunchJSON: Encodable {
                let pid: Int32
                let bundleId: String
                let shortId: String?
            }
            try JSONOutput.emit(LaunchJSON(pid: result.pid, bundleId: bid, shortId: record?.shortId))
        } else {
            let idSuffix = record.map { " [id \($0.shortId)]" } ?? ""
            print("Launched \(bid) on \(resolved.name) (pid \(result.pid))\(idSuffix)")
        }
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Terminate a running app on a simulator. Accepts a short ID from `iostesting apps`, a bundle id, or a PID."
    )
    @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` or the short-id's sim if omitted.") var sim: String?
    @Argument(help: "Short ID (from `iostesting apps`), bundle identifier, or PID. Falls back to bundle id from `iostesting config` if omitted.") var target: String?
    @Flag(name: .long) var json: Bool = false
    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.stop); return }
        // 1) Short-ID resolution wins: look up registry, use its sim + bundle/pid.
        if let raw = target, let record = try? AppRegistry.find(byShortId: raw) {
            try await backend.terminate(udid: record.simUDID, bundleIdOrPID: record.bundleId)
            try? AppRegistry.markTerminated { $0.shortId == record.shortId }
            if json {
                try JSONOutput.emit(StopOutput(udid: record.simUDID, stopped: record.bundleId))
            } else {
                print("Stopped \(record.bundleId) on \(record.simName) [id \(record.shortId)]")
            }
            return
        }
        // 2) Bundle-id or PID resolution: need explicit sim or config.
        let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
        let resolvedTarget = try ConfigResolve.bundleId(explicit: target)
        try await backend.terminate(udid: resolved.udid, bundleIdOrPID: resolvedTarget)
        try? AppRegistry.markTerminated { $0.simUDID == resolved.udid && ($0.bundleId == resolvedTarget || String($0.pid) == resolvedTarget) }
        if json {
            try JSONOutput.emit(StopOutput(udid: resolved.udid, stopped: resolvedTarget))
        } else {
            print("Stopped \(resolvedTarget) on \(resolved.name)")
        }
    }
}
