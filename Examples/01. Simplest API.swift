import Foundation
import APIKit
import Himotoki
import URITemplate

protocol JSONBodyParametersConvertible {
    var jsonBodyParametersObject: Any { get }
}
extension JSONBodyParametersConvertible {
    var jsonBodyParameters: JSONBodyParameters {return JSONBodyParameters(JSONObject: jsonBodyParametersObject)}
    var jsonBodyParametersObject: Any {return self} // default implementation
}

extension String: JSONBodyParametersConvertible {}
extension Int: JSONBodyParametersConvertible {}
extension Bool: JSONBodyParametersConvertible {}

protocol DataStructureType: JSONBodyParametersConvertible {}
extension Array where Element: JSONBodyParametersConvertible {
    var jsonBodyParametersObject: Any {return self.map {$0.jsonBodyParametersObject}}
}

protocol URITemplateContextConvertible: JSONBodyParametersConvertible {}
extension URITemplateContextConvertible {
    var context: [String: Any] {return jsonBodyParametersObject as? [String: Any] ?? [:]}
}

enum ResponseError: Error {
    case undefined(Int, String?)
    case invalidData(Int, String?)
}

struct RawDataParser: DataParser {
    var contentType: String? {return nil}
    func parse(data: Data) -> Any { return data }
}


// MARK: - Transitions

/// 
struct GET__message: Request {
    typealias Response = Responses
    let baseURL: URL
    var method: HTTPMethod {return .get}

    var path: String {return "/message"}
    var dataParser: DataParser {return RawDataParser()}

    enum Responses {
        case http200_text_plain(String)
    }


    // conver object (Data) to expected type
    func intercept(object: Any, urlResponse: HTTPURLResponse) throws -> Any {
        let contentType = (urlResponse.allHeaderFields["Content-Type"] as? String)?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
        switch (object, contentType) {
        case let (data as Data, "application/json"?): return try JSONSerialization.jsonObject(with: data, options: [])
        case let (data as Data, "text/plain"?):
            guard let s = String(data: data, encoding: .utf8) else { throw ResponseError.invalidData(urlResponse.statusCode, contentType) }
            return s
        case let (data as Data, "text/html"?):
            guard let s = String(data: data, encoding: .utf8) else { throw ResponseError.invalidData(urlResponse.statusCode, contentType) }
            return s
        case let (data as Data, _): return data
        default: return object
        }
    }

    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Response {
        let contentType = (urlResponse.allHeaderFields["Content-Type"] as? String)?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
        switch (urlResponse.statusCode, contentType) {
        case (200, "text/plain"?):
            return try .http200_text_plain(String.decodeValue(object))
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}


// MARK: - Data Structures


// MARK: - Extensions


