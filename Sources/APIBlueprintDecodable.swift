//import Foundation
//
//protocol APIBlueprintElementDecodable: Decodable {
//    static var elementName: String { get }
//}
//extension APIBlueprintElementDecodable {
//    static func decodeElement(_ e: Extractor, key: String = "content") throws -> Self {
//        guard let decoded = try decodeElementOptional(e, key: key) else {
//            throw DecodeError.custom("no decodable content for \(self)")
//        }
//        return decoded
//    }
//
//    static func decodeElementOptional(_ e: Extractor, key: String = "content") throws -> Self? {
//        let arrayOrDict = (e.rawValue as? [String: Any])?[key]
//        guard let contentsJson = (arrayOrDict as? [[String: Any]]) ?? ([arrayOrDict] as? [[String: Any]]),
//            let j = (contentsJson.first {$0["element"] as? String == elementName}) else {
//                return nil
//        }
//        return try decodeValue(j)
//    }
//
//    // filter matched elements and decode from hetero array
//    static func decodeElements(_ e: Extractor, key: String = "content") throws -> [Self] {
//        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]] else {
//            throw DecodeError.custom("no decodable content for \(self)")
//        }
//        return try contentsJson.filter {$0["element"] as? String == elementName}.map(decodeValue)
//    }
//
//    static func decodeElementsOfContents(_ e: Extractor, key: String = "content", subKey: String = "content") throws -> [Self] {
//        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]],
//            let subContentsJson = (contentsJson.first?[subKey] as? [[String: Any]]) else {
//                throw DecodeError.custom("no decodable content for \(self)")
//        }
//
//        return try subContentsJson.filter {$0["element"] as? String == elementName}.map(decodeValue)
//    }
//}
//
//protocol APIBlueprintCategory: Decodable {
//    static var className: String { get }
//}
//extension APIBlueprintCategory {
//    init(from decoder: Decoder) throws {
//        let parsed = Element<T>
//    }
//
//    static func decodeElement(_ e: Extractor, key: String = "content") throws -> Self {
//        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]],
//            let j = (contentsJson.first {
//                $0["element"] as? String == "category" &&
//                    (($0["meta"] as? [String: Any])?["classes"] as? [String])?.contains(className) == true}) else {
//                        throw DecodeError.custom("no decodable content for \(self)")
//        }
//        return try decodeValue(j)
//    }
//
//    // filter matched elements and decode from hetero array
//    static func decodeElements(_ e: Extractor, key: String = "content") throws -> [Self] {
//        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]] else {
//            throw DecodeError.custom("no decodable content for \(self)")
//        }
//        let js = contentsJson.filter {
//            $0["element"] as? String == "category" &&
//                (($0["meta"] as? [String: Any])?["classes"] as? [String])?.contains(className) == true
//        }
//        return try js.map(decodeValue)
//    }
//}
