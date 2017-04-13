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

protocol APIBlueprintRequest: Request {}
extension APIBlueprintRequest {
    var dataParser: DataParser {return RawDataParser()}

    func contentMIMEType(in urlResponse: HTTPURLResponse) -> String? {
        return (urlResponse.allHeaderFields["Content-Type"] as? String)?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
    }

    // convert object (Data) to expected type
    func intercept(object: Any, urlResponse: HTTPURLResponse) throws -> Any {
        let contentType = contentMIMEType(in: urlResponse)
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
}

protocol URITemplateRequest: Request {
    static var pathTemplate: URITemplate { get }
    associatedtype PathVars: URITemplateContextConvertible
    var pathVars: PathVars { get }
}
extension URITemplateRequest {
    // reconstruct URL to use URITemplate.expand. NOTE: APIKit does not support URITemplate format other than `path + query`
    func intercept(urlRequest: URLRequest) throws -> URLRequest {
        var req = urlRequest
        req.url = URL(string: baseURL.absoluteString + type(of: self).pathTemplate.expand(pathVars.context))!
        return req
    }
}


// MARK: - Transitions


struct GET__message: APIBlueprintRequest {
    let baseURL: URL
    var method: HTTPMethod {return .get}

    var path: String {return "/message"}

    enum Responses {
        case http200_text_plain(String)
    }

    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Responses {
        let contentType = contentMIMEType(in: urlResponse)
        switch (urlResponse.statusCode, contentType) {
        case (200, "text/plain"?):
            return .http200_text_plain(try String.decodeValue(object))
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}


// MARK: - Data Structures


// MARK: - Extensions


