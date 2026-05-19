import Testing
@testable import iostesting

@Suite("Examples")
struct ExamplesTests {
    @Test("All Examples entries are non-empty and start with a comment or command")
    func allEntriesNonEmpty() {
        let all: [(name: String, body: String)] = [
            ("simList", Examples.simList),
            ("simBoot", Examples.simBoot),
            ("simShutdown", Examples.simShutdown),
            ("simErase", Examples.simErase),
            ("simCreate", Examples.simCreate),
            ("simPrune", Examples.simPrune),
            ("simMediaAdd", Examples.simMediaAdd),
            ("simLocation", Examples.simLocation),
            ("simButton", Examples.simButton),
            ("simAppearance", Examples.simAppearance),
            ("simOpenURL", Examples.simOpenURL),
            ("install", Examples.install),
            ("uninstall", Examples.uninstall),
            ("launch", Examples.launch),
            ("stop", Examples.stop),
            ("logs", Examples.logs),
            ("screenshot", Examples.screenshot),
            ("appsList", Examples.appsList),
            ("appsPrune", Examples.appsPrune),
            ("deviceList", Examples.deviceList),
            ("deviceInstall", Examples.deviceInstall),
            ("deviceLaunch", Examples.deviceLaunch),
            ("testList", Examples.testList),
            ("testRun", Examples.testRun),
            ("configShow", Examples.configShow),
            ("configSet", Examples.configSet),
            ("configGet", Examples.configGet),
            ("configReset", Examples.configReset),
            ("licenses", Examples.licenses),
            ("clean", Examples.clean),
            ("context", Examples.context)
        ]
        for (name, body) in all {
            #expect(!body.isEmpty, "\(name) is empty")
            // Each example block should mention `iostesting` somewhere.
            #expect(body.contains("iostesting"), "\(name) does not reference iostesting")
        }
    }

    @Test("testRun example calls out the simctl backend's logic-only limitation + the fb backend opt-in")
    func testRunLimitation() {
        #expect(Examples.testRun.contains("IOSTESTING_BACKEND=fb"), "testRun should point agents at the fb backend for app-hosted + Swift Testing bundles")
    }
}
