import XCTest
@testable import SplatForge

final class OpenCVBridgeTests: XCTestCase {
    func test_openCVVersion_isReported() {
        let version = OpenCVWrapper.openCVVersion()
        XCTAssertTrue(version.hasPrefix("4."), "OpenCV 4.x를 기대했지만 \(version)을 받음")
    }
}
