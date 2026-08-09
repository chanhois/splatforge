import XCTest
import UIKit
@testable import SplatForge

final class BlurFilterTests: XCTestCase {
    func test_checkerboardHasHigherVarianceThanSolidColor() {
        let solid = Self.makeTestImage(checkerboard: false)
        let checker = Self.makeTestImage(checkerboard: true)

        let solidVariance = OpenCVWrapper.laplacianVariance(forImage: solid)
        let checkerVariance = OpenCVWrapper.laplacianVariance(forImage: checker)

        XCTAssertGreaterThan(checkerVariance, solidVariance)
    }

    private static func makeTestImage(checkerboard: Bool) -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            if !checkerboard {
                UIColor.gray.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            } else {
                for y in stride(from: 0, to: Int(size.height), by: 8) {
                    for x in stride(from: 0, to: Int(size.width), by: 8) {
                        let isBlack = ((x / 8) + (y / 8)) % 2 == 0
                        (isBlack ? UIColor.black : UIColor.white).setFill()
                        context.fill(CGRect(x: x, y: y, width: 8, height: 8))
                    }
                }
            }
        }
    }
}
