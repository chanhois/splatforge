import XCTest
import UIKit
@testable import SplatForge

final class FeatureMatchingTests: XCTestCase {
    // Catches returning arbitrary or mismatched keypoints instead of translated correspondences.
    func test_translatedPattern_findsConsistentMatches() {
        let base = Self.makePatternImage(offset: .zero)
        let shifted = Self.makePatternImage(offset: CGPoint(x: 10, y: 6))

        let result = OpenCVWrapper.matchFeatures(between: base, and: shifted)

        XCTAssertGreaterThan(result.points1.count, 10, "충분한 매칭이 나와야 함")
        XCTAssertEqual(result.points1.count, result.points2.count)

        let dxs = zip(result.points1, result.points2).map {
            $0.1.cgPointValue.x - $0.0.cgPointValue.x
        }
        let dys = zip(result.points1, result.points2).map {
            $0.1.cgPointValue.y - $0.0.cgPointValue.y
        }
        let averageDx = dxs.reduce(0, +) / CGFloat(dxs.count)
        let averageDy = dys.reduce(0, +) / CGFloat(dys.count)
        XCTAssertEqual(averageDx, 10, accuracy: 2.0)
        XCTAssertEqual(averageDy, 6, accuracy: 2.0)
    }

    // Catches passing empty descriptors into the matcher or returning unaligned arrays.
    func test_featurelessImages_returnAlignedEmptyMatches() {
        let image = Self.makeSolidImage()

        let result = OpenCVWrapper.matchFeatures(between: image, and: image)

        XCTAssertTrue(result.points1.isEmpty)
        XCTAssertTrue(result.points2.isEmpty)
        XCTAssertEqual(result.points1.count, result.points2.count)
    }

    // Catches calling OpenCV conversion routines with an empty cv::Mat.
    func test_imageWithoutCGImageOrCIImageBacking_returnsAlignedEmptyMatches() {
        let image = UIImage()

        let result = OpenCVWrapper.matchFeatures(between: image, and: image)

        XCTAssertTrue(result.points1.isEmpty)
        XCTAssertTrue(result.points2.isEmpty)
        XCTAssertEqual(result.points1.count, result.points2.count)
    }

    private static func makePatternImage(offset: CGPoint) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.setShouldAntialias(false)
            var state: UInt32 = 0x5A17_F0E3
            for row in 0..<22 {
                for column in 0..<22 {
                    state = state &* 1_664_525 &+ 1_013_904_223
                    guard state & 0x8000_0000 != 0 else { continue }

                    UIColor.black.setFill()
                    context.fill(
                        CGRect(
                            x: 45 + CGFloat(column * 5) + offset.x,
                            y: 45 + CGFloat(row * 5) + offset.y,
                            width: 5,
                            height: 5
                        )
                    )
                }
            }
        }
    }

    private static func makeSolidImage() -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
