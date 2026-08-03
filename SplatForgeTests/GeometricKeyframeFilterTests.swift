import XCTest
import simd
@testable import SplatForge

final class GeometricKeyframeFilterTests: XCTestCase {
    func test_firstFrame_alwaysSelected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let pose = matrix_identity_float4x4
        XCTAssertTrue(filter.shouldSelect(candidatePose: pose, lastKeyframePose: nil, objectCenter: simd_float3(0, 0, -0.5)))
    }

    func test_tinyMovement_rejected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let objectCenter = simd_float3(0, 0, -0.5)

        var lastPose = matrix_identity_float4x4
        lastPose.columns.3 = simd_float4(0, 0, 0, 1)

        var candidatePose = matrix_identity_float4x4
        candidatePose.columns.3 = simd_float4(0.001, 0, 0, 1) // 1mm 이동 — object까지 0.5m 대비 매우 작음

        XCTAssertFalse(filter.shouldSelect(candidatePose: candidatePose, lastKeyframePose: lastPose, objectCenter: objectCenter))
    }

    func test_sufficientRotationAroundObject_selected() {
        let filter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0)
        let objectCenter = simd_float3(0, 0, 0)
        let radius: Float = 0.5

        var lastPose = matrix_identity_float4x4
        lastPose.columns.3 = simd_float4(radius, 0, 0, 1) // objectCenter 기준 반경 0.5m 지점, 각도 0도

        let angleRad: Float = 10 * .pi / 180 // 임계값(5도)보다 큰 10도 회전
        var candidatePose = matrix_identity_float4x4
        candidatePose.columns.3 = simd_float4(radius * cos(angleRad), 0, radius * sin(angleRad), 1)

        XCTAssertTrue(filter.shouldSelect(candidatePose: candidatePose, lastKeyframePose: lastPose, objectCenter: objectCenter))
    }
}
