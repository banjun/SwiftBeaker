import Foundation
import Stencil

typealias SwiftCode = (local: String, global: String)

protocol SwiftConvertible {
    associatedtype Context
    func swift(_ context: Context, public: Bool) throws -> SwiftCode
}

fileprivate extension String {
    func indented(by level: Int) -> String {
        return components(separatedBy: "\n").map {Array(repeating: " ", count: level).joined() + $0}.joined(separator: "\n")
    }
}

fileprivate extension String {
    func swiftKeywordsEscaped() -> String {
        let keywords = ["Error"]
        return keywords.contains(self) ? self + "_" : self
    }

    func swiftTypeMapped() -> String {
        let typeMap = ["string": "String",
                       "number": "Int",
                       "enum": "Int",
                       "boolean": "Bool"]
        return typeMap[self] ?? self
    }

    func swiftIdentifierized() -> String {
        let cs = CharacterSet(charactersIn: " _/{?,}-")
        return components(separatedBy: cs).joined(separator: "_")
    }

    func docCommentPrefixed() -> String {
        return components(separatedBy: .newlines).map {"/// " + $0}.joined(separator: "\n")
    }
}

private let stencilExtension: Extension = {
    let ext = Extension()
    ext.registerFilter("escapeKeyword") { (value: Any?) in
        let keywords = ["var", "let", "where", "operator", "throws"]
        guard let s = value as? String,
            keywords.contains(s) else { return value }
        return "`" + s + "`"
    }
    return ext
}()
private let stencilEnvironment = Environment(extensions: [stencilExtension])

extension DataStructureElement.Content: SwiftConvertible {
    func swift(_ name: String? = nil, public: Bool) throws -> SwiftCode {
        let localDSTemplate = Template(templateString: """
{{ public }}struct {{ name }}: Codable { {% for v in vars %}
    {{ v.doc }}
    {{ public }}var {{ v.name|escapeKeyword }}: {{ v.type }}{% endfor %}{% if publicMemberwiseInit %}

    // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}
    public init({% for v in vars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {
    {% for v in vars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}
    {% endfor %}}{% endif %}
}
""", environment: stencilEnvironment)
        guard let name = ((name ?? id).map {$0.swiftKeywordsEscaped()}) else { throw ConversionError.undefined }
        let vars: [[String: Any]] = try members
            .map {try $0.memberAvoidingSwiftRecursiveStruct(parentTypes: [name])}
            .map { m in
                let optional = !m.required
                let optionalSuffix = optional ? "?" : ""

                return [
                    "name": m.swiftName,
                    "type": m.swiftType,
                    "optional": optional,
                    "doc": m.swiftDoc,
                    "decoder": (m.content.value.isArray ? "<||" : "<|") + optionalSuffix]}

        let localName = name.components(separatedBy: ".").last ?? name
        return (local: try localDSTemplate.render(["public": `public` ? "public " : "",
                                                   "publicMemberwiseInit": `public`,
                                                   "name": localName.swiftIdentifierized(),
                                                   "vars": vars]),
                global: "")
    }
}

extension TransitionElement: SwiftConvertible {
    func swift(_ resource: ResourceElement, public: Bool) throws -> SwiftCode {
        var globalExtensionCode = ""
        let request = transactions.first!.request!
        let requestTypeName = try swiftRequestTypeName(request: request, resource: resource)
        let href = resource.href(transition: self, request: request)
        let otherTransitions = resource.transitions

        func allResponses(method: String) -> [HTTPResponseElement] {
            otherTransitions
                .flatMap {t in t.transactions.map {(transition: t, transaction: $0)}}
                .filter {$0.transaction.request?.attributes.method.content.rawValue == method &&
                    resource.href(transition: $0.transition, request: $0.transaction.request!) == href}
                .flatMap {$0.transaction.responses}
        }

        let trTemplate = Template(templateString: """
{{ copy }}
{{ public }}struct {{ name }}: {{ extensions|join:", " }} {
    {{ public }}let baseURL: URL
    {{ public }}var method: HTTPMethod {return {{ method }}}
{% for v in pathVars %}{% if forloop.first %}
    {{ public }}let path = "" // see intercept(urlRequest:)
    static let pathTemplate: URITemplate = "{{ path }}"
    {{ public }}var pathVars: PathVars
    {{ public }}struct PathVars: URITemplateContextConvertible {
{% endif %}        {{ v.doc }}
        {{ public }}var {{ v.name|escapeKeyword }}: {{ v.type }}{% if forloop.last %}{% if publicMemberwiseInit %}

        // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}
        public init({% for v in pathVars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {
        {% for v in pathVars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}
        {% endfor %}}{% endif %}
    }{% else %}
{% endif %}{% empty %}
    {{ public }}var path: String {return "{{ path }}"}{% endfor %}
{% if paramType %}
    {{ public }}let param: {{ paramType }}
    {{ public }}var bodyParameters: BodyParameters? {% if paramType == "String" %}{return TextBodyParameters(contentType: "{{ paramContentType }}", content: param)}{% else %}{
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? JSONBodyParameters(JSONObject: JSONSerialization.jsonObject(with: encoder.encode(param)))
    }
{% endif %}{% endif %}{% if structParam %}{{ structParam }}{% endif %}
    {{ public }}enum Responses {
{% for r in responseCases %}        case {{ r.case }}({{ r.type }}){% if r.innerType %}
{{ r.innerType }}{% endif %}
{% endfor %}    }
{% if headerVars %}
    {{ public }}var headerFields: [String: String] {return headerVars.context}
    {{ public }}var headerVars: HeaderVars
    {{ public }}struct HeaderVars: URITemplateContextConvertible {
{% for v in headerVars %}        {{ v.doc }}
        {{ public }}var {{ v.name }}: {{ v.type }}
{% endfor %}
        enum CodingKeys: String, CodingKey {
{% for v in headerVars %}            case {{ v.name }} = "{{ v.key }}"
{% endfor %}        }{% if publicMemberwiseInit %}
        // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}
        public init({% for v in headerVars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {
        {% for v in headerVars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}
        {% endfor %}}{% endif %}
    }
{% endif %}{% if publicMemberwiseInit %}
    // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}
    public init(baseURL: URL{% if pathVars %}, pathVars: PathVars{% endif %}{% if paramType %}, param: {{ paramType }}{% endif %}{% if headerVars %}, headerVars: HeaderVars{% endif %}) {
        self.baseURL = baseURL{% if pathVars %}\n        self.pathVars = pathVars{% endif %}{% if paramType %}\n        self.param = param{% endif %}{% if headerVars %}\n        self.headerVars = headerVars{% endif %}
    }
{% endif %}
    {{ public }}func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Responses {
        let contentType = contentMIMEType(in: urlResponse)
        switch (urlResponse.statusCode, contentType) {
{% for r in responseCases %}        case ({{ r.statusCode }}, {{ r.contentType }}):
            return .{{ r.case }}({{ r.decode }})
{% endfor %}        default:
            throw ResponseError.undefined(urlResponse.statusCode, contentType)
        }
    }
}
""", environment: stencilEnvironment)
        let siblingResponses = allResponses(method: request.attributes.method.content.rawValue)
        let responseCases = try siblingResponses.map { r -> [String: Any] in
            let type: String
            let contentTypeEscaped = (r.attributes.headers?.contentType ?? "").replacingOccurrences(of: "/", with: "_")
            let innerType: (local: String, global: String)?
            switch r.dataStructure?.content {
            case .anonymous?:
                type = "Response\(r.attributes.statusCode)_\(contentTypeEscaped)"
                innerType = try r.dataStructure!.content.swift("\(requestTypeName).Responses.\(type)", public: `public`)
                _ = innerType.map {globalExtensionCode += $0.global}
            case let .ref(id: id)?:
                // external type (reference to type defined in Data Structures)
                type = id
                innerType = nil
            case nil:
                switch r.attributes.headers?.contentType {
                case "text/plain"?, "text/html"?:
                    type = "String"
                    innerType = nil
                default:
                    type = "Void"
                    innerType = nil
                }
            case .named?:
                throw ConversionError.unknownDataStructure
            case .array?:
                throw ConversionError.unknownDataStructure
            }
            var context: [String: String] = [
                "statusCode": String(r.attributes.statusCode),
                "contentType": r.attributes.headers?.contentType.map {"\"\($0)\"?"} ?? "_",
                "case": "http\(r.attributes.statusCode)_\(contentTypeEscaped)",
                "type": type,
                "decode": {
                    switch r.attributes.headers?.contentType {
                    case nil, "application/json"?:
                        return "try decodeJSON(from: object, urlResponse: urlResponse)"
                    case "text/html"?, "text/plain"?:
                        return "try string(from: object, urlResponse: urlResponse)"
                    default:
                        return ""
                    }
                }()]
            if let innerType = innerType {
                context["innerType"] = innerType.local.indented(by: 8)
            }
            return context
        }

        var context: [String: Any] = [
            "public": `public` ? "public " : "",
            "publicMemberwiseInit": `public`,
            "name": requestTypeName,
            "responseCases": responseCases,
            "method": "." + request.attributes.method.content.rawValue.lowercased(),
            "path": href
        ]
        if let hrefVariables = attributes?.hrefVariables {
            let pathVars: [[String: Any]] = hrefVariables.content.map {
                ["key": $0.name,
                 "name": $0.swiftName,
                 "type": $0.swiftType,
                 "doc": $0.swiftDoc,
                 "optional": !$0.required]
            }
            context["extensions"] = ["APIBlueprintRequest", "URITemplateRequest"]
            context["pathVars"] = pathVars
        } else {
            context["extensions"] = ["APIBlueprintRequest"]
        }
        if let headers = (request.attributes.headers.map {[String: String]($0.content)}), !headers.isEmpty {
            let headerVars = headers.filter {$0.key != "Content-Type"}.map { (k, v) in
                ["key": k,
                 "name": k.lowercased().swiftIdentifierized(),
                 "type": "String",
                 "doc": v.docCommentPrefixed()]
            }
            context["headerVars"] = headerVars
        }
        switch request.dataStructure?.content {
        case let .anonymous(members)?:
            // inner type
            let ds = DataStructureElement.Content.anonymous(members: members)
            context["paramType"] = "Param"
            let s = try ds.swift("\(requestTypeName).Param", public: `public`)
            globalExtensionCode += s.global
            context["structParam"] = s.local.indented(by: 4)
        case let .ref(id: id)?:
            let ds = DataStructureElement.Content.ref(id: id)
            // external type (reference to type defined in Data Structures)
            context["paramType"] = ds.id
        case .named?:
            throw ConversionError.notSupported("named DataStructure definition in a request param")
        case .array?:
            throw ConversionError.notSupported("array DataStructure definition in a request param")
        case nil:
            if let requestContentType = request.attributes.headers?.contentType, requestContentType.hasPrefix("text/") {
                context["paramType"] = "String"
                context["paramContentType"] = requestContentType
            }
        }
        context["copy"] = copy?.content.docCommentPrefixed()

        return try (local: trTemplate.render(context), global: globalExtensionCode)
    }


    func swiftRequestTypeName(request: HTTPRequestElement, resource: ResourceElement) throws -> String {
        if let title = meta?.title?.content, let first = title.first {
            return (String(first).uppercased() + String(title.dropFirst())).swiftIdentifierized()
        } else {
            return (request.attributes.method.content.rawValue + "_" + resource.href(transition: self, request: request)).swiftIdentifierized()
        }
    }
}

extension MemberElement {
    var swiftName: String {return name.swiftIdentifierized()}
    var swiftType: String {
        let name: String
        switch content.value {
        case .string:
            name = "string".swiftTypeMapped().swiftKeywordsEscaped()
        case .number:
            name = "number".swiftTypeMapped().swiftKeywordsEscaped()
        case .array(let t):
            name = "[" + (t.map {$0.swiftTypeMapped().swiftKeywordsEscaped()} ?? "Any") + "]"
        case .id(let t):
            name = t.swiftTypeMapped().swiftKeywordsEscaped()
            // TODO: support indirect recursion
        case .indirect(let t):
            name = "Indirect<\(t)>"
        }
        return name + (required ? "" : "?")
    }
    var swiftDoc: String {return [meta?.description?.content, content.displayValue.map {" ex. " + $0}]
        .compactMap {$0}
        .joined(separator: " ")
        .docCommentPrefixed()}

    func memberAvoidingSwiftRecursiveStruct(parentTypes: [String]) throws -> MemberElement {
        let recursive = parentTypes.contains {
            if case .id($0) = content.value { return true } // currently support simple recursions
            return false
        }
        guard recursive else { return self }
        guard !required else {
            throw ConversionError.notSupported("recursive data structure with required param")
        }
        guard case let .id(exactType) = content.value else {
            throw ConversionError.notSupported("recursive data structure with compound param")
        }

        return MemberElement(
            element: element,
            meta: meta,
            attributes: Attributes(typeAttributes: attributes?.typeAttributes.map {
                ArrayElement<StringElement>(element: ArrayElement<StringElement>.elementName, content: $0.content.filter {$0.content != "required"})}),
            content: .init(
                key: content.key,
                value: .indirect(exactType)))
    }
}
