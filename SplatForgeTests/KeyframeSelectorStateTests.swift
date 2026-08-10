import ARKit
import simd
import XCTest
@testable import SplatForge

final class KeyframeSelectorStateTests: XCTestCase {
    // Catches committing a candidate during evaluation instead of only after persistence succeeds.
    func test_secondEvaluation_rejectedOnlyAfterFirstPoseIsCommitted() {
        let selector = KeyframeSelector()
        let pose = matrix_identity_float4x4

        XCTAssertTrue(selector.passesGeometricFilter(pose: pose, trackingState: .normal))
        XCTAssertTrue(selector.passesGeometricFilter(pose: pose, trackingState: .normal))

        selector.commit(pose: pose)

        XCTAssertFalse(selector.passesGeometricFilter(pose: pose, trackingState: .normal))
    }

    // Catches accepting ARKit's limited tracking states as geometric candidates.
    func test_limitedTracking_isAlwaysRejected() {
        let selector = KeyframeSelector()
        var pose = matrix_identity_float4x4
        pose.columns.3 = simd_float4(1, 0, 0, 1)

        XCTAssertFalse(selector.passesGeometricFilter(pose: pose, trackingState: .limited(.excessiveMotion)))
    }

    // Catches using camera-local +Z instead of ARKit camera-local -Z for the initial object-center estimate.
    func test_identityCamera_estimatesObjectCenterAlongLocalNegativeZ() {
        let center = KeyframeSelector.estimateObjectCenter(
            fromCameraPose: matrix_identity_float4x4,
            distance: 0.3
        )

        XCTAssertEqual(center.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(center.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(center.z, -0.3, accuracy: 0.000_001)
    }

    // Catches reset retaining the preceding capture's object center and applying its baseline scale to a new capture.
    func test_reset_reestimatesObjectCenterForNextCapture() {
        let selector = KeyframeSelector(
            geometricFilter: GeometricKeyframeFilter(minBaselineRatio: 0.5, minAngleDegrees: 181),
            assumedObjectDistance: 1
        )
        let firstCapturePose = matrix_identity_float4x4

        XCTAssertTrue(selector.passesGeometricFilter(pose: firstCapturePose, trackingState: .normal))
        selector.commit(pose: firstCapturePose)
        selector.reset()

        var nextCapturePose = matrix_identity_float4x4
        nextCapturePose.columns.3 = simd_float4(0, 0, 10, 1)
        XCTAssertTrue(selector.passesGeometricFilter(pose: nextCapturePose, trackingState: .normal))
        selector.commit(pose: nextCapturePose)

        var candidatePose = nextCapturePose
        candidatePose.columns.3 = simd_float4(0.6, 0, 10, 1)
        XCTAssertTrue(selector.passesGeometricFilter(pose: candidatePose, trackingState: .normal))
    }
}
