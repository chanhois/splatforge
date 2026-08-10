import simd
import Foundation

/// 캡처된 한 키프레임: 이미지(디스크에 저장됨) + 그 순간의 카메라 포즈/내부파라미터.
/// 이미지를 메모리에 CVPixelBuffer로 들고 있지 않고 파일 경로만 저장한다 —
/// 수백 프레임이 쌓여도 메모리 부담이 없도록 하기 위함(설계 스펙의 Capture 섹션 참고).
nonisolated struct PosedFrame: Sendable {
    let imagePath: URL
    let pose: simd_float4x4       // ARFrame.camera.transform과 동일한 규약: camera-to-world, ARKit는 로컬 -Z가 전방
    let intrinsics: simd_float3x3 // ARFrame.camera.intrinsics
    let timestamp: TimeInterval
}
