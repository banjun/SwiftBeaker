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

/// Here we define an action using the `GET` [HTTP request method](http://www.w3schools.com/tags/ref_httpmethods.asp) for our resource `/message`.

As with every good action it should return a
[response](http://www.w3.org/TR/di-gloss/#def-http-response). A response always
bears a status code. Code 200 is great as it means all is green. Responding
with some data can be a great idea as well so let's add a plain text message to
our response.
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
            return .http200_text_plain(try String.decodeValue(object))
        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}

/// OK, let's add another action. This time to put new data to our resource
(essentially an update action). We will need to send something in a
[request](http://www.w3.org/TR/di-gloss/#def-http-request) and then send a
response back confirming the posting was a success (_HTTP Status Code 204 ~
Resource updated successfully, no content is returned_).
struct PUT__message: Request {
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



