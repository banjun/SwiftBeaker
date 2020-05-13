import ArgumentParser
import Foundation

struct SwiftBeaker: ParsableCommand {
    @Argument(help: "json file")
    var file: String?
//    var file: String

    @Flag(help: "generate public memberwise init")
    var `public`: Bool

    func run() throws {
        let x = hoge()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        print(String(data: try! encoder.encode(x), encoding: .utf8)!)

//        try Core.main(file: (file as NSString).expandingTildeInPath, public: `public`)
    }
}

SwiftBeaker.main()
