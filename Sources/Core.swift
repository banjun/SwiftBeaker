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
