import Himotoki

// MARK: - top-level

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

// MARK: - Categories

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

// MARK: - Elements

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

struct APIBluprintAnnotation: APIBlueprintElementDecodable {
    static let elementName = "annotation"

    static func decode(_ e: Extractor) throws -> APIBluprintAnnotation {
        return APIBluprintAnnotation()
    }
}

// MARK: - 

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
