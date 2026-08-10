import XCTest
import simd
@testable import SplatForge

final class ProjectionMathTests: XCTestCase {
    // Catches dropping the ARKit -Z-forward correction or laying out K[R|t] incorrectly.
    func test_identityPose_producesExpectedProjectionMatrix() {
        let pose = matrix_identity_float4x4
        let intrinsics = Self.intrinsics

        let projection = ProjectionMath.projectionMatrixRowMajor(
            cameraToWorldPose: pose,
            intrinsics: intrinsics
        )

        XCTAssertEqual(projection.count, 12)
        XCTAssertEqual(projection[0], 500, accuracy: 1e-4)
        XCTAssertEqual(projection[2], -320, accuracy: 1e-4)
        XCTAssertEqual(projection[5], 500, accuracy: 1e-4)
        XCTAssertEqual(projection[6], -240, accuracy: 1e-4)
        XCTAssertEqual(projection[10], -1, accuracy: 1e-4)
    }

    // Catches treating camera-to-world translation as world-to-camera translation.
    func test_translatedPose_invertsTranslationBeforeProjection() {
        var pose = matrix_identity_float4x4
        pose.columns.3 = simd_float4(0.1, 0, 0, 1)

        let projection = ProjectionMath.projectionMatrixRowMajor(
            cameraToWorldPose: pose,
            intrinsics: Self.intrinsics
        )

        XCTAssertEqual(projection.count, 12)
        XCTAssertEqual(projection[3], -50, accuracy: 1e-4)
        XCTAssertEqual(projection[7], 0, accuracy: 1e-4)
        XCTAssertEqual(projection[11], 0, accuracy: 1e-4)
    }

    // Catches using the standard +Z-forward convention for ARKit poses.
    func test_pointInFrontOfCamera_isDetected() {
        let (_, isInFront) = ProjectionMath.project(
            worldPoint: simd_float3(0, 0, -1),
            pose: matrix_identity_float4x4,
            intrinsics: Self.intrinsics
        )
        XCTAssertTrue(isInFront)

        let (_, isBehind) = ProjectionMath.project(
            worldPoint: simd_float3(0, 0, 1),
            pose: matrix_identity_float4x4,
            intrinsics: Self.intrinsics
        )
        XCTAssertFalse(isBehind)
    }

    // Catches division by zero leaking a non-finite pixel at the public math boundary.
    func test_pointOnCameraPlane_isRejectedWithFiniteSentinel() {
        let result = ProjectionMath.project(
            worldPoint: simd_float3(1, 2, 0),
            pose: matrix_identity_float4x4,
            intrinsics: Self.intrinsics
        )

        XCTAssertFalse(result.isInFrontOfCamera)
        XCTAssertEqual(result.pixel, .zero)
        XCTAssertTrue(result.pixel.x.isFinite)
        XCTAssertTrue(result.pixel.y.isFinite)
    }

    private static let intrinsics = simd_float3x3(
        simd_float3(500, 0, 0),
        simd_float3(0, 500, 0),
        simd_float3(320, 240, 1)
    )
}
