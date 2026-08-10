import CoreGraphics
import XCTest
import simd
@testable import SplatForge

final class TriangulationTests: XCTestCase {
    // Catches projection-sign, matrix-layout, or dehomogenization errors.
    func test_knownPoint_recoveredWithinTolerance() {
        let results = Self.triangulate(
            points1: [CGPoint(x: 330, y: 245)],
            points2: [CGPoint(x: 280, y: 245)]
        )

        XCTAssertEqual(results.count, 1)
        let recovered = results[0]
        XCTAssertEqual(recovered.x, 0.02, accuracy: 0.001)
        XCTAssertEqual(recovered.y, 0.01, accuracy: 0.001)
        XCTAssertEqual(recovered.z, -1, accuracy: 0.001)
    }

    // Catches out-of-bounds reads when either public projection argument is malformed.
    func test_malformedProjectionLength_returnsEmptyResult() {
        let validProjection = Self.projection1
        let point = NSValue(cgPoint: CGPoint(x: 330, y: 245))

        let malformedFirst = OpenCVWrapper.triangulate(
            withProjection1: Array(validProjection.dropLast()),
            points1: [point],
            projection2: Self.projection2,
            points2: [point]
        )
        let malformedSecond = OpenCVWrapper.triangulate(
            withProjection1: validProjection,
            points1: [point],
            projection2: Array(Self.projection2.dropLast()),
            points2: [point]
        )

        XCTAssertTrue(malformedFirst.isEmpty)
        XCTAssertTrue(malformedSecond.isEmpty)
    }

    // Catches passing unpaired point vectors into OpenCV.
    func test_mismatchedCorrespondenceCounts_returnsEmptyResult() {
        let results = OpenCVWrapper.triangulate(
            withProjection1: Self.projection1,
            points1: [NSValue(cgPoint: CGPoint(x: 330, y: 245))],
            projection2: Self.projection2,
            points2: []
        )

        XCTAssertTrue(results.isEmpty)
    }

    // Catches calling OpenCV with zero columns.
    func test_emptyCorrespondences_returnsEmptyResult() {
        let results = OpenCVWrapper.triangulate(
            withProjection1: Self.projection1,
            points1: [],
            projection2: Self.projection2,
            points2: []
        )

        XCTAssertTrue(results.isEmpty)
    }

    // Catches silently dropping a point at infinity and shifting every later match.
    func test_zeroDisparityPair_preservesAlignmentWithNonFinitePlaceholder() {
        let results = Self.triangulate(
            points1: [CGPoint(x: 320, y: 240), CGPoint(x: 330, y: 245)],
            points2: [CGPoint(x: 320, y: 240), CGPoint(x: 280, y: 245)]
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertFalse(results[0].x.isFinite)
        XCTAssertFalse(results[0].y.isFinite)
        XCTAssertFalse(results[0].z.isFinite)
        XCTAssertEqual(results[1].x, 0.02, accuracy: 0.001)
        XCTAssertEqual(results[1].y, 0.01, accuracy: 0.001)
        XCTAssertEqual(results[1].z, -1, accuracy: 0.001)
    }

    private static let intrinsics = simd_float3x3(
        simd_float3(500, 0, 0),
        simd_float3(0, 500, 0),
        simd_float3(320, 240, 1)
    )

    private static let projection1 = numberedProjection(pose: matrix_identity_float4x4)
    private static let projection2: [NSNumber] = {
        var pose = matrix_identity_float4x4
        pose.columns.3 = simd_float4(0.1, 0, 0, 1)
        return numberedProjection(pose: pose)
    }()

    private static func numberedProjection(pose: simd_float4x4) -> [NSNumber] {
        ProjectionMath.projectionMatrixRowMajor(
            cameraToWorldPose: pose,
            intrinsics: intrinsics
        ).map(NSNumber.init(value:))
    }

    private static func triangulate(points1: [CGPoint], points2: [CGPoint]) -> [TriangulatedPoint] {
        OpenCVWrapper.triangulate(
            withProjection1: projection1,
            points1: points1.map(NSValue.init(cgPoint:)),
            projection2: projection2,
            points2: points2.map(NSValue.init(cgPoint:))
        )
    }
}
