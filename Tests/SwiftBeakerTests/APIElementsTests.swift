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

        let apiCategory = result.content[0]
        XCTAssertEqual(apiCategory.element, "category")
        XCTAssertEqual(apiCategory.meta?.classes, ["api"])

        let copy = (apiCategory.content as! CategoryElement.Content)[0]
        XCTAssertTrue((copy.content as! CopyElement.Content).hasPrefix("This is one of the simplest APIs"))

        let resourceGroupCategory = (apiCategory.content as! CategoryElement.Content)[1]
        let resource = (resourceGroupCategory.content as! CategoryElement.Content)[0]
        let transition = (resource.content as! ResourceElement.Content)[0]
        let httpTransaction = (transition.content as! TransitionElement.Content)[0]
        let httpRequest = (httpTransaction.content as! HTTPTransactionElement.Content)[0]
        let httpResponse = (httpTransaction.content as! HTTPTransactionElement.Content)[1]
        let responseAsset = (httpResponse.content as! HTTPResponseElement.Content)[0]
        XCTAssertEqual(responseAsset.content as! AssetElement.Content, "Hello World!\n")
    }
}
