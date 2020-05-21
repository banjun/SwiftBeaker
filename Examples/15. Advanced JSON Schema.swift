import Foundation
import APIKit
import URITemplate

protocol URITemplateContextConvertible: Encodable {}
extension URITemplateContextConvertible {
    var context: [String: String] {
        return ((try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: String]) ?? [:]
    }
}

public enum RequestError: Error {
    case encode
}

public enum ResponseError: Error {
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

public protocol APIBlueprintRequest: Request {}
extension APIBlueprintRequest {
    public var dataParser: DataParser {return RawDataParser()}

    func contentMIMEType(in urlResponse: HTTPURLResponse) -> String? {
        return (urlResponse.allHeaderFields["Content-Type"] as? String)?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces)
    }

    func data(from object: Any, urlResponse: HTTPURLResponse) throws -> Data {
        guard let d = object as? Data else {
            throw ResponseError.invalidData(urlResponse.statusCode, contentMIMEType(in: urlResponse))
        }
        return d
    }

    func string(from object: Any, urlResponse: HTTPURLResponse) throws -> String {
        guard let s = String(data: try data(from: object, urlResponse: urlResponse), encoding: .utf8) else {
            throw ResponseError.invalidData(urlResponse.statusCode, contentMIMEType(in: urlResponse))
        }
        return s
    }

    func decodeJSON<T: Decodable>(from object: Any, urlResponse: HTTPURLResponse) throws -> T {
        return try JSONDecoder().decode(T.self, from: data(from: object, urlResponse: urlResponse))
    }

    public func intercept(object: Any, urlResponse: HTTPURLResponse) throws -> Any {
        return object
    }
}

protocol URITemplateRequest: Request {
    static var pathTemplate: URITemplate { get }
    associatedtype PathVars: URITemplateContextConvertible
    var pathVars: PathVars { get }
}
extension URITemplateRequest {
    // reconstruct URL to use URITemplate.expand. NOTE: APIKit does not support URITemplate format other than `path + query`
    public func intercept(urlRequest: URLRequest) throws -> URLRequest {
        var req = urlRequest
        req.url = URL(string: baseURL.absoluteString + type(of: self).pathTemplate.expand(pathVars.context))!
        return req
    }
}

/// indirect Codable Box-like container for recursive data structure definitions
public class Indirect<V: Codable>: Codable {
    public var value: V

    public init(_ value: V) {
        self.value = value
    }

    public required init(from decoder: Decoder) throws {
        self.value = try V(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

// MARK: - Transitions

/// Gets a single note by its unique identifier.
struct Get_a_note: APIBlueprintRequest {
    let baseURL: URL
    var method: HTTPMethod {return .get}

    var path: String {return "/notes/{id}"}

    enum Responses {
        case http200_application_json(Response200_application_json)
        struct Response200_application_json: Codable { 
            ///  ex. "abc123"
            var id: String?
            ///  ex. "This is a note"
            var title: String?
            ///  ex. "This is the note content."
            var content: String?
            ///  ex. []
            var tags: [String]?
        }
    }

    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Responses {
        let contentType = contentMIMEType(in: urlResponse)
        switch (urlResponse.statusCode, contentType) {
        case (200, "application/json"?):
            return .http200_application_json(try decodeJSON(from: object, urlResponse: urlResponse))
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}

/// Modify a note's data using its unique identifier. You can edit the `title`,
/// `content`, and `tags`.
struct Update_a_note: APIBlueprintRequest {
    let baseURL: URL
    var method: HTTPMethod {return .patch}

    var path: String {return "/notes/{id}"}

    let param: Param
    var bodyParameters: BodyParameters? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? JSONBodyParameters(JSONObject: JSONSerialization.jsonObject(with: encoder.encode(param)))
    }
    struct Param: Codable { 
        ///  ex. "This is another note"
        var title: String?
        /// 
        var content: String?
        ///  ex. []
        var tags: [String]?
    }
    enum Responses {
        case http204_(Void)
    }

    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Responses {
        let contentType = contentMIMEType(in: urlResponse)
        switch (urlResponse.statusCode, contentType) {
        case (204, _):
            return .http204_(try decodeJSON(from: object, urlResponse: urlResponse))
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}


// MARK: - Data Structures

