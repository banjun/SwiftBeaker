import Commander
import Foundation

let main = command { (file: String) in
    try Core.main(file: (file as NSString).expandingTildeInPath)
}

main.run()
