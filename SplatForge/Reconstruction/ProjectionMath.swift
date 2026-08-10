import CoreGraphics
import simd

nonisolated enum ProjectionMath {
    /// Converts ARKit's camera-to-world, local -Z-forward pose into a standard
    /// positive-depth pinhole projection matrix, returned row-major as 3x4 values.
    static func projectionMatrixRowMajor(
        cameraToWorldPose pose: simd_float4x4,
        intrinsics: simd_float3x3
    ) -> [Float] {
        let worldToCamera = pose.inverse
        let correctedExtrinsics: [[Float]] = [
            [
                worldToCamera.columns.0.x,
                worldToCamera.columns.1.x,
                worldToCamera.columns.2.x,
                worldToCamera.columns.3.x
            ],
            [
                worldToCamera.columns.0.y,
                worldToCamera.columns.1.y,
                worldToCamera.columns.2.y,
                worldToCamera.columns.3.y
            ],
            [
                -worldToCamera.columns.0.z,
                -worldToCamera.columns.1.z,
                -worldToCamera.columns.2.z,
                -worldToCamera.columns.3.z
            ]
        ]
        let cameraIntrinsics: [[Float]] = [
            [intrinsics.columns.0.x, intrinsics.columns.1.x, intrinsics.columns.2.x],
            [intrinsics.columns.0.y, intrinsics.columns.1.y, intrinsics.columns.2.y],
            [intrinsics.columns.0.z, intrinsics.columns.1.z, intrinsics.columns.2.z]
        ]

        var projection = [Float](repeating: 0, count: 12)
        for row in 0..<3 {
            for column in 0..<4 {
                projection[row * 4 + column] = (0..<3).reduce(into: 0) { sum, index in
                    sum += cameraIntrinsics[row][index] * correctedExtrinsics[index][column]
                }
            }
        }
        return projection
    }

    /// Projects a world-space point through an ARKit pose. Points on the camera
    /// plane or otherwise yielding a non-finite projection are safely rejected.
    static func project(
        worldPoint: simd_float3,
        pose: simd_float4x4,
        intrinsics: simd_float3x3
    ) -> (pixel: CGPoint, isInFrontOfCamera: Bool) {
        let worldPoint4 = simd_float4(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let cameraPoint = pose.inverse * worldPoint4
        let correctedDepth = -cameraPoint.z

        guard correctedDepth.isFinite, correctedDepth != 0 else {
            return (.zero, false)
        }

        let projected = intrinsics * simd_float3(cameraPoint.x, cameraPoint.y, correctedDepth)
        guard projected.z.isFinite, projected.z != 0 else {
            return (.zero, false)
        }

        let x = projected.x / projected.z
        let y = projected.y / projected.z
        guard x.isFinite, y.isFinite else {
            return (.zero, false)
        }

        return (
            CGPoint(x: CGFloat(x), y: CGFloat(y)),
            correctedDepth > 0
        )
    }
}
