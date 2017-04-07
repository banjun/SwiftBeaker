import Foundation
import Himotoki
import Stencil

struct Core {
    static func main(file: String) throws {
        let j = try JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: file)), options: [])
        let ast = try APIBlueprintAST.decodeValue(j)
        let transitions = ast.api.resourceGroup.flatMap {$0.resources}.flatMap {$0.transitions}
        let transitionsSwift = try transitions.map {try $0.swift(transitions)}
        let dataStructuresSwift = try ast.api.dataStructures.map {try $0.swift()}

        print(preamble)
        print("\n// MARK: - Transitions\n")
        transitionsSwift.forEach {print($0.local)}
        print("\n// MARK: - Data Structures\n")
        dataStructuresSwift.forEach {print($0.local)}
        print("\n// MARK: - Extensions\n")
        [transitionsSwift,
         dataStructuresSwift].joined().forEach {print($0.global)}
    }
}

enum ConversionError: Error {
    case undefined
    case unknownDataStructure
    case notSupported(String)
}
