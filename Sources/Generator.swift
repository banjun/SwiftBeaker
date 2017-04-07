import Foundation
import Stencil

typealias SwiftCode = (local: String, global: String)

protocol SwiftConvertible {
    associatedtype Context
    func swift(_ context: Context) throws -> SwiftCode
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
}

extension APIBlueprintDataStructure: SwiftConvertible {
    func swift(_ name: String? = nil) throws -> SwiftCode {
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
        return (local: try localDSTemplate.render(["name": localName.swiftIdentifierized(),
                                                   "vars": vars]),
                global: try globalDSTemplate.render(["name": localName.swiftIdentifierized(),
                                                     "fqn": name.components(separatedBy: ".").map {$0.swiftIdentifierized()}.joined(separator: "."),
                                                     "vars": vars]))
    }
}

extension APIBlueprintTransition: SwiftConvertible {
    func swift(_ otherTransitions: [APIBlueprintTransition]) throws -> SwiftCode {
        func allResponses(href: String, method: String) -> [APIBlueprintTransition.Transaction.Response] {
            return otherTransitions.filter {$0.attributes.href == href}
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

        var globalExtensionCode = ""
        let request = httpTransactions.first!.request
        let requestTypeName = swiftRequestTypeName(request: request)

        let siblingResponses = allResponses(href: attributes.href, method: request.method)
        let responseCases = try siblingResponses.map { r -> [String: Any] in
            let type: String
            let contentTypeEscaped = (r.contentType ?? "").replacingOccurrences(of: "/", with: "_")
            let rawType = r.dataStructure.map {$0.rawType.swiftTypeMapped().swiftKeywordsEscaped()} ?? "Void"
            let innerType: (local: String, global: String)?
            switch rawType {
            case "object":
                // inner type
                type = "Response\(r.statusCode)_\(contentTypeEscaped)"
                innerType = try r.dataStructure!.swift("\(requestTypeName).Responses.\(type)")
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
            "path": attributes.href
        ]
        if let hrefVariables = attributes.hrefVariables {
            let pathVars: [[String: Any]] = hrefVariables.members.map {
                ["key": $0.content.name,
                 "name": $0.swiftName,
                 "type": $0.swiftType,
                 "doc": $0.swiftDoc,
                 "optional": !$0.required]
            }
            context["pathVars"] = pathVars
            globalExtensionCode += try globalPathVarsTemplate.render([
                "fqn": [requestTypeName, "PathVars"].joined(separator: "."),
                "vars": pathVars])
        }
        if let headers = request.headers?.dictionary, !headers.isEmpty {
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
                let s = try ds.swift("\(requestTypeName).Param")
                globalExtensionCode += s.global
                context["structParam"] = s.local.indented(by: 4)
            default:
                // external type (reference to type defined in Data Structures)
                context["paramType"] = ds.rawType
            }
        }
        context["copy"] = copy?.text

        return try (local: trTemplate.render(context), global: globalExtensionCode)
    }


    func swiftRequestTypeName(request: Transaction.Request) -> String {
        if let title = title, let first = title.characters.first {
            return (String(first).uppercased() + String(title.characters.dropFirst())).swiftIdentifierized()
        } else {
            return (request.method + "_" + attributes.href).swiftIdentifierized()
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
    var swiftDoc: String {return [meta?.description, content.displayValue.map {" ex. " + $0}].flatMap {$0}.joined(separator: " ")}
}
