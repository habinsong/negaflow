import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

extension DevelopFrameRenderer {
    static func displayProxy(_ input: CIImage, maxDimension: CGFloat = fullMaxDimension) -> CIImage {
        let extent = input.extent.integral
        let maxSide = max(extent.width, extent.height)
        guard maxSide > maxDimension else {
            return input
        }
        let scale = maxDimension / maxSide
        let scaledSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        return input
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(origin: .zero, size: scaledSize))
    }

    static func renderContext() -> CIContext {
        sharedRenderContext
    }

}
