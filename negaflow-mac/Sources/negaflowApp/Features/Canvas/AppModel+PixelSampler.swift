import CoreGraphics
import Chromabase

extension AppModel {
    func setPixelSamplerEnabled(_ enabled: Bool) {
        pixelSamplerStore.setEnabled(enabled)
        if enabled, let frame = actionableFrame {
            requestDevelop(frame)
        }
    }

    func updatePixelSampler(for frame: ScanFrame, displayUnitPoint: CGPoint) {
        guard pixelSamplerStore.isEnabled else { return }
        let sourceSize = sourcePixelSize(for: frame)
        let basePoint = frame.imageTransform.displayUnitToBase(displayUnitPoint, baseSize: sourceSize)
        let unitPoint = CGPoint(
            x: min(max(basePoint.x, 0), 1),
            y: min(max(basePoint.y, 0), 1)
        )
        guard let coordinate = PixelSampler.sourceCoordinate(
            at: unitPoint,
            width: Int(sourceSize.width),
            height: Int(sourceSize.height)
        ) else {
            pixelSamplerStore.update(nil)
            return
        }
        let original = frame.cachedRawBase.flatMap { PixelSampler.sample($0, at: unitPoint) }
        let working = pixelSamplerStore.workingBase(for: frame.id).flatMap {
            PixelSampler.sample($0, at: unitPoint, rgbColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        }
        let proof = softProofEnabled
            ? frame.cachedDevelopedBase.flatMap { PixelSampler.sample($0, at: unitPoint) }
            : nil
        pixelSamplerStore.update(PixelSamplerReadout(
            sourceCoordinate: coordinate,
            original: original,
            working: working,
            proof: proof
        ))
    }

    func sourcePixelSize(for frame: ScanFrame) -> CGSize {
        if let width = frame.sourcePixelWidth, let height = frame.sourcePixelHeight {
            return CGSize(width: width, height: height)
        }
        if let raw = frame.cachedRawBase {
            return CGSize(width: raw.width, height: raw.height)
        }
        return CGSize(width: 1, height: 1)
    }
}
