import Foundation
import XCTest
@testable import SwiftBeakerCore

let examplesFolder = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("Examples")
func testdata(_ filename: String) -> Data {
    try! Data(contentsOf: examplesFolder.appendingPathComponent(filename))
}

class APIElementsTests: XCTestCase {
    func test_01_Simplest_API() {
        let result = try! JSONDecoder().decode(ParseResultElement.self, from: testdata("01. Simplest API.md.json"))

        XCTAssertEqual(result.element, "parseResult")
        XCTAssertEqual(result.content.count, 1)

        guard case let .api(apiCategory) = result.content[0] else { return XCTFail() }
        XCTAssertEqual(apiCategory.element, "category")
        XCTAssertEqual(apiCategory.meta?.classes, ["api"])

        guard case let .copy(copy) = apiCategory.content[0] else { return XCTFail() }
        XCTAssertTrue(copy.content.hasPrefix("This is one of the simplest APIs"))

        let resourceGroups = apiCategory.resourceGroups
        let resourceGroup = resourceGroups[0]
        let resource = resourceGroup.content[0]
        XCTAssertEqual(resource.attributes.href, "/message")

        let transitions = resource.transitions
        XCTAssertEqual(transitions.count, 1)
        let transition = transitions[0]

        let httpTransactions = transition.transactions
        XCTAssertEqual(httpTransactions.count, 1)
        let httpTransaction = httpTransactions[0]

        guard case let .httpRequest(httpRequest) = httpTransaction.content[0] else { return XCTFail() }
        XCTAssertEqual(httpRequest.attributes.method, .GET)

        guard case let .httpResponse(httpResponse) = httpTransaction.content[1] else { return XCTFail() }

        guard case let .asset(asset) = httpResponse.content[0] else { return XCTFail() }
        XCTAssertEqual(asset.content, "Hello World!\n")
    }

    func test_02_Resource_and_Actions() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("02. Resource and Actions.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_03_Named_Resource_and_Actions() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("03. Named Resource and Actions.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_04_Grouping_Resources() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("04. Grouping Resources.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_05_Responses() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("05. Responses.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_06_Requests() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("06. Requests.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_07_Parameters() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("07. Parameters.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_08_Attributes() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("08. Attributes.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_09_Advanced_Attributes() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("09. Advanced Attributes.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_10_Data_Structures() {
        let result = try! JSONDecoder().decode(ParseResultElement.self, from: testdata("10. Data Structures.md.json"))
        let api = result.api!
        let dataStructures = api.dataStructures
        XCTAssertEqual(dataStructures.count, 1)

        guard case .named(let couponBaseID, let couponBaseMembers, let couponBaseBaseRef) = dataStructures[0].content else { return XCTFail() }
        XCTAssertEqual(couponBaseID, "Coupon Base")
        XCTAssertEqual(couponBaseBaseRef, "object")
        XCTAssertEqual(couponBaseMembers.count, 2)
        XCTAssertEqual(couponBaseMembers[0].content.key.content, "percent_off")
        XCTAssertEqual(couponBaseMembers[0].content.value, .number(25))
        XCTAssertEqual(couponBaseMembers[0].description, "A positive integer between 1 and 100 that represents the discount the\ncoupon will apply.")
        XCTAssertEqual(couponBaseMembers[1].content.key.content, "redeem_by")
        XCTAssertEqual(couponBaseMembers[1].content.value, .number(nil))
        XCTAssertEqual(couponBaseMembers[1].description, "Date after which the coupon can no longer be redeemed")

        let resource = api.resourceGroups[0].content[0]
        XCTAssertEqual(resource.attributes.href, "/coupons/{id}")
    }

    func test_11_Resource_Model() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("11. Resource Model.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_12_Advanced_Action() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("12. Advanced Action.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_13_Named_Endpoints() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("13. Named Endpoints.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_14_JSON_Schema() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("14. JSON Schema.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func test_15_Advanced_JSON_Schema() {
        do {
            let result = try JSONDecoder().decode(ParseResultElement.self, from: testdata("15. Advanced JSON Schema.md.json"))
        } catch {
            XCTFail(String(describing: error))
        }
    }

    func testTypeAttributes() {
        let member1 = try! JSONDecoder().decode(MemberElement.self, from: """
            {
                  "element": "member",
                  "meta": {
                    "title": "ID"
                  },
                  "attributes": {
                    "typeAttributes": [
                      "required"
                    ]
                  },
                  "content": {
                    "key": {
                      "element": "string",
                      "content": "id"
                    },
                    "value": {
                      "element": "string"
                    }
                  }
                }
            """.data(using: .utf8)!)
        XCTAssertEqual(member1.name, "id")
        XCTAssertTrue(member1.required)

        let member2 = try! JSONDecoder().decode(MemberElement.self, from: """
            {
                  "element": "member",
                  "meta": {
                    "description": "Text to be shown as a warning before the actual content",
                    "title": "string"
                  },
                  "attributes": {
                    "typeAttributes": [
                      "optional"
                    ]
                  },
                  "content": {
                    "key": {
                      "element": "string",
                      "content": "spoiler_text"
                    },
                    "value": {
                      "element": "string"
                    }
                  }
                }
            """.data(using: .utf8)!)
        XCTAssertEqual(member2.name, "spoiler_text")
        XCTAssertFalse(member2.required)
    }

    func testHrefVariables() {
        let transition = try! JSONDecoder().decode(TransitionElement.self, from: """
            {
              "element": "transition",
              "meta": {
                "title": "GetAccount"
              },
              "attributes": {
                "href": "/api/v1/accounts/{id}",
                "hrefVariables": {
                  "element": "hrefVariables",
                  "content": [
                    {
                      "element": "member",
                      "meta": {
                        "title": "string"
                      },
                      "attributes": {
                        "typeAttributes": [
                          "required"
                        ]
                      },
                      "content": {
                        "key": {
                          "element": "string",
                          "content": "id"
                        },
                        "value": {
                          "element": "string"
                        }
                      }
                    }
                  ]
                }
              },
              "content": []
            }
        """.data(using: .utf8)!)
        XCTAssertEqual(transition.attributes?.href, "/api/v1/accounts/{id}")
        XCTAssertEqual(transition.attributes?.hrefVariables?.content[0].name, "id")
        XCTAssertEqual(transition.attributes?.hrefVariables?.content[0].required, true)
        XCTAssertEqual(transition.attributes?.hrefVariables?.content[0].content.value, .string(nil))
    }

    func testRequestHeaders() {
        let request = try! JSONDecoder().decode(HTTPRequestElement.self, from: """
        {
            "element": "httpRequest",
            "attributes": {
              "method": "POST",
              "headers": {
                "element": "httpHeaders",
                "content": [
                  {
                    "element": "member",
                    "content": {
                      "key": {
                        "element": "string",
                        "content": "Content-Type"
                      },
                      "value": {
                        "element": "string",
                        "content": "application/json"
                      }
                    }
                  }
                ]
              }
            },
            "content": []
        }
        """.data(using: .utf8)!)
        let headers = request.attributes.headers!.content
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers[0].name, "Content-Type")
        XCTAssertEqual(headers[0].content.value, .string("application/json"))
        XCTAssertEqual(request.attributes.headers?.contentType, "application/json")
        XCTAssertEqual([String: String](headers)["Content-Type"], "application/json")
    }
}
