import Foundation
import XCTest
@testable import SplatForge

final class CaptureRunStorageTests: XCTestCase {
    func test_twoRunsKeepTheirFirstFramePathsAndContentsIndependent() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-storage-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storage = CaptureRunStorage(rootDirectory: rootDirectory)

        let firstRun = try storage.makeRunDirectory()
        let secondRun = try storage.makeRunDirectory()
        let firstFrame = storage.frameURL(index: 0, in: firstRun)
        let secondFrame = storage.frameURL(index: 0, in: secondRun)

        try Data("first run".utf8).write(to: firstFrame)
        try Data("second run".utf8).write(to: secondFrame)

        XCTAssertNotEqual(firstRun, secondRun)
        XCTAssertEqual(firstFrame.lastPathComponent, "frame-0.jpg")
        XCTAssertEqual(secondFrame.lastPathComponent, "frame-0.jpg")
        XCTAssertNotEqual(firstFrame, secondFrame)
        XCTAssertEqual(try Data(contentsOf: firstFrame), Data("first run".utf8))
        XCTAssertEqual(try Data(contentsOf: secondFrame), Data("second run".utf8))
    }
}
