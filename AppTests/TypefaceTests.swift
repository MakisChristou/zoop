import XCTest
import UIKit
@testable import Zoop

final class TypefaceTests: XCTestCase {
    func testBundledGeistFacesLoadWithoutFallback() throws {
        for face in ["Geist-Regular", "Geist-Medium", "Geist-SemiBold"] {
            let font = try XCTUnwrap(UIFont(name: face, size: 14), "Missing bundled typeface: \(face)")
            XCTAssertEqual(font.familyName, "Geist")
            XCTAssertEqual(font.fontName, face)
        }
    }
}
