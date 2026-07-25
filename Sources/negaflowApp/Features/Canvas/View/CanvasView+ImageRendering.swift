import SwiftUI
import AppKit
import Chromabase

extension CanvasView {
    func fittedImage(_ image: NSImage, in imageFrame: CGRect, straightenDelta: Double = 0) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: imageFrame.width, height: imageFrame.height)
            .scaleEffect(straightenCoverScale(for: straightenDelta))
            .rotationEffect(.degrees(straightenDelta))
            .frame(width: imageFrame.width, height: imageFrame.height)
            .clipped()
            .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func straightenDelta(from renderedTransform: ImageTransform?) -> Double {
        guard var rendered = renderedTransform else { return 0 }
        var current = frame.imageTransform
        rendered.straightenAngle = 0
        current.straightenAngle = 0
        guard rendered == current else { return 0 }
        return frame.imageTransform.straightenAngle - (renderedTransform?.straightenAngle ?? frame.imageTransform.straightenAngle)
    }

    func straightenCoverScale(for degrees: Double) -> CGFloat {
        let radians = abs(degrees) * .pi / 180
        guard radians > 1e-4 else { return 1 }
        let c = abs(cos(radians))
        let s = abs(sin(radians))
        return CGFloat(min(1.18, max(c + s * 0.56, c * 0.56 + s)))
    }

    func localImage(_ image: NSImage, width: CGFloat, height: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: width, height: height)
    }

    func splitVerticalImage(
        before: NSImage,
        after: NSImage,
        destinationGamutOverlay: NSImage?,
        clippingOverlay: NSImage?,
        in imageFrame: CGRect
    ) -> some View {
        ZStack {
            localImage(after, width: imageFrame.width, height: imageFrame.height)
            if let destinationGamutOverlay {
                localImage(destinationGamutOverlay, width: imageFrame.width, height: imageFrame.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let clippingOverlay {
                localImage(clippingOverlay, width: imageFrame.width, height: imageFrame.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 0) {
                localImage(before, width: imageFrame.width, height: imageFrame.height)
                    .frame(width: imageFrame.width / 2, alignment: .leading)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: 1, height: imageFrame.height)
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func splitHorizontalImage(
        before: NSImage,
        after: NSImage,
        destinationGamutOverlay: NSImage?,
        clippingOverlay: NSImage?,
        in imageFrame: CGRect
    ) -> some View {
        ZStack {
            localImage(after, width: imageFrame.width, height: imageFrame.height)
            if let destinationGamutOverlay {
                localImage(destinationGamutOverlay, width: imageFrame.width, height: imageFrame.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let clippingOverlay {
                localImage(clippingOverlay, width: imageFrame.width, height: imageFrame.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                localImage(before, width: imageFrame.width, height: imageFrame.height)
                    .frame(height: imageFrame.height / 2, alignment: .top)
                    .clipped()
                Spacer(minLength: 0)
            }
            .frame(width: imageFrame.width, height: imageFrame.height)
            Rectangle()
                .fill(.white.opacity(0.75))
                .frame(width: imageFrame.width, height: 1)
        }
        .frame(width: imageFrame.width, height: imageFrame.height)
        .position(x: imageFrame.midX, y: imageFrame.midY)
    }

    func compareLabels(in imageFrame: CGRect, orientation: CanvasCompareOrientation) -> some View {
        CanvasCompareLabels(
            imageFrame: imageFrame,
            orientation: orientation,
            beforeLabel: beforeLabel,
            selectedBeforeID: selectedBeforeID,
            primaryBeforeOptions: primaryBeforeOptions,
            frameBeforeOptions: frameBeforeOptions,
            onSelectBefore: { beforeContentRaw = $0 },
            onSelectCurrent: { selectCompareMode(.developed) }
        )
    }

}
