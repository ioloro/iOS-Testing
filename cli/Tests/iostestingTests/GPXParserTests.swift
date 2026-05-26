import Testing
import Foundation
@testable import iostesting

@Suite("GPXParser")
struct GPXParserTests {
    @Test("Standard trkpt elements parse in document order")
    func standardTrkpts() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
        <trk><trkseg>
        <trkpt lat="40.1704968" lon="-105.1259256"><time>2026-04-24T14:22:23.000Z</time></trkpt>
        <trkpt lat="40.1704964" lon="-105.1258001"></trkpt>
        <trkpt lat="40.1704939" lon="-105.1256790"/>
        </trkseg></trk>
        </gpx>
        """
        let pts = GPXParser.parseString(gpx)
        #expect(pts.count == 3)
        #expect(pts[0].latitude == 40.1704968)
        #expect(pts[0].longitude == -105.1259256)
        #expect(pts[2].latitude == 40.1704939)
        #expect(pts[2].longitude == -105.1256790)
    }

    @Test("lon-before-lat attribute order also parses")
    func lonFirstOrder() {
        let gpx = #"<trkpt lon="-105.0" lat="40.0"></trkpt>"#
        let pts = GPXParser.parseString(gpx)
        #expect(pts.count == 1)
        #expect(pts[0].latitude == 40.0)
        #expect(pts[0].longitude == -105.0)
    }

    @Test("Single-quote attributes parse")
    func singleQuotes() {
        let gpx = "<trkpt lat='40.5' lon='-105.5'/>"
        let pts = GPXParser.parseString(gpx)
        #expect(pts.count == 1)
        #expect(pts[0].latitude == 40.5)
        #expect(pts[0].longitude == -105.5)
    }

    @Test("Malformed trkpts are skipped, not fatal")
    func malformedSkipped() {
        let gpx = """
        <trkpt lat="40.0" lon="garbage"/>
        <trkpt lat="41.0" lon="-105.0"/>
        <trkpt/>
        """
        let pts = GPXParser.parseString(gpx)
        #expect(pts.count == 1)
        #expect(pts[0].latitude == 41.0)
    }

    @Test("Empty input yields zero waypoints")
    func emptyInput() {
        #expect(GPXParser.parseString("").isEmpty)
    }
}
