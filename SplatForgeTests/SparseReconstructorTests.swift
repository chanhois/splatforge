import CoreGraphics
import XCTest
import simd
import UIKit
@testable import SplatForge

final class SparseReconstructorTests: XCTestCase {
    func test_reconstructionRunsAcrossDetachedTaskBoundary() async {
        let keyframes = [
            makeFrame(imagePath: missingImageURL()),
            makeFrame(imagePath: missingImageURL())
        ]

        let points: [SparsePoint3D] = await Task.detached {
            SparseReconstructor.reconstruct(keyframes: keyframes, neighborWindow: 1)
        }.value

        XCTAssertTrue(points.isEmpty)
    }

    func test_nonpositiveNeighborWindowsReturnEmptyWithoutTrapping() {
        let frame = makeFrame(imagePath: missingImageURL())

        XCTAssertTrue(SparseReconstructor.reconstruct(keyframes: [frame], neighborWindow: 0).isEmpty)
        XCTAssertTrue(SparseReconstructor.reconstruct(keyframes: [frame], neighborWindow: -1).isEmpty)
    }

    func test_tooFewFramesReturnEmpty() {
        let frame = makeFrame(imagePath: missingImageURL())

        XCTAssertTrue(SparseReconstructor.reconstruct(keyframes: [frame], neighborWindow: 1).isEmpty)
    }

    func test_missingImageFilesReturnEmpty() {
        let first = makeFrame(imagePath: missingImageURL())
        let second = makeFrame(imagePath: missingImageURL())

        XCTAssertTrue(SparseReconstructor.reconstruct(keyframes: [first, second], neighborWindow: 1).isEmpty)
    }

    func test_neighborPairsWrapAroundInCaptureOrder() {
        let pairs = SparseReconstructor.neighborPairs(frameCount: 4, neighborWindow: 2)

        XCTAssertEqual(
            pairs.map { "\($0.anchor)->\($0.neighbor)" },
            ["0->1", "0->2", "1->2", "1->3", "2->3", "2->0", "3->0", "3->1"]
        )
    }

    func test_twoViewReprojectionRejectsPointWhenOnlySecondViewExceedsThreshold() {
        let frameA = makeFrame(imagePath: missingImageURL())
        let frameB = makeFrame(imagePath: missingImageURL())

        let accepted = SparseReconstructor.passesTwoViewReprojection(
            position: simd_float3(0, 0, -1),
            pixelA: .zero,
            frameA: frameA,
            pixelB: CGPoint(x: 5, y: 0),
            frameB: frameB,
            maxErrorPixels: 4
        )

        XCTAssertFalse(accepted)
    }

    func test_decodedRGBAImageSamplesKnownColors() throws {
        let image = try makeImage(
            width: 2,
            height: 1,
            rgba: [
                255, 0, 0, 255,
                0, 255, 0, 255
            ]
        )
        let decoded = try XCTUnwrap(SparseReconstructor.DecodedRGBAImage(image: image))

        XCTAssertEqual(
            SparseReconstructor.sampleColor(from: decoded, at: CGPoint(x: 0, y: 0)),
            SIMD3<UInt8>(255, 0, 0)
        )
        XCTAssertEqual(
            SparseReconstructor.sampleColor(from: decoded, at: CGPoint(x: 1, y: 0)),
            SIMD3<UInt8>(0, 255, 0)
        )
    }

    func test_colorSamplingUsesGrayFallbackForDecodeOrBoundsFailure() throws {
        let image = try makeImage(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let decoded = try XCTUnwrap(SparseReconstructor.DecodedRGBAImage(image: image))
        let gray = SIMD3<UInt8>(128, 128, 128)

        XCTAssertEqual(SparseReconstructor.sampleColor(from: nil, at: .zero), gray)
        XCTAssertEqual(
            SparseReconstructor.sampleColor(from: decoded, at: CGPoint(x: 1, y: 0)),
            gray
        )
        XCTAssertEqual(
            SparseReconstructor.sampleColor(from: decoded, at: CGPoint(x: CGFloat.nan, y: 0)),
            gray
        )
    }

    func test_nonFinitePlaceholderDoesNotShiftLaterMatchOrColor() throws {
        var pixels = [UInt8](repeating: 0, count: 6 * 4)
        pixels[0...3] = [255, 0, 0, 255]
        pixels[20...23] = [0, 0, 255, 255]
        let image = try makeImage(width: 6, height: 1, rgba: pixels)
        let decoded = try XCTUnwrap(SparseReconstructor.DecodedRGBAImage(image: image))

        let placeholder = triangulatedPoint(x: .nan, y: .nan, z: .nan)
        let valid = triangulatedPoint(x: 5, y: 0, z: -1)
        let pointAtZero = NSValue(cgPoint: .zero)
        let pointAtFive = NSValue(cgPoint: CGPoint(x: 5, y: 0))
        let frame = makeFrame(imagePath: missingImageURL())

        let points = SparseReconstructor.makeSparsePoints(
            triangulated: [placeholder, valid],
            points1: [pointAtZero, pointAtFive],
            points2: [pointAtZero, pointAtFive],
            frameA: frame,
            frameB: frame,
            decodedImageA: decoded
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].position, simd_float3(5, 0, -1))
        XCTAssertEqual(points[0].color, SIMD3<UInt8>(0, 0, 255))
    }

    func test_invalidCorrespondenceArrayCountsReturnNoPoints() throws {
        let image = try makeImage(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let decoded = try XCTUnwrap(SparseReconstructor.DecodedRGBAImage(image: image))
        let triangulated = triangulatedPoint(x: 0, y: 0, z: -1)
        let point = NSValue(cgPoint: .zero)
        let frame = makeFrame(imagePath: missingImageURL())

        XCTAssertTrue(
            SparseReconstructor.makeSparsePoints(
                triangulated: [triangulated],
                points1: [point],
                points2: [],
                frameA: frame,
                frameB: frame,
                decodedImageA: decoded
            ).isEmpty
        )
        XCTAssertTrue(
            SparseReconstructor.makeSparsePoints(
                triangulated: [],
                points1: [point],
                points2: [point],
                frameA: frame,
                frameB: frame,
                decodedImageA: decoded
            ).isEmpty
        )
    }

    private func makeFrame(imagePath: URL) -> PosedFrame {
        PosedFrame(
            imagePath: imagePath,
            pose: matrix_identity_float4x4,
            intrinsics: matrix_identity_float3x3,
            timestamp: 0
        )
    }

    private func missingImageURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jpg")
    }

    private func triangulatedPoint(x: Float, y: Float, z: Float) -> TriangulatedPoint {
        let point = TriangulatedPoint()
        point.x = x
        point.y = y
        point.z = z
        return point
    }

    private func makeImage(width: Int, height: Int, rgba: [UInt8]) throws -> UIImage {
        XCTAssertEqual(rgba.count, width * height * 4)
        let data = Data(rgba) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let alphaInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let bitmapInfo = alphaInfo.union(.byteOrder32Big)
        let cgImage = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )
        return UIImage(cgImage: cgImage)
    }
}
