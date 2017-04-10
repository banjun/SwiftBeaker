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

enum RequestError: Error {
   case encode
}

enum ResponseError: Error {
    case undefined(Int, String?)
    case invalidData(Int, String?)
}

struct RawDataParser: DataParser {
    var contentType: String? {return nil}
    func parse(data: Data) -> Any { return data }
}

struct TextBodyParameters: BodyParameters {
   let contentType: String
   let content: String
   func buildEntity() throws -> RequestBodyEntity {
       guard let r = content.data(using: .utf8) else { throw RequestError.encode }
       return .data(r)
   }
}


// MARK: - Transitions

/// This action has **two** responses defined: One returning plain text and the
/// other a JSON representation of our resource. Both have the same HTTP status
/// code. Also both responses bear additional information in the form of a custom
/// HTTP header. Note that both responses have set the `Content-Type` HTTP header
/// just by specifying `(text/plain)` or `(application/json)` in their respective
/// signatures.
struct Retrieve_a_Message: Request {
    typealias Response = Responses
    let baseURL: URL
    var method: HTTPMethod {return .get}

    var path: String {return "/message"}
    var dataParser: DataParser {return RawDataParser()}

    enum Responses {
        case http200_text_plain(String)
        case http200_application_json(Void)
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
            return .http200_text_plain(try String.decodeValue(object))
        case (200, "application/json"?):
            return .http200_application_json()
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}


struct Update_a_Message: Request {
    typealias Response = Responses
    let baseURL: URL
    var method: HTTPMethod {return .put}

    var path: String {return "/message"}
    var dataParser: DataParser {return RawDataParser()}

    let param: String
    var bodyParameters: BodyParameters? {return TextBodyParameters(contentType: "text/plain", content: param)}
    enum Responses {
        case http204_(Void)
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
        case (204, _):
            return .http204_()
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}


// MARK: - Data Structures


// MARK: - Extensions



