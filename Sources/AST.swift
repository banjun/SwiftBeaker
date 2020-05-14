import Foundation

enum APIElements {
    struct Meta: Codable {
        var id: String?
        var ref: String?
        var classes: [String]?
        var title: String?
        var description: String?
        var links: [LinkElement]?

        init(id: String? = nil, ref: String? = nil, classes: [String]? = nil, title: String? = nil, description: String? = nil, links: [LinkElement]? = nil) {
            self.id = id
            self.ref = ref
            self.classes = classes
            self.title = title
            self.description = description
            self.links = links
        }
    }

    enum NilAttributes: APIElementsAttributes {
        func encode(to encoder: Encoder) throws {}
        init(from decoder: Decoder) throws {fatalError()}
    }
}

protocol BasicElement: Codable {
//    static var elementName: String { get }
    associatedtype Content
    associatedtype Attributes: APIElementsAttributes
    var element: String { get }
    var meta: APIElements.Meta? { get }
    var attributes: Attributes? { get }
    var content: Content { get }
}

class AnyBasicElementBox<Attributes: APIElementsAttributes>: Codable {
    var element: String {fatalError("abstract")}
    var meta: APIElements.Meta? {fatalError("abstract")}
    var attributes: Attributes? {fatalError("abstract")}
    var content: Any {fatalError("abstract")}
}

final class BasicElementBox<Element: BasicElement>: AnyBasicElementBox<Element.Attributes> {
    private let base: Element
    init(_ base: Element) {
        self.base = base
        super.init()
    }

    required init(from decoder: Decoder) throws {
        self.base = try .init(from: decoder)
        super.init()
    }

    override func encode(to encoder: Encoder) throws {
        try base.encode(to: encoder)
    }

    override var element: String {base.element}
    override var meta: APIElements.Meta? {base.meta}
    override var attributes: Element.Attributes? {base.attributes}
    override var content: Any {base.content}
}

final class AnyBasicElement<Attributes: APIElementsAttributes>: BasicElement {
    private let box: AnyBasicElementBox<Attributes>
    init<Element: BasicElement>(_ base: Element) where Element.Attributes == Attributes {
        self.box = BasicElementBox<Element>(base)
    }

    func encode(to encoder: Encoder) throws {
        try box.encode(to: encoder)
    }

    var element: String {box.element}
    var meta: APIElements.Meta? {box.meta}
    var attributes: Attributes? {box.attributes}
    var content: Any {box.content}
}

struct AnyElement: BasicElement {
    var element: String
    var meta: APIElements.Meta?
    var attributes: AnyAttributes?
    var content: Any

    private enum CodingKeys: CodingKey {
        case element, meta, attributes, content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let element = try container.decode(String.self, forKey: .element)
        self.element = element
        switch element {
        case StringElement.elementName: self.content = try container.decode(StringElement.Content.self, forKey: .content)
        case CategoryElement.elementName: self.content = try container.decode(CategoryElement.Content.self, forKey: .content)
        case CopyElement.elementName: self.content = try container.decode(CopyElement.Content.self, forKey: .content)
        case ResourceElement.elementName: self.content = try container.decode(ResourceElement.Content.self, forKey: .content)
        case TransitionElement.elementName: self.content = try container.decode(TransitionElement.Content.self, forKey: .content)
        case HTTPTransactionElement.elementName: self.content = try container.decode(HTTPTransactionElement.Content.self, forKey: .content)
        case HTTPRequestElement.elementName: self.content = try container.decode(HTTPRequestElement.Content.self, forKey: .content)
        case HTTPResponseElement.elementName: self.content = try container.decode(HTTPResponseElement.Content.self, forKey: .content)
        case AssetElement.elementName: self.content = try container.decode(AssetElement.Content.self, forKey: .content)
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element name to decode content: \(element)"))
        }

        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
        self.attributes = try container.decodeIfPresent(AnyAttributes.self, forKey: .attributes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(element, forKey: .element)
        try container.encodeIfPresent(meta, forKey: .meta)
        try container.encodeIfPresent(attributes, forKey: .attributes)

        switch element {
        case StringElement.elementName: try container.encode(content as! StringElement.Content, forKey: .content)
        default: throw EncodingError.invalidValue(element, EncodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element name to encode content: \(element)"))
        }
    }
}

struct AnyAttributes: APIElementsAttributes {

}

final class Box<Value: Codable>: Codable {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }
    init(from decoder: Decoder) throws {
        try self.value = Value(from: decoder)
    }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

protocol TypedElement: BasicElement {
    static var elementName: String { get }
}

struct StringElement: TypedElement {
    static let elementName = "string"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: String
}

struct LinkElement: TypedElement {
    static let elementName = "link"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes?
    var content: String
    struct Attributes: APIElementsAttributes {
        var relation: StringElement
        var href: StringElement
    }
}

struct CopyElement: TypedElement {
    static var elementName = "copy"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: String
}

struct CategoryElement: TypedElement {
    static let elementName = "category"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}
extension CategoryElement {
//    var resources: [Any] {
//        content.compactMap {$0.content}
//    }
}

struct ResourceElement: TypedElement {
    static let elementName = "resource"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}

struct TransitionElement: TypedElement {
    static let elementName = "transition"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}

struct HTTPTransactionElement: TypedElement {
    static let elementName = "httpTransaction"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}

struct HTTPRequestElement: TypedElement {
    static let elementName = "httpRequest"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}

struct HTTPResponseElement: TypedElement {
    static let elementName = "httpResponse"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyElement]
}

struct AssetElement: TypedElement {
    static let elementName = "asset"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: String
}

protocol APIElementsAttributes: Codable {

}

struct ParseResultElement: TypedElement {
    static let elementName = "parseResult"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes?
    var content: [AnyElement]

    struct Attributes: APIElementsAttributes {
        var meta: [APIElements.Meta]
    }
}

struct DataStructureElement: TypedElement {
    static let elementName = "dataStructure"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.NilAttributes?
    var content: [AnyBasicElement<APIElements.NilAttributes>]
}

struct MemberElement: TypedElement {
    static let elementName = "member"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes?
    var content: [Property]

    struct Attributes: APIElementsAttributes {
        var typeAttributes: [String]
    }

    struct Property: Codable {
        var key: AnyBasicElement<APIElements.NilAttributes>
        var value: AnyBasicElement<APIElements.NilAttributes>
    }
}

typealias APIBlueprintAST = ParseResultElement
extension APIBlueprintAST {
    var resourceGroup: CategoryElement? {
        content.first {$0.element == "resourceGroup"}
            .flatMap {try? JSONEncoder().encode($0)}
            .flatMap {try? JSONDecoder().decode(CategoryElement.self, from: $0)}
    }
}

//// MARK: - top-level
//
//protocol APIBlueprintASTElement: Decodable {
//    static var apiBlueprintASTElementName: String { get }
//}
//extension APIBlueprintASTElement {
//    init(from decoder: Decoder) throws {
//        let parsed = try Element<Self>(from: decoder)
//        guard parsed.element == Self.apiBlueprintASTElementName else {
//            throw DecodingError.valueNotFound(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "expect elemenet = \"\(Self.apiBlueprintASTElementName)\" but got element = \"\(parsed.element)\")"))
//        }
//        self = parsed.content
//    }
//}
//protocol APIBlueprintASTCategory: APIBlueprintASTElement {
//    static var apiBlueprintASTClassName: String { get }
//}
//extension APIBlueprintCategory {
//    init(from decoder: Decoder) throws {
//        let parsed = try Element<Self>(from: decoder)
//        guard parsed.element == "category" else {
//            throw DecodingError.valueNotFound(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "expect elemenet = \"\("category")\" but got element = \"\(parsed.element)\")"))
//        }
//        self = parsed.content
//    }
//}
//
//struct Element<T: APIBlueprintASTElement>: Decodable {
//    var element: String
//    var meta: Meta
//    var attributes: Attributes
//    var content: T
//}
//
//struct Meta: Codable {
//    var classes: [String]
//    var title: String?
//}
//
//struct Attributes: Codable {
//    var meta: [Meta]
//}
//
//struct APIBlueprintAST: APIBlueprintASTElement {
//    static let apiBlueprintASTElementName = "parseResult"
//    var api: APIBlueprintAPI
//    var annotations: [APIBluprintAnnotation]
//}
//
//// MARK: - Categories
//
//struct APIBlueprintAPI: APIBlueprintASTCategory {
//    static let apiBlueprintASTClassName = "api"
//    private var meta: Meta?
//    var title: String? {meta?.title}
//    var resourceGroup: [APIBlueprintResourceGroup]
//    var dataStructures: [APIBlueprintDataStructure]
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintAPI {
//        return try APIBlueprintAPI(
//            title: e <|? ["meta", "title"],
//            resourceGroup: APIBlueprintResourceGroup.decodeElements(e),
//            dataStructures: APIBlueprintDataStructures.decodeElements(e).flatMap {
//                $0.dataStructures
//        })
//    }
//}
//
//struct APIBlueprintResourceGroup: APIBlueprintCategoryDecodable {
//    static let className = "resourceGroup"
//    let title: String?
//    let resources: [Resource]
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintResourceGroup {
//        return try APIBlueprintResourceGroup(
//            title: e <|? ["meta", "title"],
//            resources: Resource.decodeElements(e))
//    }
//
//    struct Resource: APIBlueprintElementDecodable {
//        static let elementName = "resource"
//        let title: String?
//        let attributes: Attributes?
//        let transitions: [APIBlueprintTransition]
//
//        static func decode(_ e: Extractor) throws -> Resource {
//            return try Resource(
//                title: e <|? ["meta", "title"],
//                attributes: e <|? "attributes",
//                transitions: APIBlueprintTransition.decodeElements(e))
//        }
//
//        struct Attributes: Himotoki.Decodable {
//            let href: String?
//            static func decode(_ e: Extractor) throws -> APIBlueprintResourceGroup.Resource.Attributes {
//                return try Attributes(href: e <|? "href")
//            }
//        }
//
//        func href(transition: APIBlueprintTransition, request: APIBlueprintTransition.Transaction.Request) throws -> String {
//            // cascade
//            guard let href = request.href ?? transition.attributes?.href ?? attributes?.href else { throw ConversionError.undefined }
//            return href
//        }
//    }
//}
//
//struct APIBlueprintDataStructures: APIBlueprintCategoryDecodable {
//    static let className = "dataStructures"
//    let dataStructures: [APIBlueprintDataStructure]
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintDataStructures {
//        return try APIBlueprintDataStructures(
//            dataStructures: APIBlueprintDataStructure.decodeElements(e))
//    }
//}
//
//// MARK: - Elements
//
//struct APIBlueprintCopy: APIBlueprintElementDecodable {
//    static let elementName = "copy"
//    let text: String
//    static func decode(_ e: Extractor) throws -> APIBlueprintCopy {
//        return try APIBlueprintCopy(text: e <| "content")
//    }
//}
//
//struct APIBlueprintTransition: APIBlueprintElementDecodable {
//    static let elementName = "transition"
//
//    let meta: APIBlueprintMeta?
//    var title: String? {return meta?.title}
//
//    let copy: APIBlueprintCopy?
//
//    let attributes: Attributes?
//    func href(request: Transaction.Request) throws -> String {
//        guard let href = request.href ?? attributes?.href else { throw ConversionError.undefined }
//        return href
//    }
//    let httpTransactions: [Transaction]
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintTransition {
//        return try APIBlueprintTransition(
//            meta: e <|? "meta",
//            copy: APIBlueprintCopy.decodeElementOptional(e),
//            attributes: e <|? "attributes",
//            httpTransactions: Transaction.decodeElements(e))
//    }
//
//    struct Attributes: Himotoki.Decodable {
//        let href: String?
//        let hrefVariables: HrefVariables?
//
//        static func decode(_ e: Extractor) throws -> Attributes {
//            return try Attributes(
//                href: e <|? "href",
//                hrefVariables: HrefVariables.decodeElementOptional(e, key: HrefVariables.elementName))
//        }
//
//        struct HrefVariables: APIBlueprintElementDecodable {
//            static let elementName = "hrefVariables"
//            let members: [APIBlueprintMember]
//            static func decode(_ e: Extractor) throws -> HrefVariables {
//                return try HrefVariables(members: APIBlueprintMember.decodeElements(e))
//            }
//        }
//    }
//
//    struct Transaction: APIBlueprintElementDecodable {
//        static let elementName = "httpTransaction"
//        let request: Request // currently supports single request per transaction
//        let responses: [Response]
//
//        static func decode(_ e: Extractor) throws -> Transaction {
//            return try Transaction(
//                request: Request.decodeElement(e),
//                responses: Response.decodeElements(e))
//        }
//
//        struct Request: APIBlueprintElementDecodable {
//            static let elementName = "httpRequest"
//            let method: String
//            let href: String? // nil indicates transition.href should be used
//            let headers: Headers?
//            let dataStructure: APIBlueprintDataStructure?
//
//            static func decode(_ e: Extractor) throws -> Request {
//                return try Request(
//                    method:  e <| ["attributes", "method"],
//                    href:  e <|? ["attributes", "href"],
//                    headers: e <|? ["attributes", "headers"],
//                    dataStructure: {do {return try APIBlueprintDataStructure.decodeElement(e)} catch DecodeError.custom {return nil}}())
//            }
//        }
//
//        struct Response: APIBlueprintElementDecodable {
//            static let elementName = "httpResponse"
//            let statusCode: Int // multiple Responses are identified by pair (statusCode, contentType) for a single Request
//            let headers: Headers?
//            let contentType: String?
//            let dataStructure: APIBlueprintDataStructure?
//
//            static func decode(_ e: Extractor) throws -> Response {
//                guard let statusCode = ((try e <|? ["attributes", "statusCode"]).flatMap {Int($0)}) else {
//                    throw ConversionError.undefined
//                }
//                let headers: Headers? = try e <|? ["attributes", "headers"]
//
//                return try Response(
//                    statusCode: statusCode,
//                    headers: headers,
//                    contentType: headers?.contentType?.value,
//                    dataStructure: APIBlueprintDataStructure.decodeElementOptional(e))
//            }
//        }
//
//        struct Headers: Himotoki.Decodable {
//            static let elementName = "httpHeaders"
//            let members: [APIBlueprintMember]
//            static func decode(_ e: Extractor) throws -> Headers {
//                return try Headers(members: APIBlueprintMember.decodeElements(e))
//            }
//            var dictionary: [String: String] {
//                var d = [String: String]()
//                members.forEach {
//                    guard $0.content.name != "Content-Type" else { return } // ignore Content-Type
//                    d[$0.content.name] = $0.content.value
//                }
//                return d
//            }
//            var contentType: APIBlueprintMemberContent? {
//                return members.map {$0.content}.first {$0.name == "Content-Type"}
//            }
//        }
//    }
//}
//
//struct APIBlueprintElement: Himotoki.Decodable {
//    let element: String
//    let meta: APIBlueprintMeta?
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintElement {
//        return try APIBlueprintElement(
//            element: e <| "element",
//            meta: e <|? "meta")
//    }
//}
//
//struct APIBlueprintMeta: Himotoki.Decodable {
//    let classes: [String]?
//    let id: String?
//    let description: String?
//    let title: String?
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintMeta {
//        return try APIBlueprintMeta(
//            classes: e <||? "classes",
//            id: e <|? "id",
//            description: e <|? "description",
//            title: e <|? "title")
//    }
//}
//
//struct APIBlueprintMember: APIBlueprintElementDecodable {
//    static let elementName = "member"
//    let meta: APIBlueprintMeta?
//    let typeAttributes: [String]?
//    var required: Bool {return typeAttributes?.contains("required") == true}
//    let content: APIBlueprintMemberContent
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintMember {
//        return try APIBlueprintMember(
//            meta: e <|? "meta",
//            typeAttributes: e <||? ["attributes", "typeAttributes"],
//            content: e <| "content")
//    }
//}
//
//struct APIBlueprintStringElement: APIBlueprintElementDecodable {
//    static let elementName = "string"
//    let value: String
//    static func decode(_ e: Extractor) throws -> APIBlueprintStringElement {
//        return try APIBlueprintStringElement(value: e <| "content")
//    }
//}
//
//struct APIBlueprintMemberContent: Himotoki.Decodable {
//    let name: String
//    let type: APIBlueprintMemberType
//    let value: String? // value, 42, [value], ...
//    let displayValue: String? // "value", 42, ["value"], ...
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintMemberContent {
//        let value: String?
//        let displayValue: String?
//        let type: APIBlueprintMemberType = try e <| "value"
//        switch type {
//        case .exact("string"):
//            let string: String? = try e <|? ["value", "content"]
//            value = string
//            displayValue = value.map {"\"" + $0 + "\""}
//        case .exact("number"):
//            let number: Int? = try e <|? ["value", "content"]
//            value = number.map {String($0)}
//            displayValue = value
//        case .array:
//            let contents = try StringArrayValue.decodeElement(e, key: "value").content
//            value = "[" + contents.map {$0.value}.joined(separator: ", ") + "]"
//            displayValue = "[" + contents.map {"\"" + $0.value + "\""}.joined(separator: ", ") + "]"
//        case .exact("enum"):
//            throw ConversionError.notSupported("\(type) at \(self)")
//        case .indirect:
//            throw ConversionError.undefined
//        case let .exact(id):
//            value = id
//            displayValue = value
//        }
//
//        return try APIBlueprintMemberContent(
//            name: e <| ["key", "content"],
//            type: type,
//            value: value,
//            displayValue: displayValue)
//    }
//
//    struct StringArrayValue: APIBlueprintElementDecodable {
//        static let elementName = "array"
//        let content: [APIBlueprintStringElement]
//        static func decode(_ e: Extractor) throws -> StringArrayValue {
//            return try StringArrayValue(content: APIBlueprintStringElement.decodeElements(e))
//        }
//    }
//}
//
//enum APIBlueprintMemberType: Himotoki.Decodable {
//    case exact(String)
//    case array(String?)
//    case indirect(String)
//
//    var isArray: Bool {
//        switch self {
//        case .exact: return false
//        case .array: return true
//        case .indirect: return false
//        }
//    }
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintMemberType {
//        let raw: String = try e <| "element"
//        switch raw {
//        case "array":
//            let contentTypes: [APIBlueprintAnyElement] = try e <|| "content"
//            return .array(contentTypes.first?.element)
//        default:
//            return .exact(raw)
//        }
//    }
//}
//
//struct APIBlueprintAnyElement: Himotoki.Decodable {
//    let element: String
//    static func decode(_ e: Extractor) throws -> APIBlueprintAnyElement {
//        return try APIBlueprintAnyElement(element: e <| "element")
//    }
//}
//
//enum APIBlueprintDataStructure: APIBlueprintElementDecodable {
//    static let elementName = "dataStructure"
//
//    case named(id: String, members: [APIBlueprintMember])
//    case anonymous(members: [APIBlueprintMember])
//    case ref(id: String)
//
//    var id: String? {
//        switch self {
//        case .named(let id, _): return id
//        case .ref(let id): return id
//        case .anonymous: return nil
//        }
//    }
//
//    var rawType: String {
//        switch self {
//        case .named(let id, _): return id
//        case .ref(let id): return id
//        case .anonymous: return "object"
//        }
//    }
//
//    var members: [APIBlueprintMember] {
//        switch self {
//        case .named(_, let members): return members
//        case .anonymous(let members): return members
//        case .ref: return []
//        }
//    }
//
//    static func decode(_ e: Extractor) throws -> APIBlueprintDataStructure {
//        guard let content: APIBlueprintElement = try (e <|| "content").first else {
//            throw ConversionError.unknownDataStructure
//        }
//        if let id = content.meta?.id {
//            return .named(id: id, members: try APIBlueprintMember.decodeElementsOfContents(e))
//        }
//        if content.element == "object" {
//            return .anonymous(members: try APIBlueprintMember.decodeElementsOfContents(e))
//        }
//        return .ref(id: content.element)
//    }
//}
//
//struct APIBluprintAnnotation: APIBlueprintElementDecodable {
//    static let elementName = "annotation"
//
//    static func decode(_ e: Extractor) throws -> APIBluprintAnnotation {
//        return APIBluprintAnnotation()
//    }
//}
