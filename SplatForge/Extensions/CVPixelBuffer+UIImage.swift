import CoreImage
import UIKit

extension CVPixelBuffer {
    /// ARFrame.capturedImage is YCbCr 4:2:0, which Core Image converts to a standard RGB CGImage.
    /// CIContext creation is expensive; this shared context is safe to reuse and avoids allocating one
    /// for every capture candidate.
    private static let imageConversionContext = CIContext()

    func toUIImage() -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: self)
        guard let cgImage = Self.imageConversionContext.createCGImage(ciImage, from: ciImage.extent) else {
            preconditionFailure("CVPixelBuffer를 CGImage로 변환 실패")
        }
        return UIImage(cgImage: cgImage)
    }
}
