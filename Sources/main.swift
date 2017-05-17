import Commander
import Foundation

let main = command(
    Argument<String>(""),
    Flag("public")) { (file: String, public: Bool) in
        try Core.main(file: (file as NSString).expandingTildeInPath, public: `public`)
}

main.run()
