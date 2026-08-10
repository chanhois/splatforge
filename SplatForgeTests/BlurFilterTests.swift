import XCTest
import UIKit
@testable import SplatForge

final class BlurFilterTests: XCTestCase {
    // Catches matFromUIImage dereferencing a nil CGImage for CIImage-backed inputs.
    func test_finiteCIImageBackedUIImageReturnsFiniteVariance() {
        let ciImage = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = UIImage(ciImage: ciImage)

        let variance = OpenCVWrapper.laplacianVariance(forImage: image)

        XCTAssertTrue(variance.isFinite)
    }

    // Catches null dereferences and invalid OpenCV processing for images with no backing.
    func test_imageWithNoCGImageOrCIImageBackingReturnsZero() {
        let image = UIImage()

        XCTAssertEqual(OpenCVWrapper.laplacianVariance(forImage: image), 0.0)
    }

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
