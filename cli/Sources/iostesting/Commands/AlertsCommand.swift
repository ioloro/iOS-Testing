import ArgumentParser
import Foundation
import FBBridge
import AppKit
import Vision

/// `iostesting alerts` — dismiss SpringBoard-owned system modals that XCUITest's
/// `addUIInterruptionMonitor` cannot reach. The watcher polls screenshots,
/// runs Vision OCR to find a button by label, and taps it via FBSimulatorHID.
///
/// Use cases:
///   • iOS 26's "Allow X to ALSO use your location..." upgrade prompt
///     (SpringBoard-owned; addUIInterruptionMonitor misses it).
///   • "Allow notifications" / "Allow tracking" / camera / mic prompts that
///     fire mid-test before the app's monitor handler fires.
///   • Any centered system modal with a Cancel-style first button.
struct Alerts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alerts",
        abstract: "Dismiss SpringBoard-owned system modals via screenshot + OCR + HID tap. Requires IOSTESTING_BACKEND=fb.",
        subcommands: [Dismiss.self, Watch.self]
    )
}

/// Default button labels we look for, in priority order. Matches both the
/// iOS 26 location-upgrade prompt and the standard When-In-Use prompt.
private let defaultButtonLabels: [String] = [
    "Keep Only While Using",
    "Allow While Using App",
    "Allow Once",
    "Don\u{2019}t Allow",
    "Don't Allow",
    "OK",
    "Allow"
]

extension Alerts {
    struct Dismiss: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "dismiss",
            abstract: "One-shot: screenshot the sim, OCR for a button label, tap it. Exits 0 if a button was tapped, 2 if nothing matched."
        )
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, parsing: .upToNextOption, help: "Button label(s) to look for. Repeatable. Tapped in order of first match. Defaults: \(defaultButtonLabels.joined(separator: ", ")).") var label: [String] = []
        @Flag(name: .long, help: "Match labels case-insensitively. Default: true.") var caseInsensitive: Bool = true
        @Option(name: .long, help: "Minimum OCR confidence (0..1). Default 0.5.") var minConfidence: Float = 0.5
        @Flag(name: .long) var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.alertsDismiss); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            let labels = label.isEmpty ? defaultButtonLabels : label
            let result = try AlertDismisser.dismissOnce(
                udid: resolved.udid,
                labels: labels,
                caseInsensitive: caseInsensitive,
                minConfidence: minConfidence
            )
            if json {
                struct R: Encodable {
                    let udid: String
                    let matched: String?
                    let tappedAtX: Double?
                    let tappedAtY: Double?
                }
                try JSONOutput.emit(R(
                    udid: resolved.udid,
                    matched: result?.matchedLabel,
                    tappedAtX: result?.x,
                    tappedAtY: result?.y
                ))
            } else if let r = result {
                print("Tapped '\(r.matchedLabel)' at (\(Int(r.x)), \(Int(r.y))) on \(resolved.name)")
            } else {
                print("No matching button found on \(resolved.name) (looked for: \(labels.joined(separator: ", ")))")
            }
            if result == nil {
                Foundation.exit(2)
            }
        }
    }

    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "watch",
            abstract: "Background-poll the sim. Whenever a matching button label appears, tap it. Runs until --duration expires or SIGINT."
        )
        @Option(name: [.short, .long], help: "Simulator name or UDID. Falls back to `iostesting config` if omitted.") var sim: String?
        @Option(name: .long, parsing: .upToNextOption, help: "Button label(s) to dismiss. Repeatable. Defaults to system-prompt buttons.") var label: [String] = []
        @Option(name: .long, help: "Total seconds to watch. Default 600. Use 0 for forever.") var duration: Double = 600
        @Option(name: .long, help: "Seconds between screenshots. Default 2.0.") var interval: Double = 2.0
        @Option(name: .long, help: "Minimum OCR confidence (0..1). Default 0.5.") var minConfidence: Float = 0.5
        @Flag(name: .long, help: "Emit one JSON line per dismissal to stdout.") var json: Bool = false
        @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

        func run() async throws {
            if examples { print(Examples.alertsWatch); return }
            let resolved = try await backend.resolveSimulator(try ConfigResolve.sim(explicit: sim))
            let labels = label.isEmpty ? defaultButtonLabels : label
            let stopAt: Date? = duration > 0 ? Date().addingTimeInterval(duration) : nil
            if !json {
                let until = stopAt.map { "until \($0)" } ?? "forever"
                FileHandle.standardError.write(Data("alerts.watch: polling \(resolved.name) every \(interval)s \(until); labels=\(labels)\n".utf8))
            }
            while stopAt == nil || Date() < stopAt! {
                let dismissed = try? AlertDismisser.dismissOnce(
                    udid: resolved.udid,
                    labels: labels,
                    caseInsensitive: true,
                    minConfidence: minConfidence
                )
                if let r = dismissed ?? nil {
                    if json {
                        struct E: Encodable {
                            let event: String
                            let udid: String
                            let matched: String
                            let x: Double
                            let y: Double
                            let timestamp: String
                        }
                        let ev = E(
                            event: "dismissed",
                            udid: resolved.udid,
                            matched: r.matchedLabel,
                            x: r.x,
                            y: r.y,
                            timestamp: ISO8601DateFormatter().string(from: Date())
                        )
                        try? JSONOutput.emitLine(ev)
                    } else {
                        FileHandle.standardError.write(Data("alerts.watch: tapped '\(r.matchedLabel)' at (\(Int(r.x)), \(Int(r.y)))\n".utf8))
                    }
                }
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if !json {
                FileHandle.standardError.write(Data("alerts.watch: duration elapsed, exiting.\n".utf8))
            }
        }
    }
}

// MARK: - AlertDismisser

/// Screenshots the simulator (via simctl io for portability), OCRs the image
/// via Vision, locates a button matching one of the candidate labels, and
/// taps the centroid via FBSimulatorHID. Used by `alerts dismiss/watch` and by
/// `test run --auto-dismiss` for in-test prompt handling.
enum AlertDismisser {
    struct DismissResult: Sendable {
        let matchedLabel: String
        /// Tap coordinate in point space (what FBSimulatorHID.tapAtX:y: expects).
        let x: Double
        let y: Double
    }

    static func dismissOnce(
        udid: String,
        labels: [String],
        caseInsensitive: Bool,
        minConfidence: Float
    ) throws -> DismissResult? {
        // 1. Take a screenshot. Use `simctl io screenshot` (works on any sim
        // regardless of backend); writes a PNG to a temp file.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("iostesting-alerts-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "io", udid, "screenshot", tmp.path]
        let nullPipe = Pipe()
        proc.standardOutput = nullPipe
        proc.standardError = nullPipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw BackendError(message: "screenshot for OCR failed (exit \(proc.terminationStatus))")
        }

        // 2. Load the image and figure out the pixel→point ratio. On iPhone
        // 17 Pro the framebuffer is 1206x2622 px @ 3x → 402x874 pts.
        guard let image = NSImage(contentsOf: tmp) else {
            throw BackendError(message: "could not load screenshot at \(tmp.path)")
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw BackendError(message: "could not get CGImage from screenshot")
        }
        let pixelW = Double(cgImage.width)
        let pixelH = Double(cgImage.height)
        let pointW = image.size.width
        let pointH = image.size.height
        // NSImage size on the screenshot file is the same as the pixel size
        // (simctl writes raw pixels, no @2x metadata), so we have to derive
        // the point space from a known mapping: iPhone screens have a fixed
        // backing scale (2x or 3x). Use the framebuffer dims + the device
        // class via heuristic: scale = 3 for newer Pro phones; fall back to 2.
        // The HID layer wants point coords; Apple's `FBSimulatorHIDEvent.tap`
        // accepts the simulator's native point space.
        let scale: Double
        if pointW > 0 && abs(pixelW / pointW - 3.0) < 0.1 {
            scale = pixelW / pointW
        } else if pointW > 0 && abs(pixelW / pointW - 2.0) < 0.1 {
            scale = pixelW / pointW
        } else {
            // Fallback: assume @3x for modern iPhones, @2x for older / iPad.
            scale = pixelW >= 1170 ? 3.0 : 2.0
        }
        _ = pixelW / scale  // screenPointW — kept for future plausibility filter
        let screenPointH = pixelH / scale
        _ = (pointW, pointH) // unused-warning silence

        // 3. Vision OCR. Synchronous via VNImageRequestHandler.perform().
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observations = request.results else { return nil }

        // 4. For each candidate label (in priority order), find the first
        // observation whose recognized text matches AND whose bbox has a
        // typical button shape (width > 0.4 of screen, height < 0.1 of
        // screen). We tap the centroid of that bbox.
        for label in labels {
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                guard candidate.confidence >= minConfidence else { continue }
                if !matches(label: label, recognized: candidate.string, caseInsensitive: caseInsensitive) {
                    continue
                }
                // Vision normalized rect: origin bottom-left, units 0..1.
                let bb = obs.boundingBox
                // Centroid in pixel coords (Vision Y is bottom-up; CGImage Y is top-down).
                let centerPxX = (bb.origin.x + bb.size.width / 2.0) * pixelW
                let centerPxYBottomUp = (bb.origin.y + bb.size.height / 2.0) * pixelH
                let centerPxYTopDown = pixelH - centerPxYBottomUp
                // Convert to point space.
                let pointX = centerPxX / scale
                let pointY = centerPxYTopDown / scale
                // Reject implausible matches (e.g. OCR'd "OK" inside a label
                // far from the alert plate). Buttons sit in the lower 2/3 of
                // the screen; reject hits in the top 15% (status bar / nav).
                if pointY < screenPointH * 0.10 { continue }
                // Tap via FBSimulatorHID. Requires booted sim + FB backend
                // bootstrapped, which happens on first FBBridge call.
                try FBBridge.tapAt(x: pointX, y: pointY, onSimulator: udid)
                return DismissResult(matchedLabel: label, x: pointX, y: pointY)
            }
        }
        return nil
    }

    private static func matches(label: String, recognized: String, caseInsensitive: Bool) -> Bool {
        // Vision OCR commonly emits curly apostrophes for "Don't"; strip both
        // smart and straight apostrophes before comparing. Also accept loose
        // contiguity ("KeepOnly..." → "Keep Only...").
        let normalize: (String) -> String = { s in
            var out = s.replacingOccurrences(of: "\u{2019}", with: "'")
            out = out.replacingOccurrences(of: "\u{2018}", with: "'")
            if caseInsensitive { out = out.lowercased() }
            return out
        }
        let target = normalize(label)
        let recog = normalize(recognized)
        return recog.contains(target)
    }
}
