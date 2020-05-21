import Foundation

enum APIElements {
    struct Meta: Codable, Equatable {
        var id: String?
        var ref: String?
        var classes: [String]?
        var title: String?
        var description: String?

        init(id: String? = nil, ref: String? = nil, classes: [String]? = nil, title: String? = nil, description: String? = nil) {
            self.id = id
            self.ref = ref
            self.classes = classes
            self.title = title
            self.description = description
        }
    }

    struct Attributes: Codable, Equatable {
        var meta: [Meta]?
    }
}

protocol TypedElement: Codable, Equatable {
    associatedtype ContentType: Codable
    static var elementName: String { get }
    var element: String { get set }
    var content: ContentType { get set }
}
extension TypedElement {
    static func decodeElementAndContent<CodingKeys: CodingKey>(from decoder: Decoder, elementKey: CodingKeys, contentKey: CodingKeys) throws -> (element: String, content: ContentType) {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let element = try container.decode(String.self, forKey: elementKey)
        guard element == Self.elementName else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [elementKey], debugDescription: "element \(Self.elementName) is expected but found: \(element)"))
        }
        let content = try container.decode(ContentType.self, forKey: contentKey)
        return (element, content)
    }

    func encode<CodingKeys: CodingKey>(to encoder: Encoder, elementKey: CodingKeys, contentKey: CodingKeys) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(element, forKey: elementKey)
        try container.encode(content, forKey: contentKey)
    }
}

protocol SimpleTypedElement: TypedElement {
    associatedtype CodingKeys = SimpleTypedElementCodingKeys
    init(element: String, content: ContentType)
}
enum SimpleTypedElementCodingKeys: CodingKey { case element, content }
extension SimpleTypedElement {
    init(from decoder: Decoder) throws {
        let ec = try Self.decodeElementAndContent(from: decoder, elementKey: SimpleTypedElementCodingKeys.element, contentKey: SimpleTypedElementCodingKeys.content)
        self.init(element: ec.element, content: ec.content)
    }
    func encode(to encoder: Encoder) throws {
        try encode(to: encoder, elementKey: SimpleTypedElementCodingKeys.element, contentKey: SimpleTypedElementCodingKeys.content)
    }
}

// MARK: -

typealias APIBlueprintAST = ParseResultElement

struct ParseResultElement: SimpleTypedElement {
    static let elementName = "parseResult"
    var element: String
    var content: [Content]

    var api: APICategoryElement? {
        content.lazy.compactMap {
            guard case let .api(x) = $0 else { return nil }
            return x
        }.first
    }

    enum Content: Codable, Equatable {
        case api(APICategoryElement)

        init(from decoder: Decoder) throws {
            self = .api(try APICategoryElement(from: decoder))
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .api(let e): try e.encode(to: encoder)
            }
        }
    }
}

struct CategoryElement: Codable {
    static let elementName = "category"
    var element: String
    var meta: APIElements.Meta?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
    }
}

struct APICategoryElement: TypedElement, Equatable {
    static let elementName = "category"
    static let className = "api"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.Attributes?
    var content: [Content]

    var resourceGroups: [ResourceGroupCategoryElement] {
        content.compactMap {
            guard case let .resourceGroup(x) = $0 else { return nil }
            return x
        }
    }

    var dataStructures: [DataStructureElement] {
        content.compactMap { content -> DataStructuresCategoryElement? in
            guard case let .dataStructures(x) = content else { return nil }
            return x
        }.flatMap {
            $0.content
        }
    }

    enum Content: Codable, Equatable {
        case copy(CopyElement)
        case resourceGroup(ResourceGroupCategoryElement)
        case dataStructures(DataStructuresCategoryElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case CopyElement.elementName:
                self = .copy(try CopyElement(from: decoder))
            case CategoryElement.elementName:
                let category = try CategoryElement(from: decoder)
                let classes = category.meta?.classes ?? []

                if classes.contains(ResourceGroupCategoryElement.className) {
                    self = .resourceGroup(try ResourceGroupCategoryElement(from: decoder))
                } else if classes.contains(DataStructuresCategoryElement.className) {
                    self = .dataStructures(try DataStructuresCategoryElement(from: decoder))
                } else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown category element classes found at \(decoder.codingPath): \(classes)"))
                }
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .copy(let e): try e.encode(to: encoder)
            case .resourceGroup(let e): try e.encode(to: encoder)
            case .dataStructures(let e): try e.encode(to: encoder)
            }
        }

        var element: String {
            switch self {
            case .copy(let e): return e.element
            case .resourceGroup(let e): return e.element
            case .dataStructures(let e): return e.element
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
        guard (self.meta?.classes ?? []).contains(Self.className) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.meta], debugDescription: "meta classes is expected to have \(Self.className) but found: \(self.meta?.classes ?? [])")) }
        self.attributes = try container.decodeIfPresent(APIElements.Attributes.self, forKey: .attributes)
        self.content = try container.decode([Content].self, forKey: .content)
    }
}

struct ResourceGroupCategoryElement: TypedElement {
    static let elementName = "category"
    static let className = "resourceGroup"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.Attributes?
    var content: [Content]

    var resources: [ResourceElement] {
        content.compactMap {
            guard case let .resource(x) = $0 else { return nil }
            return x
        }
    }

    enum Content: Codable, Equatable {
        case copy(CopyElement)
        case resource(ResourceElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case CopyElement.elementName:
                self = .copy(try CopyElement(from: decoder))
            case ResourceElement.elementName:
                self = .resource(try ResourceElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .copy(let e): try e.encode(to: encoder)
            case .resource(let e): try e.encode(to: encoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
        guard (self.meta?.classes ?? []).contains(Self.className) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.meta], debugDescription: "meta classes is expected to have \(Self.className) but found: \(self.meta?.classes ?? [])")) }
        self.attributes = try container.decodeIfPresent(APIElements.Attributes.self, forKey: .attributes)
        self.content = try container.decode([Content].self, forKey: .content)
    }
}

struct DataStructuresCategoryElement: TypedElement {
    static let elementName = "category"
    static let className = "dataStructures"
    var element: String
    var meta: APIElements.Meta?
    var attributes: APIElements.Attributes?
    var content: [DataStructureElement]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
        guard (self.meta?.classes ?? []).contains(Self.className) else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.meta], debugDescription: "meta classes is expected to have \(Self.className) but found: \(self.meta?.classes ?? [])")) }
        self.attributes = try container.decodeIfPresent(APIElements.Attributes.self, forKey: .attributes)
        self.content = try container.decode([DataStructureElement].self, forKey: .content)
    }
}

struct DataStructureElement: TypedElement {
    static let elementName = "dataStructure"
    var element: String
    var content: Content

    enum Content: Codable, Equatable {
        case named(id: String, members: [MemberElement], baseRef: String) // id = meta.id, baseRef = element
        case anonymous(members: [MemberElement]) // element = object but no id
        case ref(id: String) // id = element
        case array(id: String, contentRef: String) // element = array, contentRef = content.element

        var id: String? {
            switch self {
            case .named(id: let id, members: _, baseRef: _): return id
            case .anonymous: return nil
            case .ref(id: let id): return id
            case .array(id: let id, contentRef: _): return id
            }
        }
        var members: [MemberElement] {
            switch self {
            case .named(id: _, members: let members, baseRef: _): return members
            case .anonymous(members: let members): return members
            case .ref, .array: return []
            }
        }

        enum CodingKeys: String, CodingKey {
            case element, meta, content
        }

        private struct ArrayContent: Codable {
            var element: String
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            let meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
            if let id = meta?.id {
                if element == "array" {
                    let content = try container.decode([ArrayContent].self, forKey: .content)
                    guard content.count == 1, let ref = content.first?.element else {
                        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.content], debugDescription: "unexpected non-single type array content: \(content)"))
                    }
                    self = .array(id: id, contentRef: ref)
                } else {
                    self = .named(
                        id: id,
                        members: try container.decode([MemberElement].self, forKey: .content),
                        baseRef: element)
                }
            } else if element == "object" {
                self = .anonymous(members: try container.decode([MemberElement].self, forKey: .content))
            } else {
                self = .ref(id: element)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .named(id: let id, members: let members, baseRef: let baseRef):
                try container.encode(baseRef, forKey: .element)
                try container.encode(APIElements.Meta(id: id), forKey: .meta)
                try container.encode(members, forKey: .content)
            case .anonymous(members: let members):
                try container.encode("object", forKey: .element)
                try container.encode(members, forKey: .content)
            case .ref(id: let id):
                try container.encode(id, forKey: .element)
            case .array(id: let id, contentRef: let contentRef):
                try container.encode(id, forKey: .element)
                try container.encode(["element": contentRef], forKey: .content)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        let contents = try container.decode([Content].self, forKey: .content)
        guard contents.count == 1, let content = contents.first else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.content], debugDescription: "unexpected single array content: \(contents)"))
        }
        self.content = content
    }
}

struct MemberElement: TypedElement {
    static let elementName = "member"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes?
    var content: Content

    var description: String? {
        meta?.description
    }

    var name: String {content.key.content}
    var required: Bool {attributes?.typeAttributes?.contains("required") == true}

    struct Attributes: Codable, Equatable {
        var typeAttributes: [String]?
    }

    struct Content: Codable, Equatable {
        var key: StringElement
        var value: Value

        var displayValue: String? {
            switch value {
            case .string(let v): return v.map {"\"" + $0 + "\""}
            case .number(let v): return v.map {String($0)}
            case .array(let t): return t.map {"[" + $0 + "]"}
            case .id(let v): return v
            case .indirect(let t): return t
            }
        }

        enum Value: Codable, Equatable {
            case string(String?)
            case number(Double?)
            case array(String?)
            case id(String)
//            case `enum`([String]) // unsupported
            case indirect(String)

            enum CodingKeys: CodingKey {
                case element, content
            }

            var isArray: Bool {
                switch self {
                case .array: return true
                case .string, .number, .id, .indirect: return false
                }
            }

            init(from decoder: Decoder) throws {
                let container = try! decoder.container(keyedBy: CodingKeys.self)
                let element = try! container.decode(String.self, forKey: .element)
                switch element {
                case StringElement.elementName: self = .string(try container.decodeIfPresent(String.self, forKey: .content))
                case NumberElement.elementName: self = .number(try container.decodeIfPresent(Double.self, forKey: .content))
                case "array":
                    let content = try container.decodeIfPresent([AnyElement].self, forKey: .content)
                    self = .array(content?.first?.element)
//                case "enum": self = .enum([...])
                default: self = .id(element)
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .string(let v):
                    try container.encode(StringElement.elementName, forKey: .element)
                    try container.encode(v, forKey: .content)
                case .number(let v):
                    try container.encode(NumberElement.elementName, forKey: .element)
                    try container.encode(v, forKey: .content)
                case .array(let v):
                    try container.encode("array", forKey: .element)
                    try container.encodeIfPresent(v.map {AnyElement(element: $0)}, forKey: .content)
                case .id(let v):
                    try container.encode(v, forKey: .element)
                case .indirect(let t):
                    try container.encode(t, forKey: .element)
                }
            }
        }
    }
}
extension Dictionary where Key == String, Value == String {
    init(_ members: [MemberElement]) {
        self = members.reduce(into: [:]) {
            guard case let .string(s) = $1.content.value else { return }
            $0[$1.name] = s
        }
    }
}

struct AnyElement: Codable, Equatable {
    var element: String
}

struct StringElement: SimpleTypedElement {
    static let elementName = "string"
    var element: String
    var content: String
}

struct NumberElement: SimpleTypedElement {
    static let elementName = "number"
    var element: String
    var content: Double
}

struct CopyElement: SimpleTypedElement {
    static var elementName = "copy"
    var element: String
    var content: String
}

struct ResourceElement: TypedElement {
    static let elementName = "resource"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes
    var content: [Content]

    var copy: CopyElement? {
        content.lazy.compactMap {
            guard case let .copy(x) = $0 else { return nil }
            return x
        }.first
    }

    var transitions: [TransitionElement] {
        content.reduce(into: []) {
            guard case let .transition(x) = $1 else { return }
            $0.append(x)
        }
    }
    
    var dataStructures: [DataStructureElement] {
        content.reduce(into: []) {
            guard case let .dataStructure(x) = $1 else { return }
            $0.append(x)
        }
    }

    struct Attributes: Codable, Equatable {
        var href: String
    }

    enum Content: Codable, Equatable {
        case copy(CopyElement)
        case transition(TransitionElement)
        case dataStructure(DataStructureElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case CopyElement.elementName:
                self = .copy(try CopyElement(from: decoder))
            case TransitionElement.elementName:
                self = .transition(try TransitionElement(from: decoder))
            case DataStructureElement.elementName:
                self = .dataStructure(try DataStructureElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .copy(let e): try e.encode(to: encoder)
            case .transition(let e): try e.encode(to: encoder)
            case .dataStructure(let e): try e.encode(to: encoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.meta = try container.decodeIfPresent(APIElements.Meta.self, forKey: .meta)
        self.attributes = try container.decode(Attributes.self, forKey: .attributes)
        self.content = try container.decode([Content].self, forKey: .content)
    }
}
extension ResourceElement {
    func href(transition: TransitionElement, request: HTTPRequestElement) -> String {
        request.attributes.href ?? transition.attributes?.href ?? attributes.href
    }
}

struct TransitionElement: TypedElement {
    static let elementName = "transition"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes?
    var content: [Content]

    var copy: CopyElement? {
        content.lazy.compactMap {
            guard case let .copy(x) = $0 else { return nil }
            return x
        }.first
    }

    var transactions: [HTTPTransactionElement] {
        content.reduce(into: []) {
            guard case let .transaction(x) = $1 else { return }
            $0.append(x)
        }
    }

    struct Attributes: Codable, Equatable {
        var href: String?
        var hrefVariables: HrefVariables?
        struct HrefVariables: SimpleTypedElement {
            static let elementName = "hrefVariables"
            var element: String
            var content: [MemberElement]
        }
    }

    enum Content: Codable, Equatable {
        case copy(CopyElement)
        case transaction(HTTPTransactionElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case CopyElement.elementName:
                self = .copy(try CopyElement(from: decoder))
            case HTTPTransactionElement.elementName:
                self = .transaction(try HTTPTransactionElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .copy(let e): try e.encode(to: encoder)
            case .transaction(let e): try e.encode(to: encoder)
            }
        }
    }
}

struct HTTPTransactionElement: SimpleTypedElement {
    static let elementName = "httpTransaction"
    var element: String
    var content: [RequestResponse]

    /// NOTE: currently supports single request per transaction
    var request: HTTPRequestElement? {
        content.lazy.compactMap {
            guard case let .httpRequest(x) = $0 else { return nil }
            return x
        }.first
    }
    var responses: [HTTPResponseElement] {
        content.reduce(into: []) {
            guard case let .httpResponse(x) = $1 else { return }
            $0.append(x)
        }
    }

    enum RequestResponse: Codable, Equatable {
        case httpRequest(HTTPRequestElement)
        case httpResponse(HTTPResponseElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case HTTPRequestElement.elementName: self = .httpRequest(try HTTPRequestElement(from: decoder))
            case HTTPResponseElement.elementName: self = .httpResponse(try HTTPResponseElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .httpRequest(let e): try e.encode(to: encoder)
            case .httpResponse(let e): try e.encode(to: encoder)
            }
        }
    }
}

struct HTTPRequestElement: TypedElement {
    static let elementName = "httpRequest"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes
    var content: [Content]

    var dataStructure: DataStructureElement? {
        content.lazy.compactMap {
            guard case let .dataStructure(x) = $0 else { return nil }
            return x
        }.first
    }

    struct Attributes: Codable, Equatable {
        var method: Method
        var href: String? // nil indicates transition.href should be used
        var headers: HTTPHeadersElement?
        enum Method: String, Codable, Equatable {
            case GET
            case POST
            case PUT
            case DELETE
            case PATCH
        }
    }

    enum Content: Codable, Equatable {
        case asset(AssetElement)
        case dataStructure(DataStructureElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case AssetElement.elementName: self = .asset(try AssetElement(from: decoder))
            case DataStructureElement.elementName: self = .dataStructure(try DataStructureElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .asset(let e): try e.encode(to: encoder)
            case .dataStructure(let e): try e.encode(to: encoder)
            }
        }
    }
}

struct HTTPResponseElement: TypedElement {
    static let elementName = "httpResponse"
    var element: String
    var attributes: Attributes
    var content: [Content]

    var dataStructure: DataStructureElement? {
        content.lazy.compactMap {
            guard case let .dataStructure(x) = $0 else { return nil }
            return x
        }.first
    }

    struct Attributes: Codable, Equatable {
        var statusCode: Int
        var headers: HTTPHeadersElement?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let statusCode = Int(try container.decode(String.self, forKey: .statusCode)) else {
                throw DecodingError.typeMismatch(Int.self, DecodingError.Context(codingPath: container.codingPath + [CodingKeys.statusCode], debugDescription: "statusCode is expected a String representing an Int"))
            }
            self.statusCode = statusCode
            self.headers = try container.decodeIfPresent(HTTPHeadersElement.self, forKey: .headers)
        }
    }

    enum Content: Codable, Equatable {
        case copy(CopyElement)
        case asset(AssetElement)
        case dataStructure(DataStructureElement)

        enum CodingKeys: String, CodingKey {
            case element
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let element = try container.decode(String.self, forKey: .element)
            switch element {
            case CopyElement.elementName: self = .copy(try CopyElement(from: decoder))
            case AssetElement.elementName: self = .asset(try AssetElement(from: decoder))
            case DataStructureElement.elementName: self = .dataStructure(try DataStructureElement(from: decoder))
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "unknown element: \(element)"))
            }
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .copy(let e): try e.encode(to: encoder)
            case .asset(let e): try e.encode(to: encoder)
            case .dataStructure(let e): try e.encode(to: encoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.element = try container.decode(String.self, forKey: .element)
        guard self.element == Self.elementName else { throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath + [CodingKeys.element], debugDescription: "element \(Self.elementName) is expected but found: \(self.element)")) }
        self.attributes = try container.decode(Attributes.self, forKey: .attributes)
        self.content = try container.decode([Content].self, forKey: .content)
    }
}

struct HTTPHeadersElement: SimpleTypedElement {
    static let elementName = "httpHeaders"
    var element: String
    var content: [MemberElement]
    var contentType: String? {
        guard case let .string(x) = (content.first {$0.name == "Content-Type"}?.content.value) else { return nil }
        return x
    }
}

struct AssetElement: TypedElement {
    static let elementName = "asset"
    var element: String
    var meta: APIElements.Meta?
    var attributes: Attributes
    var content: String

    struct Attributes: Codable, Equatable {
        var contentType: String?
    }
}
