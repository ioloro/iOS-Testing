import ArgumentParser
import Foundation

struct Licenses: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "licenses", abstract: "Print third-party license notices.")

    @Flag(name: .long, help: "Print usage examples and exit.") var examples: Bool = false

    func run() async throws {
        if examples { print(Examples.licenses); return }
        print(ThirdPartyLicensesText.content)
    }
}
