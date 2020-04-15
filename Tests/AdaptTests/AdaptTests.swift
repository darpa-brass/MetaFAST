import XCTest
@testable import FlightTest

class AdaptTests: XCTestCase {

    func testInverse() {
        XCTAssertEqual(inverse([[7,2,1],[0,3,-1],[-3,4,-2]]), [[-2.0, 8.0, -5.0], [3.0, -11.0, 7.0], [9.0, -34.0, 21.0]])
    }

    static var allTests = [
        ("testInverse", testInverse)
    ]
}
