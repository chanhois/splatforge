import CoreGraphics
import UIKit
import simd

nonisolated enum SparseReconstructor {
    struct DecodedRGBAImage {
        let width: Int
        let height: Int

        private let bytesPerRow: Int
        private let pixels: [UInt8]

        init?(image: UIImage) {
            guard let cgImage = image.cgImage else { return nil }

            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0 else { return nil }

            let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
            let (byteCount, countOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
            guard !rowOverflow, !countOverflow, byteCount > 0 else { return nil }

            var pixels = [UInt8](repeating: 0, count: byteCount)
            let bitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            )
            let drewImage: Bool = pixels.withUnsafeMutableBytes { storage in
                guard let baseAddress = storage.baseAddress,
                      let context = CGContext(
                          data: baseAddress,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: bitmapInfo.rawValue
                      ) else {
                    return false
                }

                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drewImage else { return nil }

            self.width = width
            self.height = height
            self.bytesPerRow = bytesPerRow
            self.pixels = pixels
        }

        func color(at point: CGPoint) -> SIMD3<UInt8>? {
            let roundedX = point.x.rounded()
            let roundedY = point.y.rounded()
            guard roundedX.isFinite,
                  roundedY.isFinite,
                  roundedX >= 0,
                  roundedY >= 0,
                  roundedX < CGFloat(width),
                  roundedY < CGFloat(height) else {
                return nil
            }

            let x = Int(roundedX)
            let y = Int(roundedY)
            let (rowOffset, rowOverflow) = y.multipliedReportingOverflow(by: bytesPerRow)
            let (columnOffset, columnOverflow) = x.multipliedReportingOverflow(by: 4)
            let (offset, offsetOverflow) = rowOffset.addingReportingOverflow(columnOffset)
            let (lastColorByte, lastByteOverflow) = offset.addingReportingOverflow(2)
            guard !rowOverflow,
                  !columnOverflow,
                  !offsetOverflow,
                  !lastByteOverflow,
                  offset >= 0,
                  lastColorByte < pixels.count else {
                return nil
            }

            return SIMD3<UInt8>(pixels[offset], pixels[offset + 1], pixels[offset + 2])
        }
    }

    private static let fallbackColor = SIMD3<UInt8>(128, 128, 128)
    private static let maximumReprojectionError: Float = 4

    /// 각 키프레임을 기준(anchor)으로, 촬영 순서상 가까운 이웃과만 매칭한다.
    /// 턴테이블 캡처이므로 마지막 프레임과 첫 프레임도 순환 이웃으로 취급한다.
    static func reconstruct(keyframes: [PosedFrame], neighborWindow: Int = 3) -> [SparsePoint3D] {
        guard neighborWindow > 0, keyframes.count > neighborWindow else { return [] }

        return neighborPairs(frameCount: keyframes.count, neighborWindow: neighborWindow).flatMap { pair in
            reconstructPair(frameA: keyframes[pair.anchor], frameB: keyframes[pair.neighbor])
        }
    }

    static func neighborPairs(
        frameCount: Int,
        neighborWindow: Int
    ) -> [(anchor: Int, neighbor: Int)] {
        guard neighborWindow > 0, frameCount > neighborWindow else { return [] }

        var pairs: [(anchor: Int, neighbor: Int)] = []
        pairs.reserveCapacity(frameCount * neighborWindow)
        for anchor in 0..<frameCount {
            for offset in 1...neighborWindow {
                pairs.append((anchor, (anchor + offset) % frameCount))
            }
        }
        return pairs
    }

    static func passesTwoViewReprojection(
        position: simd_float3,
        pixelA: CGPoint,
        frameA: PosedFrame,
        pixelB: CGPoint,
        frameB: PosedFrame,
        maxErrorPixels: Float
    ) -> Bool {
        isReprojectionErrorAcceptable(
            position: position,
            pixel: pixelA,
            frame: frameA,
            maxErrorPixels: maxErrorPixels
        ) && isReprojectionErrorAcceptable(
            position: position,
            pixel: pixelB,
            frame: frameB,
            maxErrorPixels: maxErrorPixels
        )
    }

    static func sampleColor(
        from decodedImage: DecodedRGBAImage?,
        at point: CGPoint
    ) -> SIMD3<UInt8> {
        decodedImage?.color(at: point) ?? fallbackColor
    }

    static func makeSparsePoints(
        triangulated: [TriangulatedPoint],
        points1: [NSValue],
        points2: [NSValue],
        frameA: PosedFrame,
        frameB: PosedFrame,
        decodedImageA: DecodedRGBAImage?
    ) -> [SparsePoint3D] {
        guard !points1.isEmpty,
              points1.count == points2.count,
              triangulated.count == points1.count else {
            return []
        }

        var result: [SparsePoint3D] = []
        result.reserveCapacity(triangulated.count)
        for index in triangulated.indices {
            let triangulatedPoint = triangulated[index]
            let position = simd_float3(
                triangulatedPoint.x,
                triangulatedPoint.y,
                triangulatedPoint.z
            )
            guard position.x.isFinite,
                  position.y.isFinite,
                  position.z.isFinite else {
                continue
            }

            let pixelA = points1[index].cgPointValue
            let pixelB = points2[index].cgPointValue
            guard passesTwoViewReprojection(
                position: position,
                pixelA: pixelA,
                frameA: frameA,
                pixelB: pixelB,
                frameB: frameB,
                maxErrorPixels: maximumReprojectionError
            ) else {
                continue
            }

            result.append(
                SparsePoint3D(
                    position: position,
                    color: sampleColor(from: decodedImageA, at: pixelA)
                )
            )
        }
        return result
    }

    private static func reconstructPair(frameA: PosedFrame, frameB: PosedFrame) -> [SparsePoint3D] {
        guard let imageA = UIImage(contentsOfFile: frameA.imagePath.path),
              let imageB = UIImage(contentsOfFile: frameB.imagePath.path) else {
            return []
        }

        let matches = OpenCVWrapper.matchFeatures(between: imageA, and: imageB)
        guard !matches.points1.isEmpty,
              matches.points1.count == matches.points2.count else {
            return []
        }

        let projection1 = ProjectionMath.projectionMatrixRowMajor(
            cameraToWorldPose: frameA.pose,
            intrinsics: frameA.intrinsics
        ).map(NSNumber.init(value:))
        let projection2 = ProjectionMath.projectionMatrixRowMajor(
            cameraToWorldPose: frameB.pose,
            intrinsics: frameB.intrinsics
        ).map(NSNumber.init(value:))
        let triangulated = OpenCVWrapper.triangulate(
            withProjection1: projection1,
            points1: matches.points1,
            projection2: projection2,
            points2: matches.points2
        )
        let decodedImageA = DecodedRGBAImage(image: imageA)

        return makeSparsePoints(
            triangulated: triangulated,
            points1: matches.points1,
            points2: matches.points2,
            frameA: frameA,
            frameB: frameB,
            decodedImageA: decodedImageA
        )
    }

    private static func isReprojectionErrorAcceptable(
        position: simd_float3,
        pixel: CGPoint,
        frame: PosedFrame,
        maxErrorPixels: Float
    ) -> Bool {
        guard pixel.x.isFinite,
              pixel.y.isFinite,
              maxErrorPixels.isFinite,
              maxErrorPixels >= 0 else {
            return false
        }

        let projection = ProjectionMath.project(
            worldPoint: position,
            pose: frame.pose,
            intrinsics: frame.intrinsics
        )
        guard projection.isInFrontOfCamera else { return false }

        let error = hypot(projection.pixel.x - pixel.x, projection.pixel.y - pixel.y)
        return error.isFinite && error <= CGFloat(maxErrorPixels)
    }
}
