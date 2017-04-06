import Foundation
import Himotoki
import Stencil

struct Core {
    static func main(file: String) throws {
        let j = try JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: file)), options: [])

        let ast = try APIBlueprintAST.decodeValue(j)

        var globalExtensionCode: String = ""

        let transitions = ast.api.resourceGroup.flatMap {$0.resources}.flatMap {$0.transitions}

        func allResponses(href: String, method: String) -> [APIBlueprintTransition.Transaction.Response] {
            return transitions.filter {$0.href == href}
                .flatMap {$0.httpTransactions}
                .filter {$0.request.method == method}
                .flatMap {$0.responses}
        }

        let trTemplate = Template(templateString: ["/// {{ copy }}",
                                                   "struct {{ name }}: Request {",
                                                   "    typealias Response = {{ response }}",
                                                   "    let baseURL: URL",
                                                   "    var method: HTTPMethod {return {{ method }}}",
                                                   "{% for v in pathVars %}{% if forloop.first %}",
                                                   "    let path = \"\" // see intercept(urlRequest:)",
                                                   "    static let pathTemplate: URITemplate = \"{{ path }}\"",
                                                   "    var pathVars: PathVars",
                                                   "    struct PathVars {",
                                                   "{% endif %}        /// {{ v.doc }}",
                                                   "        var {{ v.name }}: {{ v.type }}",
                                                   "{% if forloop.last %}    }",
                                                   "{% endif %}{% empty %}",
                                                   "    var path: String {return \"{{ path }}\"}{% endfor %}",
                                                   "    var dataParser: DataParser {return RawDataParser()}",
                                                   "{% if paramType %}",
                                                   "    let param: {{ paramType }}",
                                                   "    var bodyParameters: BodyParameters? {return param.jsonBodyParameters}{% endif %}{% if structParam %}",
                                                   "{{ structParam }}{% endif %}",
                                                   "    enum Responses {",
                                                   "{% for r in responseCases %}        case {{ r.case }}({{ r.type }}){% if r.innerType %}",
                                                   "{{ r.innerType }}{% endif %}",
                                                   "{% endfor %}    }",
                                                   "{% if headerVars %}",
                                                   "    var headerFields: [String: String] {return headerVars.context as? [String: String] ?? [:]}",
                                                   "    var headerVars: HeaderVars",
                                                   "    struct HeaderVars {",
                                                   "{% for v in headerVars %}       /// {{ v.doc }}",
                                                   "        var {{ v.name }}: {{ v.type }}",
                                                   "{% endfor %}",
                                                   "    }",
                                                   "{% endif %}",
                                                   "{% if pathVars %}",
                                                   "    // reconstruct URL to use URITemplate.expand. NOTE: APIKit does not support URITemplate format other than `path + query`",
                                                   "    func intercept(urlRequest: URLRequest) throws -> URLRequest {",
                                                   "        var req = urlRequest",
                                                   "        req.url = URL(string: baseURL.absoluteString + {{ name }}.pathTemplate.expand(pathVars.context))!",
                                                   "        return req",
                                                   "    }",
                                                   "{% endif %}",
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
                                                   "{% for r in responseCases %}        case ({{ r.statusCode }}, {{ r.contentType }}):",
                                                   "            return try .{{ r.case }}({% if r.innerType %}Responses.{% endif %}{{ r.type }}.decodeValue(object))",
                                                   "{% endfor %}        default:",
                                                   "            throw ResponseError.undefined(urlResponse.statusCode, contentType)",
                                                   "        }",
                                                   "    }",
                                                   "}\n"].joined(separator: "\n"))
        let globalPathVarsTemplate = Template(templateString: [ // FIXME: rename protocol name
            "extension {{ fqn }}: URITemplateContextConvertible {",
            "    var jsonBodyParametersObject: Any {",
            "        var j: [String: Any] = [:]",
            "{% for v in vars %}        j[\"{{ v.key }}\"] = {{ v.name }}{% if v.optional %}?{% endif %}.jsonBodyParametersObject\n{% endfor %}        return j",
            "    }",
            "}\n"].joined(separator: "\n"))
        try transitions.forEach { transition in
            let request = transition.httpTransactions.first!.request
            let requestTypeName = transition.requestTypeName(request: request)

            let siblingResponses = allResponses(href: transition.href, method: request.method)
            let responseCases = try siblingResponses.map { r -> [String: Any] in
                let type: String
                let contentTypeEscaped = (r.contentType ?? "").replacingOccurrences(of: "/", with: "_")
                let rawType = r.dataStructure.map {SwiftTypeName.nameEscapingKeyword($0.rawType)} ?? "Void"
                let innerType: (local: String, global: String)?
                switch rawType {
                case "object":
                    // inner type
                    type = "Response\(r.statusCode)_\(contentTypeEscaped)"
                    innerType = try swift(dataStructure: r.dataStructure!, name: "\(requestTypeName).Responses.\(type)")
                    _ = innerType.map {globalExtensionCode += $0.global}
                default:
                    // external type (reference to type defined in Data Structures)
                    type = rawType
                    innerType = nil
                }
                var context: [String: String] = [
                    "statusCode": String(r.statusCode),
                    "contentType": r.contentType.map {"\"\($0)\"?"} ?? "_",
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
            if let hrefVariables = transition.hrefVariables {
                let pathVars: [[String: Any]] = hrefVariables.members.map {
                    ["key": $0.content.name,
                     "name": $0.swiftName,
                     "type": $0.swiftType,
                     "doc": $0.swiftDoc,
                     "optional": $0.attributes?.required != true]
                }
                context["pathVars"] = pathVars
                globalExtensionCode += try globalPathVarsTemplate.render([
                    "fqn": [requestTypeName, "PathVars"].joined(separator: "."),
                    "vars": pathVars])
            }
            if let headers = request.headers {
                let headerVars = headers.map { (k, v) in
                    ["key": k,
                     "name": k.lowercased().swiftIdentifierized(),
                     "type": "String",
                     "doc": v]
                }
                context["headerVars"] = headerVars
                globalExtensionCode += try globalPathVarsTemplate.render([
                    "fqn": [requestTypeName, "HeaderVars"].joined(separator: "."),
                    "vars": headerVars])
            }
            if let ds = request.dataStructure {
                switch ds.rawType {
                case "object":
                    // inner type
                    context["paramType"] = "Param"
                    let s = try swift(dataStructure: ds, name: "\(requestTypeName).Param")
                    globalExtensionCode += s.global
                    context["structParam"] = s.local.indented(by: 4)
                default:
                    // external type (reference to type defined in Data Structures)
                    context["paramType"] = ds.rawType
                }
            }
            if let copy = transition.copy {
                context["copy"] = copy
            }
            try print(trTemplate.render(context))
        }

        try ast.api.dataStructures.forEach { ds in
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
    let hrefVariables: APIBlueprintHrefVariables?
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
            hrefVariables: e <|? "hrefVariables",
            method: e <|? "method",
            statusCode: e <|? "statusCode",
            headers: headers)
    }
}

struct APIBlueprintHrefVariables: Decodable {
    let members: [APIBlueprintMember]

    static func decode(_ e: Extractor) throws -> APIBlueprintHrefVariables {
        return try APIBlueprintHrefVariables(members: e <|| "content")
    }
}

struct APIBlueprintMember: APIBlueprintElementDecodable {
    static let elementName = "member"
    let meta: APIBlueprintMeta?
    let attributes: APIBlueprintAttributes?
    let content: APIBlueprintMemberContent

    var swiftName: String {return content.name.swiftIdentifierized()}
    var swiftType: String {return content.type.swiftName(optional: attributes?.required != true)}
    var swiftDoc: String {return [meta?.description, content.value.map {" ex. " + $0}].flatMap {$0}.joined(separator: " ")}

    static func decode(_ e: Extractor) throws -> APIBlueprintMember {
        return try APIBlueprintMember(
            meta: e <|? "meta",
            attributes: e <|? "attributes",
            content: e <| "content")
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
                          "enum": "Int",
                          "boolean": "Bool"]
    static let keywords = ["Error"]
    static func nameEscapingKeyword(_ name: String) -> String {
        return keywords.contains(name) ? name + "_" : name
    }

    func swiftName(optional: Bool) -> String {
        return name + (optional ? "?" : "")
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

protocol APIBlueprintCategoryDecodable: Decodable {
    static var className: String { get }
}
extension APIBlueprintCategoryDecodable {
    static func decodeElement(_ e: Extractor, key: String = "content") throws -> Self {
        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]],
            let j = (contentsJson.first {
                $0["element"] as? String == "category" &&
                    (($0["meta"] as? [String: Any])?["classes"] as? [String])?.contains(className) == true}) else {
            throw DecodeError.custom("no decodable content for \(self)")
        }
        return try decodeValue(j)
    }

    // filter matched elements and decode from hetero array
    static func decodeElements(_ e: Extractor, key: String = "content") throws -> [Self] {
        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]] else {
                        throw DecodeError.custom("no decodable content for \(self)")
        }
        let js = contentsJson.filter {
            $0["element"] as? String == "category" &&
                (($0["meta"] as? [String: Any])?["classes"] as? [String])?.contains(className) == true
        }
        return try js.map(decodeValue)
    }
}

struct APIBlueprintAST: APIBlueprintElementDecodable {
    static let elementName = "parseResult"
    let api: APIBlueprintAPI
    let annotations: [APIBluprintAnnotation]

    static func decode(_ e: Extractor) throws -> APIBlueprintAST {
        return try APIBlueprintAST(
            api: APIBlueprintAPI.decodeElement(e),
            annotations: APIBluprintAnnotation.decodeElements(e))
    }
}

struct APIBlueprintAPI: APIBlueprintCategoryDecodable {
    static let className = "api"
    let title: String?
    let resourceGroup: [APIBlueprintResourceGroup]
    let dataStructures: [APIBlueprintDataStructure]

    static func decode(_ e: Extractor) throws -> APIBlueprintAPI {
        return try APIBlueprintAPI(
            title: e <|? ["meta", "title"],
            resourceGroup: APIBlueprintResourceGroup.decodeElements(e),
            dataStructures: APIBlueprintDataStructures.decodeElements(e).flatMap {
                $0.dataStructures
        })
    }
}

struct APIBlueprintResourceGroup: APIBlueprintCategoryDecodable {
    static let className = "resourceGroup"
    let title: String?
    let resources: [Resource]

    static func decode(_ e: Extractor) throws -> APIBlueprintResourceGroup {
        return try APIBlueprintResourceGroup(
            title: e <|? ["meta", "title"],
            resources: Resource.decodeElements(e))
    }

    struct Resource: APIBlueprintElementDecodable {
        static let elementName = "resource"
        let title: String?
        let transitions: [APIBlueprintTransition]

        static func decode(_ e: Extractor) throws -> Resource {
            return try Resource(
                title: e <|? ["meta", "title"],
                transitions: APIBlueprintTransition.decodeElements(e))
        }
    }
}

struct APIBlueprintDataStructures: APIBlueprintCategoryDecodable {
    static let className = "dataStructures"
    let dataStructures: [APIBlueprintDataStructure]

    static func decode(_ e: Extractor) throws -> APIBlueprintDataStructures {
        return try APIBlueprintDataStructures(
            dataStructures: APIBlueprintDataStructure.decodeElements(e))
    }
}

struct APIBluprintAnnotation: APIBlueprintElementDecodable {
    static let elementName = "annotation"

    static func decode(_ e: Extractor) throws -> APIBluprintAnnotation {
        return APIBluprintAnnotation()
    }
}

struct APIBlueprintTransition: APIBlueprintElementDecodable {
    static let elementName = "transition"

    let meta: APIBlueprintMeta?
    var title: String? {return meta?.title}

    private let contents: [APIBlueprintElement]
    var copy: String? {return contents.first {$0.element == "copy"}?.stringContent}

    private let attributes: APIBlueprintTransitionAttributes
    var href: String {return attributes.href}
    var hrefVariables: APIBlueprintHrefVariables? {return attributes.hrefVariables}
    let httpTransactions: [Transaction]

    static func decode(_ e: Extractor) throws -> APIBlueprintTransition {
        return try APIBlueprintTransition(
            meta: e <|? "meta",
            contents: e <|| "content",
            attributes: e <| "attributes",
            httpTransactions: Transaction.decodeElements(e))
    }

    func requestTypeName(request: Transaction.Request) -> String {
        if let title = title, let first = title.characters.first {
            return (String(first).uppercased() + String(title.characters.dropFirst())).swiftIdentifierized()
        } else {
            return (request.method + "_" + href).swiftIdentifierized()
        }
    }

    struct Transaction: APIBlueprintElementDecodable {
        static let elementName = "httpTransaction"
        let request: Request // currently supports single request per transaction
        let responses: [Response]

        static func decode(_ e: Extractor) throws -> Transaction {
            return try Transaction(
                request: Request.decodeElement(e),
                responses: Response.decodeElements(e))
        }

        struct Request: APIBlueprintElementDecodable {
            static let elementName = "httpRequest"
            let method: String
            let headers: [String: String]?
            let dataStructure: APIBlueprintDataStructure?

            static func decode(_ e: Extractor) throws -> Request {
                let attributes: APIBlueprintAttributes = try e <| "attributes"
                return try Request(
                    method:  e <| ["attributes", "method"],
                    headers: attributes.headers,
                    dataStructure: {do {return try APIBlueprintDataStructure.decodeElement(e)} catch DecodeError.custom {return nil}}())
            }
        }

        struct Response: APIBlueprintElementDecodable {
            static let elementName = "httpResponse"
            private let attributes: APIBlueprintAttributes
            let statusCode: Int // multiple Responses are identified by pair (statusCode, contentType) for a single Request
            let headers: [String: String]?
            var contentType: String? {return headers?["Content-Type"]}
            let dataStructure: APIBlueprintDataStructure?

            static func decode(_ e: Extractor) throws -> Response {
                let attributes: APIBlueprintAttributes = try e <| "attributes"
                guard let statusCode = (attributes.statusCode.flatMap {Int($0)}) else { throw ConversionError.undefined }

                return try Response(
                    attributes: attributes,
                    statusCode: statusCode,
                    headers: attributes.headers,
                    dataStructure: APIBlueprintDataStructure.decodeElementOptional(e))
            }
        }
    }
}

struct APIBlueprintTransitionAttributes: Decodable {
    let href: String
    let hrefVariables: APIBlueprintHrefVariables?

    static func decode(_ e: Extractor) throws -> APIBlueprintTransitionAttributes {
        return try APIBlueprintTransitionAttributes(
            href: e <| "href",
            hrefVariables: e <|? "hrefVariables")
    }
}

enum APIBlueprintDataStructure: APIBlueprintElementDecodable {
    static let elementName = "dataStructure"

    case named(id: String, members: [APIBlueprintMember])
    case anonymous(members: [APIBlueprintMember])
    case ref(id: String)

    var id: String? {
        switch self {
        case .named(let id, _): return id
        case .ref(let id): return id
        case .anonymous: return nil
        }
    }

    var rawType: String {
        switch self {
        case .named(let id, _): return id
        case .ref(let id): return id
        case .anonymous: return "object"
        }
    }

    var members: [APIBlueprintMember] {
        switch self {
        case .named(_, let members): return members
        case .anonymous(let members): return members
        case .ref: return []
        }
    }

    static func decode(_ e: Extractor) throws -> APIBlueprintDataStructure {
        guard let content: APIBlueprintElement = try (e <|| "content").first else {
            throw ConversionError.unknownDataStructure
        }
        if let id = content.meta?.id {
            return .named(id: id, members: try APIBlueprintMember.decodeElementsOfContents(e))
        }
        if content.element == "object" {
            return .anonymous(members: try APIBlueprintMember.decodeElementsOfContents(e))
        }
        return .ref(id: content.element)
    }
}

protocol APIBlueprintElementDecodable: Decodable {
    static var elementName: String { get }
}
extension APIBlueprintElementDecodable {
    static func decodeElement(_ e: Extractor, key: String = "content") throws -> Self {
        guard let decoded = try decodeElementOptional(e, key: key) else {
            throw DecodeError.custom("no decodable content for \(self)")
        }
        return decoded
    }

    static func decodeElementOptional(_ e: Extractor, key: String = "content") throws -> Self? {
        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]],
            let j = (contentsJson.first {$0["element"] as? String == elementName}) else {
                return nil
        }
        return try decodeValue(j)
    }

    // filter matched elements and decode from hetero array
    static func decodeElements(_ e: Extractor, key: String = "content") throws -> [Self] {
        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]] else {
            throw DecodeError.custom("no decodable content for \(self)")
        }
        return try contentsJson.filter {$0["element"] as? String == elementName}.map(decodeValue)
    }

    static func decodeElementsOfContents(_ e: Extractor, key: String = "content", subKey: String = "content") throws -> [Self] {
        guard let contentsJson = (e.rawValue as? [String: Any])?[key] as? [[String: Any]],
            let subContentsJson = (contentsJson.first?[subKey] as? [[String: Any]]) else {
            throw DecodeError.custom("no decodable content for \(self)")
        }

        return try subContentsJson.filter {$0["element"] as? String == elementName}.map(decodeValue)
    }
}

func swift(dataStructure ds: APIBlueprintDataStructure, name: String? = nil) throws -> (local: String, global: String) {
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

    guard let name = ((name ?? ds.id).map {SwiftTypeName.nameEscapingKeyword($0)}) else { throw ConversionError.undefined }
    let vars: [[String: Any]] = ds.members.map { m in
        let optional = m.attributes?.required != true
        let optionalSuffix = optional ? "?" : ""
        return [
            "name": m.swiftName,
            "type": m.swiftType,
            "optional": optional,
            "doc": m.swiftDoc,
            "decoder": (m.content.type.isArray ? "<||" : "<|") + optionalSuffix]}

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
