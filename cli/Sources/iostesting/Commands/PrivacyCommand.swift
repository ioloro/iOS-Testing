import ArgumentParser
import Foundation

/// `iostesting privacy` — wraps `simctl privacy` with safer sequencing and a
/// convenience for the location-always upgrade prompt.
///
/// Background: on iOS 26 the "Allow X to ALSO use your location even when you
/// are not using the app?" upgrade prompt is fired by SpringBoard (not the host
/// app) the second time CLLocationManager transitions from `whenInUse` to
/// `always`. XCUITest's `addUIInterruptionMonitor` is scoped to the app under
/// test and does NOT catch this SpringBoard-owned modal reliably. The cleanest
/// pre-emptive fix is to grant `location-always` BEFORE the runner launches:
/// locationd's `clients.plist` then carries `Authorization=4` and
/// `AuthorizationUpgradeAvailable=false`, suppressing the prompt entirely.
///
/// The grant must happen AFTER the app is installed (so locationd has the
/// bundle path); this command surfaces that requirement and verifies the app
/// is present before granting.
struct Privacy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "privacy",
        abstract: "Grant, revoke, or reset privacy/permissions on a simulator (wraps `simctl privacy`).",
        subcommands: [Grant.self, Revoke.self, Reset.self]
    )
}

extension Privacy {
    /// Service keys exactly as `simctl privacy` accepts them. We document them
    /// here so callers don't need to dig through `simctl privacy --help`.
    static let knownServices: [String] = [
        "all",
        "calendar",
        "contacts",
        "contacts-limited",
        "location",
        "location-always",
        "photos",
        "photos-add",
        "media-library",
        "microphone",
        "motion",
        "reminders",
        "siri"
    ]

    struct Grant: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "grant",
            abstract: "Grant a privacy service without prompting. Use --all-location to grant both `location` and `location-always`."
        )
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Service to grant. One of: \(Privacy.knownServices.joined(separator: ", ")). Required unless --all-location is set.") var service: String?
        @Argument(help: "Bundle identifier. Falls back to `iostesting config` if omitted.") var bundleId: String?
        @Flag(name: .long, help: "Grant both `location` AND `location-always`. Preempts the iOS 26 'also use location' upgrade prompt that XCUITest's addUIInterruptionMonitor cannot catch.") var allLocation: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false
        @Flag(name: .long) var json: Bool = false

        func run() async throws {
            if examples { print(Examples.privacyGrant); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            // Argument-parser quirk: when the user runs
            //   `iostesting privacy grant --all-location com.example.MyApp`
            // the single positional lands in `service`, not `bundleId`. Shift
            // it over when --all-location is set and looks like a bundle id.
            var resolvedService = service
            var resolvedBundleArg = bundleId
            if allLocation, resolvedBundleArg == nil, let s = resolvedService, s.contains(".") {
                resolvedBundleArg = s
                resolvedService = nil
            }
            let bid = try ConfigResolve.bundleId(explicit: resolvedBundleArg)
            var granted: [String] = []
            if allLocation {
                // Sequence matters: simctl writes locationd's `Authorization`
                // field on each grant. `location` (3 = whenInUse) sets up the
                // base record; `location-always` (4) then flips Authorization
                // to 4 AND sets AuthorizationUpgradeAvailable=false, which is
                // the flag that suppresses the SpringBoard upgrade prompt.
                _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", resolved.udid, "grant", "location", bid])
                granted.append("location")
                _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", resolved.udid, "grant", "location-always", bid])
                granted.append("location-always")
            } else {
                guard let svc = resolvedService, !svc.isEmpty else {
                    IOSTesting.fail("Pass a service (e.g. `location-always`) or --all-location.")
                }
                if !Privacy.knownServices.contains(svc) {
                    FileHandle.standardError.write(Data("warning: '\(svc)' is not in iostesting's known service list (\(Privacy.knownServices.joined(separator: ", "))). Passing through to simctl anyway.\n".utf8))
                }
                _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", resolved.udid, "grant", svc, bid])
                granted.append(svc)
            }
            if json {
                struct R: Encodable { let udid: String; let bundleId: String; let granted: [String] }
                try JSONOutput.emit(R(udid: resolved.udid, bundleId: bid, granted: granted))
            } else {
                print("Granted \(granted.joined(separator: " + ")) to \(bid) on \(resolved.name)")
                if granted.contains("location-always") {
                    print("  → locationd.Authorization=4, AuthorizationUpgradeAvailable=false. The iOS 26 'also use location' prompt should no longer fire for this app.")
                }
            }
        }
    }

    struct Revoke: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "revoke", abstract: "Revoke a privacy service.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Service to revoke.") var service: String
        @Argument(help: "Bundle identifier. Falls back to `iostesting config` if omitted.") var bundleId: String?
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false
        @Flag(name: .long) var json: Bool = false

        func run() async throws {
            if examples { print(Examples.privacyRevoke); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            let bid = try ConfigResolve.bundleId(explicit: bundleId)
            _ = try await Shell.runChecked("/usr/bin/xcrun", ["simctl", "privacy", resolved.udid, "revoke", service, bid])
            if json {
                struct R: Encodable { let udid: String; let bundleId: String; let revoked: String }
                try JSONOutput.emit(R(udid: resolved.udid, bundleId: bid, revoked: service))
            } else {
                print("Revoked \(service) from \(bid) on \(resolved.name)")
            }
        }
    }

    struct Reset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "reset", abstract: "Reset a privacy service (next request will prompt). `service all` clears every cached grant.")
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Argument(help: "Service to reset (`all` clears every grant).") var service: String = "all"
        @Argument(help: "Bundle identifier. Omit to reset for every app.") var bundleId: String?
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false
        @Flag(name: .long) var json: Bool = false

        func run() async throws {
            if examples { print(Examples.privacyReset); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            var args = ["simctl", "privacy", resolved.udid, "reset", service]
            // bundle id is optional for reset (simctl supports device-wide reset).
            let resolvedBid: String?
            if let explicit = bundleId, !explicit.isEmpty {
                resolvedBid = explicit
            } else {
                resolvedBid = try? ConfigResolve.bundleId(explicit: nil)
            }
            if let bid = resolvedBid, !bid.isEmpty {
                args.append(bid)
            }
            _ = try await Shell.runChecked("/usr/bin/xcrun", args)
            if json {
                struct R: Encodable { let udid: String; let bundleId: String?; let reset: String }
                try JSONOutput.emit(R(udid: resolved.udid, bundleId: resolvedBid, reset: service))
            } else {
                let scope = resolvedBid.map { "for \($0)" } ?? "device-wide"
                print("Reset \(service) \(scope) on \(resolved.name)")
            }
        }
    }
}
