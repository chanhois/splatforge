import simd

/// 마지막으로 저장한 키프레임 대비 카메라가 충분히 움직였는지(baseline) 또는
/// 물체 중심 기준으로 충분히 돌았는지(각도)를 판단한다.
/// 절대 거리 대신 "물체까지 거리 대비 비율"로 baseline을 판단하는 이유:
/// 물체가 가까우면 작은 이동도 큰 시차를 만들고, 멀면 그 반대이기 때문.
nonisolated struct GeometricKeyframeFilter {
    let minBaselineRatio: Float
    let minAngleDegrees: Float

    func shouldSelect(candidatePose: simd_float4x4, lastKeyframePose: simd_float4x4?, objectCenter: simd_float3) -> Bool {
        guard let lastPose = lastKeyframePose else { return true } // 첫 프레임은 항상 채택

        let candidatePos = simd_float3(candidatePose.columns.3.x, candidatePose.columns.3.y, candidatePose.columns.3.z)
        let lastPos = simd_float3(lastPose.columns.3.x, lastPose.columns.3.y, lastPose.columns.3.z)

        let baseline = simd_distance(candidatePos, lastPos)
        let distanceToObject = simd_distance(candidatePos, objectCenter)
        let baselineRatio = distanceToObject > 0 ? baseline / distanceToObject : 0

        let candidateDir = simd_normalize(candidatePos - objectCenter)
        let lastDir = simd_normalize(lastPos - objectCenter)
        let cosAngle = simd_clamp(simd_dot(candidateDir, lastDir), -1, 1)
        let angleDegrees = acos(cosAngle) * 180 / .pi

        return baselineRatio >= minBaselineRatio || angleDegrees >= minAngleDegrees
    }
}
