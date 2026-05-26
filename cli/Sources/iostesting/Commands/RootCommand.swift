import ArgumentParser
import Foundation

@main
struct IOSTesting: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "iostesting",
        abstract: "Drive iOS simulators and run XCTest bundles for the @ioloro/ios-testing skill.",
        version: "2.2.0",
        subcommands: [
            ConfigCommand.self,
            Context.self,
            Sim.self,
            Install.self,
            Uninstall.self,
            Launch.self,
            Stop.self,
            Logs.self,
            Screenshot.self,
            Apps.self,
            Device.self,
            Test.self,
            UI.self,
            Privacy.self,
            Alerts.self,
            Clean.self,
            Licenses.self,
            SetupCommand.self
        ]
    )
}

let backend: any Backend = {
    // IOSTESTING_BACKEND=fb opts into the FBBackend (v2.0). Any method not yet
    // implemented in FBBackend falls through to SimctlBackend via HybridBackend.
    // Default: pure SimctlBackend.
    let mode = ProcessInfo.processInfo.environment["IOSTESTING_BACKEND"]?.lowercased() ?? "simctl"
    switch mode {
    case "fb", "framework", "hybrid":
        return HybridBackend(primary: FBBackend(), fallback: SimctlBackend())
    default:
        return SimctlBackend()
    }
}()

extension IOSTesting {
    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        Foundation.exit(1)
    }
}
