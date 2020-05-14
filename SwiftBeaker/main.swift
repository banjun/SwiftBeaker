import ArgumentParser
import Foundation
import SwiftBeakerCore

struct SwiftBeaker: ParsableCommand {
    @Argument(help: "json file")
    var file: String

    @Flag(help: "generate public memberwise init")
    var `public`: Bool

    func run() throws {
        try Core.main(file: (file as NSString).expandingTildeInPath, public: `public`)
    }
}

SwiftBeaker.main()
