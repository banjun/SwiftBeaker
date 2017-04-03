import Foundation
import Himotoki
import Stencil

struct Core {
    static func main(file: String) throws {
        let j = try JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: file)), options: [])
        let apib = try APIBlueprintElement.decodeValue(j)
        var globalExtensionCode: String = ""

        let resourceGroups = (apib.elements(byName: "category") ?? [])
            .flatMap {$0.elements(byClass: "resourceGroup") ?? []}
        let resources = resourceGroups.flatMap {$0.arrayContent ?? []}
        let transitions = try resources.flatMap {r in try (r.elements(byName: "transition") ?? []).map {try Transition($0, parentResource: r)}}

        func allResponses(href: String, method: String) -> [HTTPTransaction.Response] {
            return transitions.filter {$0.href == href}
                .flatMap {$0.httpTransactions}
                .filter {$0.httpRequest.method == method}
                .map {$0.httpResponse}
        }

        let trTemplate = Template(templateString: ["/// {{ copy }}",
                                                   "struct {{ name }}: Request {",
                                                   "    typealias Response = {{ response }}",
                                                   "    let baseURL: URL",
                                                   "    var method: HTTPMethod {return {{ method }}}",
                                                   "    var path: String {return \"{{ path }}\"}",
                                                   "    var dataParser: DataParser {return RawDataParser()}",
                                                   "{% if paramType %}",
                                                   "    let param: {{ paramType }}",
                                                   "    var bodyParameters: BodyParameters? {return param.jsonBodyParameters}{% endif %}{% if structParam %}",
                                                   "{{ structParam }}{% endif %}",
                                                   "    enum Responses {",
                                                   "{% for r in responseCases %}        case {{ r.case }}({{ r.type }}){% if r.innerType %}",
                                                   "{{ r.innerType }}{% endif %}",
                                                   "{% endfor %}    }",
                                                   "",
                                                   "    // conver object (Data) to expected type",
                                                   "    func intercept(object: Any, urlResponse: HTTPURLResponse) throws -> Any {",
                                                   "        let contentType = urlResponse.allHeaderFields[\"Content-Type\"] as? String",
                                                   "        switch (object, contentType) {",
                                                   "        case let (data as Data, \"application/json\"?): return try JSONSerialization.jsonObject(with: data, options: [])",
                                                   "        case let (data as Data, _): return data",
                                                   "        default: return object",
                                                   "        }",
                                                   "    }",
                                                   "",
                                                   "    func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Response {",
                                                   "        let contentType = urlResponse.allHeaderFields[\"Content-Type\"] as? String",
                                                   "        switch (urlResponse.statusCode, contentType) {",
                                                   "{% for r in responseCases %}        case ({{ r.statusCode }}, \"{{ r.contentType }}\"?):",
                                                   "            return try .{{ r.case }}({% if r.innerType %}Responses.{% endif %}{{ r.type }}.decodeValue(object))",
                                                   "{% endfor %}        default:",
                                                   "            throw ResponseError.undefinedResponse(urlResponse.statusCode, contentType)",
                                                   "        }",
                                                   "    }",
                                                   "}\n"].joined(separator: "\n"))
        try transitions.forEach { transition in
            let request = transition.httpTransactions.first!.httpRequest
            let requestTypeName = transition.httpTransactions.first!.requestTypeName
            let dss = request.dataStructure?.arrayContent ?? []
            guard dss.count <= 1 else { throw ConversionError.unknownDataStructure }

            let siblingResponses = allResponses(href: transition.href, method: request.method)
            let responseCases = try siblingResponses.map { r -> [String: Any] in
                let type: String
                let contentTypeEscaped = (r.contentType ?? "").replacingOccurrences(of: "/", with: "_")
                let rawType = (r.dataStructure?.arrayContent ?? []).first.flatMap {$0.element}.map {SwiftTypeName.nameEscapingKeyword($0)} ?? "unknown"
                let innerType: (local: String, global: String)?
                switch rawType {
                case "object":
                    // inner type
                    type = "Response\(r.statusCode)_\(contentTypeEscaped)"
                    innerType = try swift(dataStructure: (r.dataStructure?.arrayContent ?? []).first!, name: "\(requestTypeName).Responses.\(type)")
                    _ = innerType.map {globalExtensionCode += $0.global}
                default:
                    // external type (reference to type defined in Data Structures)
                    type = rawType
                    innerType = nil
                }
                var context: [String: String] = [
                    "statusCode": String(r.statusCode),
                    "contentType": r.contentType ?? "",
                    "case": "http\(r.statusCode)_\(contentTypeEscaped)",
                    "type": type,
                    ]
                if let innerType = innerType {
                    context["innerType"] = innerType.local.indented(by: 8)
                }
                return context
            }

            var context: [String: Any] = [
                "name": requestTypeName,
                "response": "Responses",
                "responseCases": responseCases,
                "method": "." + request.method.lowercased(),
                "path": transition.href
            ]
            if let ds = dss.first {
                switch ds.element {
                case "object":
                    // inner type
                    context["paramType"] = "Param"
                    let s = try swift(dataStructure: ds, name: "\(requestTypeName).Param")
                    globalExtensionCode += s.global
                    context["structParam"] = s.local.indented(by: 4)
                default:
                    // external type (reference to type defined in Data Structures)
                    context["paramType"] = ds.element
                }
            }
            if let copy = transition.copy {
                context["copy"] = copy
            }
            try print(trTemplate.render(context))
        }

        let dataStructures = (apib.elements(byName: "category") ?? [])
            .flatMap {$0.elements(byClass: "dataStructures") ?? []}
            .flatMap {$0.arrayContent ?? []}
            .flatMap {$0.arrayContent ?? []}
        try dataStructures.forEach { ds in
            let s = try swift(dataStructure: ds)
            globalExtensionCode += s.global
            print(s.local)
        }

        print(preamble)
        print(globalExtensionCode)
    }
}

enum ConversionError: Error {
    case undefined
    case unknownDataStructure
}

struct APIBlueprintElement: Decodable {
    let element: String
    let meta: APIBlueprintMeta?
    let arrayContent: [APIBlueprintElement]?
    let memberContent: APIBlueprintMemberContent?
    let stringContent: String?
    let attributes: APIBlueprintAttributes?

    static func decode(_ e: Extractor) throws -> APIBlueprintElement {
        return try APIBlueprintElement(
            element: e <| "element",
            meta: e <|? "meta",
            arrayContent: {do {return try e <||? "content"} catch DecodeError.typeMismatch {return nil}}(),
            memberContent: {do {return try e <|? "content"} catch DecodeError.typeMismatch {return nil}}(),
            stringContent: {do {return try e <|? "content"} catch DecodeError.typeMismatch {return nil}}(),
            attributes: e <|? "attributes")
    }

    func elements(byName name: String) -> [APIBlueprintElement]? {
        return (arrayContent ?? []).filter {$0.element == name}
    }

    func elements(byClass c: String) -> [APIBlueprintElement]? {
        return (arrayContent ?? []).filter {$0.meta?.classes?.contains(c) == true}
    }
}

struct APIBlueprintMeta: Decodable {
    let classes: [String]?
    let id: String?
    let description: String?
    let title: String?

    static func decode(_ e: Extractor) throws -> APIBlueprintMeta {
        return try APIBlueprintMeta(
            classes: e <||? "classes",
            id: e <|? "id",
            description: e <|? "description",
            title: e <|? "title")
    }
}

struct APIBlueprintAttributes: Decodable {
    let typeAttributes: [String]?
    var required: Bool? {return typeAttributes?.contains("required")}
    let href: String?
    let method: String?
    let statusCode: String?
    let headers: [String: String]?

    static func decode(_ e: Extractor) throws -> APIBlueprintAttributes {
        var headers: [String: String]?
        if let headersElement: APIBlueprintElement = (try e <|? "headers") {
            headers = [:]
            headersElement.elements(byName: "member")?.flatMap {$0.memberContent}.forEach { m in
                headers?[m.name] = m.value
            }
        }

        return try APIBlueprintAttributes(
            typeAttributes: e <||? "typeAttributes",
            href: e <|? "href",
            method: e <|? "method",
            statusCode: e <|? "statusCode",
            headers: headers)
    }
}

struct APIBlueprintMemberContent: Decodable {
    let name: String
    let type: SwiftTypeName
    let value: String?

    static func decode(_ e: Extractor) throws -> APIBlueprintMemberContent {
        let valueString: String? = try {do {return try e <|? ["value", "content"]} catch DecodeError.typeMismatch {return nil}}()
        let valueDict: [String: String]? = try {do {return try e <|-|? ["value", "content"]} catch DecodeError.typeMismatch {return nil}}()
        let valueElements: [APIBlueprintElement]? = try {do {return try e <||? ["value", "content"]} catch DecodeError.typeMismatch {return nil}}()
        let value: String? = valueString ?? valueDict?["element"] ?? valueElements.map { e -> String in "[" + e.flatMap {$0.stringContent}.joined(separator: ", ") + "]"}

        return try APIBlueprintMemberContent(
            name: e <| ["key", "content"],
            type: e <| ["value"],
            value: value)
    }
}

struct SwiftTypeName: Decodable {
    let name: String
    private let raw: String
    var isArray: Bool {return raw == "array"}

    static let typeMap = ["string": "String",
                          "number": "Int",
                          "boolean": "Bool"]
    static let keywords = ["Error"]
    static func nameEscapingKeyword(_ name: String) -> String {
        return keywords.contains(name) ? name + "_" : name
    }

    static func decode(_ e: Extractor) throws -> SwiftTypeName {
        let raw: String = try e <| "element"
        let resolved = typeMap[raw].map {nameEscapingKeyword($0)} ?? raw
        switch resolved {
        case "array":
            let contents: [APIBlueprintElement] = try e <|| "content"
            let resolved = contents.first.map {$0.element}.map {typeMap[$0] ?? $0} ?? "Any"
            return SwiftTypeName(name: "[" + resolved + "]", raw: raw)
        default:
            return SwiftTypeName(name: resolved, raw: raw)
        }
    }
}

struct Transition {
    let title: String?
    let copy: String?
    let href: String
    let httpTransactions: [HTTPTransaction]

    init(_ element: APIBlueprintElement, parentResource: APIBlueprintElement? = nil) throws {
        guard let href = element.attributes?.href ?? parentResource?.attributes?.href else { throw ConversionError.undefined }
        guard let httpTransactions = element.elements(byName: "httpTransaction") else { throw ConversionError.undefined }
        self.title = element.meta?.title
        self.copy = element.elements(byName: "copy")?.first?.stringContent
        self.href = href
        self.httpTransactions = try httpTransactions.map {try HTTPTransaction($0, href: href, title: element.meta?.title)}
    }
}

struct HTTPTransaction {
    private let title: String?
    let httpRequest: Request
    let httpResponse: Response
    fileprivate let href: String

    var requestTypeName: String {
        if let title = title, let first = title.characters.first {
            return (String(first).uppercased() + String(title.characters.dropFirst())).swiftIdentifierized()
        } else {
            return (httpRequest.method + "_" + href).swiftIdentifierized()
        }
    }

    init(_ element: APIBlueprintElement, href: String, title: String?) throws {
        guard let httpRequest = element.elements(byName: "httpRequest")?.first else { throw ConversionError.undefined }
        guard let httpResponse = element.elements(byName: "httpResponse")?.first else { throw ConversionError.undefined }
        self.title = title
        self.httpRequest = try Request(httpRequest)
        self.httpResponse = try Response(httpResponse)
        self.href = href
    }

    struct Request: HTTPMessagePayload {
        let copy: String? = nil
        let headers: [String: String]? = nil
        let dataStructure: APIBlueprintElement?
        let method: String

        init(_ element: APIBlueprintElement) throws {
            guard let method = element.attributes?.method else { throw ConversionError.undefined }
            guard let dataStructures = element.elements(byName: "dataStructure") else { throw ConversionError.unknownDataStructure }
            self.method = method
            self.dataStructure = dataStructures.first
        }
    }

    struct Response: HTTPMessagePayload {
        let copy: String? = nil
        let headers: [String: String]?
        let dataStructure: APIBlueprintElement?
        let statusCode: Int // multiple Responses are identified by pair (statusCode, contentType) for a single Request
        let contentType: String?

        init(_ element: APIBlueprintElement) throws {
            guard let dataStructures = element.elements(byName: "dataStructure") else { throw ConversionError.unknownDataStructure }
            guard let statusCode = (element.attributes?.statusCode.flatMap {Int($0)}) else { throw ConversionError.undefined }
            self.dataStructure = dataStructures.first
            self.headers = element.attributes?.headers
            self.statusCode = statusCode
            self.contentType = headers?["Content-Type"]
        }
    }
}

protocol HTTPMessagePayload {
    var headers: [String: String]? { get }
    var copy: String? { get }
    var dataStructure: APIBlueprintElement? { get } // The content MUST NOT contain more than one Data Structure.
    var assets: [APIBlueprintElement]? { get } // The content SHOULD NOT contain more than one asset of its respective type. (body or body schema)
}
extension HTTPMessagePayload {
    var assets: [APIBlueprintElement]? {return nil} // unsupported
}

func swift(dataStructure ds: APIBlueprintElement, name: String? = nil) throws -> (local: String, global: String) {
    let localDSTemplate = Template(templateString: ["struct {{ name }} { {% for v in vars %}",
                                                    "    /// {{ v.doc }}",
                                                    "    var {{ v.name }}: {{ v.type }}{% endfor %}",
                                                    "}\n"].joined(separator: "\n"))
    let globalDSTemplate = Template(templateString: ["extension {{ fqn }}: Decodable {",
                                                     "    static func decode(_ e: Extractor) throws -> {{ fqn }} {",
                                                     "        return try self.init({% for v in vars %}",
                                                     "            {{ v.name }}: e {{ v.decoder }} \"{{ v.name }}\"{% if not forloop.last %},{% endif %}{% endfor %}",
                                                     "        )",
                                                     "    }",
                                                     "}",
                                                     "extension {{ fqn }}: DataStructureType {",
                                                     "    var jsonBodyParametersObject: Any {",
                                                     "        var j: [String: Any] = [:]",
                                                     "{% for v in vars %}        j[\"{{ v.name }}\"] = {{ v.name }}{% if v.optional %}?{% endif %}.jsonBodyParametersObject\n{% endfor %}        return j",
                                                     "    }",
                                                     "}\n"].joined(separator: "\n"))

    guard let name = ((name ?? ds.meta?.id).map {SwiftTypeName.nameEscapingKeyword($0)}) else { throw ConversionError.undefined }
    let members = (ds.elements(byName: "member") ?? [])
    let vars: [[String: Any]] = try members.map { m in
        guard let content = m.memberContent else {
            throw NSError(domain: "Data Structure Generation", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(name) contains invalid member: \(m)"])
        }
        let doc = [m.meta?.description.map {$0 + " "}, content.value.map {"ex. " + $0}].flatMap {$0}.joined(separator: " ")
        let optional = m.attributes?.required != true
        let optionalSuffix = optional ? "?" : ""
        return [
            "name": content.name.swiftIdentifierized(),
            "type": content.type.name + optionalSuffix,
            "optional": optional,
            "doc": doc,
            "decoder": (content.type.isArray ? "<||" : "<|") + optionalSuffix]}

    let localName = name.components(separatedBy: ".").last ?? name
    return (local: try localDSTemplate.render(["name": localName.swiftIdentifierized(),
                                               "vars": vars]),
            global: try globalDSTemplate.render(["name": localName.swiftIdentifierized(),
                                                 "fqn": name.components(separatedBy: ".").map {$0.swiftIdentifierized()}.joined(separator: "."),
                                                 "vars": vars]))
}

extension String {
    func indented(by level: Int) -> String {
        return components(separatedBy: "\n").map {Array(repeating: " ", count: level).joined() + $0}.joined(separator: "\n")
    }

    func swiftIdentifierized() -> String {
        let cs = CharacterSet(charactersIn: " _/{?,}-")
        return components(separatedBy: cs).joined(separator: "_")
    }
}
