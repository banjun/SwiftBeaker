import Foundation
import Himotoki
import Stencil

struct Core {
    static func main(file: String, public: Bool) throws {
        let j = try JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: file)), options: [])
        let ast = try APIBlueprintAST.decodeValue(j)
        let resources = ast.api.resourceGroup.flatMap {$0.resources}
        let transitionsSwift = try resources.flatMap { r in
            try r.transitions.map {try $0.swift(r, public: `public`)}
        }
        let dataStructuresSwift = try ast.api.dataStructures.map {try $0.swift(public: `public`)}

        print(preamble)
        print("\n// MARK: - Transitions\n")
        transitionsSwift.forEach {print($0.local + "\n")}
        print("\n// MARK: - Data Structures\n")
        dataStructuresSwift.forEach {print($0.local + "\n")}
        let extensions = [transitionsSwift,
                          dataStructuresSwift].joined().map {$0.global}
            .reduce("") { (r: String, s: String) -> String in
                guard !r.hasSuffix("\n") || !s.isEmpty else { return r }
                return r + "\n" + s
        }
        if !extensions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("\n// MARK: - Extensions\n")
            print(extensions)
        }
    }
}

enum ConversionError: Error {
    case undefined
    case unknownDataStructure
    case notSupported(String)
}
extension ConversionError: CustomStringConvertible {
    var description: String {
        switch self {
        case .undefined: return "ConversionError.undefined"
        case .unknownDataStructure: return "ConversionError.unknownDataStructure"
        case let .notSupported(s): return "ConversionError.notSupported(\(s))"
        }
    }
}
