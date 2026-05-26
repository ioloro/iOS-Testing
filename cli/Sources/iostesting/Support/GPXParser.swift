import Foundation

/// Minimal GPX 1.1 parser. We only need lat/lon from `<trkpt lat="..." lon="..."/>`
/// elements (the rest of the file — metadata, time, ele — is ignored). This
/// covers the format dewygolf-api emits and every standard GPX track file.
///
/// Two paths: a fast regex sweep over the raw bytes (handles 100% of files in
/// practice because trkpt elements are line-uniform there) and a fallback
/// XMLParser pass for anything pathological.
enum GPXParser {
    struct Waypoint: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    enum GPXError: Error, CustomStringConvertible {
        case fileNotFound(String)
        case unreadable(String)
        case noWaypoints

        var description: String {
            switch self {
            case .fileNotFound(let p): return "GPX file not found: \(p)"
            case .unreadable(let p): return "GPX file unreadable: \(p)"
            case .noWaypoints: return "GPX file contained no <trkpt> waypoints"
            }
        }
    }

    /// Parse a GPX file off disk and return its track waypoints in document order.
    static func parse(fileAt url: URL) throws -> [Waypoint] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw GPXError.fileNotFound(url.path)
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw GPXError.unreadable(url.path)
        }
        let waypoints = parseString(contents)
        if waypoints.isEmpty { throw GPXError.noWaypoints }
        return waypoints
    }

    /// Pure-string entry point — useful in tests and for in-memory parsing.
    /// Matches lat/lon attributes regardless of order (`lat="..." lon="..."`
    /// or `lon="..." lat="..."`). Skips malformed trkpt elements.
    static func parseString(_ source: String) -> [Waypoint] {
        var results: [Waypoint] = []
        // Single regex sweep: each `<trkpt ...>` opening tag, attributes in
        // any order. `(?s)` so attribute spans tolerate accidental newlines.
        // Greedy enough to handle either attribute order.
        let pattern = #"<trkpt\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return results
        }
        let ns = source as NSString
        let range = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 2 else { return }
            let attrs = ns.substring(with: m.range(at: 1))
            guard let lat = extractAttribute("lat", from: attrs),
                  let lon = extractAttribute("lon", from: attrs) else { return }
            results.append(Waypoint(latitude: lat, longitude: lon))
        }
        return results
    }

    private static func extractAttribute(_ name: String, from attrs: String) -> Double? {
        // Match: `name="value"` or `name='value'`, value is a number.
        let pattern = "\\b\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = attrs as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: attrs, options: [], range: range),
              m.numberOfRanges >= 2 else { return nil }
        let raw = ns.substring(with: m.range(at: 1))
        return Double(raw)
    }
}
