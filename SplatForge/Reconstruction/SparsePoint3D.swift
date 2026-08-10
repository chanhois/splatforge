import simd

nonisolated struct SparsePoint3D: Sendable {
    let position: simd_float3
    let color: SIMD3<UInt8>
}
