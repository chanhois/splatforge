import ARKit
import simd
import UIKit

/// Decides whether a captured AR frame should be persisted as a keyframe.
/// Call `commit(pose:)` only after the candidate image has been written successfully.
final class KeyframeSelector {
    private let geometricFilter: GeometricKeyframeFilter
    private let blurVarianceThreshold: Double
    private let assumedObjectDistance: Float

    private var lastKeyframePose: simd_float4x4?
    private var objectCenter: simd_float3?

    init(
        geometricFilter: GeometricKeyframeFilter = GeometricKeyframeFilter(minBaselineRatio: 0.05, minAngleDegrees: 5.0),
        blurVarianceThreshold: Double = 50.0,
        assumedObjectDistance: Float = 0.3
    ) {
        self.geometricFilter = geometricFilter
        self.blurVarianceThreshold = blurVarianceThreshold
        self.assumedObjectDistance = assumedObjectDistance
    }

    func passesGeometricFilter(pose: simd_float4x4, trackingState: ARCamera.TrackingState) -> Bool {
        guard case .normal = trackingState else { return false }

        if objectCenter == nil {
            objectCenter = Self.estimateObjectCenter(fromCameraPose: pose, distance: assumedObjectDistance)
        }

        return geometricFilter.shouldSelect(
            candidatePose: pose,
            lastKeyframePose: lastKeyframePose,
            objectCenter: objectCenter!
        )
    }

    func passesBlurFilter(image: UIImage) -> Bool {
        OpenCVWrapper.laplacianVariance(forImage: image) >= blurVarianceThreshold
    }

    /// Records a persisted keyframe as the comparison baseline for the next candidate.
    func commit(pose: simd_float4x4) {
        lastKeyframePose = pose
    }

    /// Clears capture-specific state so a new capture estimates its own object center and baseline.
    func reset() {
        lastKeyframePose = nil
        objectCenter = nil
    }

    /// ARKit cameras look along camera-local -Z, so transform the negative third rotation column.
    static func estimateObjectCenter(fromCameraPose pose: simd_float4x4, distance: Float) -> simd_float3 {
        let forward = -simd_float3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)
        let position = simd_float3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
        return position + forward * distance
    }
}
