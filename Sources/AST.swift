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

struct APIBlueprintCopy: APIBlueprintElementDecodable {
    static let elementName = "copy"
    let text: String
    static func decode(_ e: Extractor) throws -> APIBlueprintCopy {
        return try APIBlueprintCopy(text: e <| "content")
    }
}

struct APIBlueprintTransition: APIBlueprintElementDecodable {
    static let elementName = "transition"

    let meta: APIBlueprintMeta?
    var title: String? {return meta?.title}

    let copy: APIBlueprintCopy?

    let attributes: Attributes
    let httpTransactions: [Transaction]

    static func decode(_ e: Extractor) throws -> APIBlueprintTransition {
        return try APIBlueprintTransition(
            meta: e <|? "meta",
            copy: APIBlueprintCopy.decodeElementOptional(e),
            attributes: e <| "attributes",
            httpTransactions: Transaction.decodeElements(e))
    }

    func requestTypeName(request: Transaction.Request) -> String {
        if let title = title, let first = title.characters.first {
            return (String(first).uppercased() + String(title.characters.dropFirst())).swiftIdentifierized()
        } else {
            return (request.method + "_" + attributes.href).swiftIdentifierized()
        }
    }

    struct Attributes: Decodable {
        let href: String
        let hrefVariables: HrefVariables?

        static func decode(_ e: Extractor) throws -> Attributes {
            return try Attributes(
                href: e <| "href",
                hrefVariables: HrefVariables.decodeElementOptional(e, key: HrefVariables.elementName))
        }

        struct HrefVariables: APIBlueprintElementDecodable {
            static let elementName = "hrefVariables"
            let members: [APIBlueprintMember]
            static func decode(_ e: Extractor) throws -> HrefVariables {
                return try HrefVariables(members: APIBlueprintMember.decodeElements(e))
            }
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
            let headers: Headers?
            let dataStructure: APIBlueprintDataStructure?

            static func decode(_ e: Extractor) throws -> Request {
                return try Request(
                    method:  e <| ["attributes", "method"],
                    headers: e <|? ["attributes", "headers"],
                    dataStructure: {do {return try APIBlueprintDataStructure.decodeElement(e)} catch DecodeError.custom {return nil}}())
            }
        }

        struct Response: APIBlueprintElementDecodable {
            static let elementName = "httpResponse"
            let statusCode: Int // multiple Responses are identified by pair (statusCode, contentType) for a single Request
            let headers: Headers?
            let contentType: String?
            let dataStructure: APIBlueprintDataStructure?

            static func decode(_ e: Extractor) throws -> Response {
                guard let statusCode = ((try e <|? ["attributes", "statusCode"]).flatMap {Int($0)}) else {
                    throw ConversionError.undefined
                }
                let headers: Headers? = try e <|? ["attributes", "headers"]

                return try Response(
                    statusCode: statusCode,
                    headers: headers,
                    contentType: headers?.members.map {$0.content}.first {$0.name == "Content-Type"}?.value,
                    dataStructure: APIBlueprintDataStructure.decodeElementOptional(e))
            }
        }

        struct Headers: Decodable {
            static let elementName = "httpHeaders"
            let members: [APIBlueprintMember]
            static func decode(_ e: Extractor) throws -> Headers {
                return try Headers(members: APIBlueprintMember.decodeElements(e))
            }
            var dictionary: [String: String] {
                var d = [String: String]()
                members.forEach {
                    guard $0.content.name != "Content-Type" else { return } // ignore Content-Type
                    d[$0.content.name] = $0.content.value
                }
                return d
            }
        }
    }
}

struct APIBlueprintElement: Decodable {
    let element: String
    let meta: APIBlueprintMeta?

    static func decode(_ e: Extractor) throws -> APIBlueprintElement {
        return try APIBlueprintElement(
            element: e <| "element",
            meta: e <|? "meta")
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

struct APIBlueprintMember: APIBlueprintElementDecodable {
    static let elementName = "member"
    let meta: APIBlueprintMeta?
    let typeAttributes: [String]?
    var required: Bool {return typeAttributes?.contains("required") == true}
    let content: APIBlueprintMemberContent

    static func decode(_ e: Extractor) throws -> APIBlueprintMember {
        return try APIBlueprintMember(
            meta: e <|? "meta",
            typeAttributes: e <||? ["attributes", "typeAttributes"],
            content: e <| "content")
    }
}

extension APIBlueprintMember {
    var swiftName: String {return content.name.swiftIdentifierized()}
    var swiftType: String {
        let name: String
        switch content.type {
        case let .exact(t):
            name = t.swiftTypeMapped().swiftKeywordsEscaped()
        case let .array(t):
            name = "[" + (t.map {$0.swiftTypeMapped().swiftKeywordsEscaped()} ?? "Any") + "]"
        }
        return name + (required ? "" : "?")
    }
    var swiftDoc: String {return [meta?.description, content.displayValue.map {" ex. " + $0}].flatMap {$0}.joined(separator: " ")}
}

struct APIBlueprintStringElement: APIBlueprintElementDecodable {
    static let elementName = "string"
    let value: String
    static func decode(_ e: Extractor) throws -> APIBlueprintStringElement {
        return try APIBlueprintStringElement(value: e <| "content")
    }
}

struct APIBlueprintMemberContent: Decodable {
    let name: String
    let type: APIBlueprintMemberType
    let value: String? // value, 42, [value], ...
    let displayValue: String? // "value", 42, ["value"], ...

    static func decode(_ e: Extractor) throws -> APIBlueprintMemberContent {
        let value: String?
        let displayValue: String?
        let type: APIBlueprintMemberType = try e <| "value"
        switch type {
        case .exact("string"):
            let string: String? = try e <|? ["value", "content"]
            value = string
            displayValue = value.map {"\"" + $0 + "\""}
        case .exact("number"):
            let number: Int? = try e <|? ["value", "content"]
            value = number.map {String($0)}
            displayValue = value
        case .array:
            let contents = try StringArrayValue.decodeElement(e, key: "value").content
            value = "[" + contents.map {$0.value}.joined(separator: ", ") + "]"
            displayValue = "[" + contents.map {"\"" + $0.value + "\""}.joined(separator: ", ") + "]"
        case .exact("enum"):
            throw ConversionError.notSupported("\(type) at \(self)")
        case let .exact(id):
            value = id
            displayValue = value
        }

        return try APIBlueprintMemberContent(
            name: e <| ["key", "content"],
            type: type,
            value: value,
            displayValue: displayValue)
    }

    struct StringArrayValue: APIBlueprintElementDecodable {
        static let elementName = "array"
        let content: [APIBlueprintStringElement]
        static func decode(_ e: Extractor) throws -> StringArrayValue {
            return try StringArrayValue(content: APIBlueprintStringElement.decodeElements(e))
        }
    }
}

enum APIBlueprintMemberType: Decodable {
    case exact(String)
    case array(String?)

    var isArray: Bool {
        switch self {
        case .exact: return false
        case .array: return true
        }
    }

    static func decode(_ e: Extractor) throws -> APIBlueprintMemberType {
        let raw: String = try e <| "element"
        switch raw {
        case "array":
            let contentTypes: [APIBlueprintAnyElement] = try e <|| "content"
            return .array(contentTypes.first?.element)
        default:
            return .exact(raw)
        }
    }
}

struct APIBlueprintAnyElement: Decodable {
    let element: String
    static func decode(_ e: Extractor) throws -> APIBlueprintAnyElement {
        return try APIBlueprintAnyElement(element: e <| "element")
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
