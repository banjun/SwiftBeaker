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

extension APIBlueprintDataStructure: SwiftConvertible {
    func swift(_ name: String? = nil, public: Bool) throws -> SwiftCode {
        let localDSTemplate = Template(templateString: ["{{ public }}struct {{ name }} { {% for v in vars %}",
                                                        "    {{ v.doc }}",
                                                        "    {{ public }}var {{ v.name|escapeKeyword }}: {{ v.type }}{% endfor %}{% if publicMemberwiseInit %}",
                                                        "",
                                                        "    // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}",
                                                        "    public init({% for v in vars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {",
                                                        "    {% for v in vars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}",
                                                        "    {% endfor %}}{% endif %}",
                                                        "}\n"].joined(separator: "\n"), environment: stencilEnvironment)
        let globalDSTemplate = Template(templateString: ["extension {{ fqn }}: Decodable {",
                                                         "    {{ public }}static func decode(_ e: Extractor) throws -> {{ fqn }} {",
                                                         "        return try self.init({% for v in vars %}",
                                                         "            {{ v.name }}: e {{ v.decoder }} \"{{ v.name }}\"{% if not forloop.last %},{% endif %}{% endfor %}",
                                                         "        )",
                                                         "    }",
                                                         "}",
                                                         "extension {{ fqn }}: DataStructureType {",
                                                         "    {{ public }}var jsonBodyParametersObject: Any {",
                                                         "        var j: [String: Any] = [:]",
                                                         "{% for v in vars %}        j[\"{{ v.name }}\"] = {{ v.name|escapeKeyword }}{% if v.optional %}?{% endif %}.jsonBodyParametersObject\n{% endfor %}        return j",
                                                         "    }",
                                                         "}\n"].joined(separator: "\n"), environment: stencilEnvironment)

        guard let name = ((name ?? id).map {$0.swiftKeywordsEscaped()}) else { throw ConversionError.undefined }
        let vars: [[String: Any]] = members.map { m in
            let optional = !m.required
            let optionalSuffix = optional ? "?" : ""
            return [
                "name": m.swiftName,
                "type": m.swiftType,
                "optional": optional,
                "doc": m.swiftDoc,
                "decoder": (m.content.type.isArray ? "<||" : "<|") + optionalSuffix]}

        let localName = name.components(separatedBy: ".").last ?? name
        return (local: try localDSTemplate.render(["public": `public` ? "public " : "",
                                                   "publicMemberwiseInit": `public`,
                                                   "name": localName.swiftIdentifierized(),
                                                   "vars": vars]),
                global: try globalDSTemplate.render(["public": `public` ? "public " : "",
                                                     "name": localName.swiftIdentifierized(),
                                                     "fqn": name.components(separatedBy: ".").map {$0.swiftIdentifierized()}.joined(separator: "."),
                                                     "vars": vars]))
    }
}

extension APIBlueprintTransition: SwiftConvertible {
    func swift(_ resource: APIBlueprintResourceGroup.Resource, public: Bool) throws -> SwiftCode {
        var globalExtensionCode = ""
        let request = httpTransactions.first!.request
        let requestTypeName = try swiftRequestTypeName(request: request, resource: resource)
        let href = try resource.href(transition: self, request: request)
        let otherTransitions = resource.transitions

        func allResponses(method: String) throws -> [APIBlueprintTransition.Transaction.Response] {
            return try otherTransitions
                .flatMap {t in t.httpTransactions.map {(transition: t, transaction: $0)}}
                .filter {try $0.transaction.request.method == method &&
                    resource.href(transition: $0.transition, request: $0.transaction.request) == href}
                .flatMap {$0.transaction.responses}
        }

        let trTemplate = Template(templateString: ["{{ copy }}",
                                                   "{{ public }}struct {{ name }}: {{ extensions|join:\", \" }} {",
                                                   "    {{ public }}let baseURL: URL",
                                                   "    {{ public }}var method: HTTPMethod {return {{ method }}}",
                                                   "{% for v in pathVars %}{% if forloop.first %}",
                                                   "    {{ public }}let path = \"\" // see intercept(urlRequest:)",
                                                   "    static let pathTemplate: URITemplate = \"{{ path }}\"",
                                                   "    {{ public }}var pathVars: PathVars",
                                                   "    {{ public }}struct PathVars {",
                                                   "{% endif %}        {{ v.doc }}",
                                                   "        {{ public }}var {{ v.name }}: {{ v.type }}{% if forloop.last %}{% if publicMemberwiseInit %}",
                                                   "",
                                                   "        // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}",
                                                   "        public init({% for v in pathVars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {",
                                                   "        {% for v in pathVars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}",
                                                   "        {% endfor %}}{% endif %}",
                                                   "    }{% endif %}{% empty %}",
                                                   "    {{ public }}var path: String {return \"{{ path }}\"}{% endfor %}",
                                                   "{% if paramType %}",
                                                   "    {{ public }}let param: {{ paramType }}",
                                                   "    {{ public }}var bodyParameters: BodyParameters? {return {% if paramType == \"String\" %}TextBodyParameters(contentType: \"{{ paramContentType }}\", content: param){% else %}param.jsonBodyParameters{% endif %}}{% endif %}{% if structParam %}{{ structParam }}{% endif %}",
                                                   "    {{ public }}enum Responses {",
                                                   "{% for r in responseCases %}        case {{ r.case }}({{ r.type }}){% if r.innerType %}",
                                                   "{{ r.innerType }}{% endif %}",
                                                   "{% endfor %}    }",
                                                   "{% if headerVars %}",
                                                   "    {{ public }}var headerFields: [String: String] {return headerVars.context as? [String: String] ?? [:]}",
                                                   "    {{ public }}var headerVars: HeaderVars",
                                                   "    {{ public }}struct HeaderVars {",
                                                   "{% for v in headerVars %}       {{ v.doc }}",
                                                   "        {{ public }}var {{ v.name }}: {{ v.type }}",
                                                   "{% endfor %}{% if publicMemberwiseInit %}",
                                                   "        // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}",
                                                   "        public init({% for v in headerVars %}{{ v.name|escapeKeyword }}: {{ v.type }}{% ifnot forloop.last %}, {% endif %}{% endfor %}) {",
                                                   "        {% for v in headerVars %}    self.{{ v.name|escapeKeyword }} = {{ v.name|escapeKeyword }}",
                                                   "        {% endfor %}}{% endif %}",
                                                   "    }",
                                                   "{% endif %}{% if publicMemberwiseInit %}",
                                                   "    // public memberwise init{# default synthesized memberwise init is internal in Swift 3 #}",
                                                   "    public init(baseURL: URL{% if pathVars %}, pathVars: PathVars{% endif %}{% if paramType %}, param: {{ paramType }}{% endif %}{% if headerVars %}, headerVars: HeaderVars{% endif %}) {",
                                                   "        self.baseURL = baseURL{% if pathVars %}\n        self.pathVars = pathVars{% endif %}{% if paramType %}\n        self.param = param{% endif %}{% if headerVars %}\n        self.headerVars = headerVars{% endif %}",
                                                   "    }",
                                                   "{% endif %}",
                                                   "    {{ public }}func response(from object: Any, urlResponse: HTTPURLResponse) throws -> Responses {",
                                                   "        let contentType = contentMIMEType(in: urlResponse)",
                                                   "        switch (urlResponse.statusCode, contentType) {",
                                                   "{% for r in responseCases %}        case ({{ r.statusCode }}, {{ r.contentType }}):",
                                                   "            return .{{ r.case }}({% if r.type != \"Void\" %}try {% if r.innerType %}Responses.{% endif %}{{ r.type }}.decodeValue(object){% endif %})",
                                                   "{% endfor %}        default:",
                                                   "            throw ResponseError.undefined(urlResponse.statusCode, contentType)",
                                                   "        }",
                                                   "    }",
                                                   "}\n"].joined(separator: "\n"), environment: stencilEnvironment)
        let globalPathVarsTemplate = Template(templateString: [ // FIXME: rename protocol name
            "extension {{ fqn }}: URITemplateContextConvertible {",
            "    var jsonBodyParametersObject: Any {",
            "        var j: [String: Any] = [:]",
            "{% for v in vars %}        j[\"{{ v.key }}\"] = {{ v.name }}{% if v.optional %}?{% endif %}.jsonBodyParametersObject\n{% endfor %}        return j",
            "    }",
            "}\n"].joined(separator: "\n"))

        let siblingResponses = try allResponses(method: request.method)
        let responseCases = try siblingResponses.map { r -> [String: Any] in
            let type: String
            let contentTypeEscaped = (r.contentType ?? "").replacingOccurrences(of: "/", with: "_")
            let innerType: (local: String, global: String)?
            switch r.dataStructure {
            case .anonymous?:
                type = "Response\(r.statusCode)_\(contentTypeEscaped)"
                innerType = try r.dataStructure!.swift("\(requestTypeName).Responses.\(type)", public: `public`)
                _ = innerType.map {globalExtensionCode += $0.global}
            case let .ref(id: id)?:
                // external type (reference to type defined in Data Structures)
                type = id
                innerType = nil
            case nil:
                switch r.contentType {
                case "text/plain"?, "text/html"?:
                    type = "String"
                    innerType = nil
                default:
                    type = "Void"
                    innerType = nil
                }
            case .named?:
                throw ConversionError.unknownDataStructure
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
            "public": `public` ? "public " : "",
            "publicMemberwiseInit": `public`,
            "name": requestTypeName,
            "responseCases": responseCases,
            "method": "." + request.method.lowercased(),
            "path": href
        ]
        if let hrefVariables = attributes?.hrefVariables {
            let pathVars: [[String: Any]] = hrefVariables.members.map {
                ["key": $0.content.name,
                 "name": $0.swiftName,
                 "type": $0.swiftType,
                 "doc": $0.swiftDoc,
                 "optional": !$0.required]
            }
            context["extensions"] = ["APIBlueprintRequest", "URITemplateRequest"]
            context["pathVars"] = pathVars
            globalExtensionCode += try globalPathVarsTemplate.render([
                "fqn": [requestTypeName, "PathVars"].joined(separator: "."),
                "vars": pathVars])
        } else {
            context["extensions"] = ["APIBlueprintRequest"]
        }
        if let headers = request.headers?.dictionary, !headers.isEmpty {
            let headerVars = headers.map { (k, v) in
                ["key": k,
                 "name": k.lowercased().swiftIdentifierized(),
                 "type": "String",
                 "doc": v.docCommentPrefixed()]
            }
            context["headerVars"] = headerVars
            globalExtensionCode += try globalPathVarsTemplate.render([
                "fqn": [requestTypeName, "HeaderVars"].joined(separator: "."),
                "vars": headerVars])
        }
        switch request.dataStructure {
        case let .anonymous(members)?:
            // inner type
            let ds = APIBlueprintDataStructure.anonymous(members: members)
            context["paramType"] = "Param"
            let s = try ds.swift("\(requestTypeName).Param", public: `public`)
            globalExtensionCode += s.global
            context["structParam"] = s.local.indented(by: 4)
        case let .ref(id: id)?:
            let ds = APIBlueprintDataStructure.ref(id: id)
            // external type (reference to type defined in Data Structures)
            context["paramType"] = ds.id
        case .named?:
            throw ConversionError.notSupported("named DataStructure definition in a request param")
        case nil:
            if let requestContentType = request.headers?.contentType?.value, requestContentType.hasPrefix("text/") {
                context["paramType"] = "String"
                context["paramContentType"] = requestContentType
            }
        }
        context["copy"] = copy?.text.docCommentPrefixed()

        return try (local: trTemplate.render(context), global: globalExtensionCode)
    }


    func swiftRequestTypeName(request: Transaction.Request, resource: APIBlueprintResourceGroup.Resource) throws -> String {
        if let title = title, let first = title.characters.first {
            return (String(first).uppercased() + String(title.characters.dropFirst())).swiftIdentifierized()
        } else {
            return try (request.method + "_" + resource.href(transition: self, request: request)).swiftIdentifierized()
        }
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
    var swiftDoc: String {return [meta?.description, content.displayValue.map {" ex. " + $0}]
        .flatMap {$0}
        .joined(separator: " ")
        .docCommentPrefixed()}
}
