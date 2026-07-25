import CoreGraphics
import Foundation
import ScannerKit

struct FlatbedScanRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    var unitRect: CGRect
    var straightenAngle: Double

    init(
        id: UUID = UUID(),
        unitRect: CGRect,
        straightenAngle: Double = 0
    ) {
        self.id = id
        self.unitRect = clampedUnitRect(unitRect)
        self.straightenAngle = straightenAngle.isFinite
            ? min(max(straightenAngle, -45), 45)
            : 0
    }
}

enum FlatbedScanRegionGeometry {
    static func physicalArea(
        for region: FlatbedScanRegion,
        previewScanArea: ScanArea? = nil,
        capabilities: ScannerCapabilities
    ) -> ScanArea? {
        guard capabilities.supportsPositionedScanArea == true,
              let bounds = capabilities.physicalScanAreaBounds else { return nil }
        let previewArea = previewScanArea ?? bounds.maximum
        guard previewArea.originXMM.isFinite,
              previewArea.originYMM.isFinite,
              previewArea.widthMM.isFinite,
              previewArea.heightMM.isFinite,
              previewArea.widthMM > 0,
              previewArea.heightMM > 0 else { return nil }
        let rect = clampedUnitRect(region.unitRect)
        return capabilities.clampedPhysicalScanArea(ScanArea(
            originXMM: previewArea.originXMM + Double(rect.minX) * previewArea.widthMM,
            originYMM: previewArea.originYMM + Double(rect.minY) * previewArea.heightMM,
            widthMM: Double(rect.width) * previewArea.widthMM,
            heightMM: Double(rect.height) * previewArea.heightMM
        ))
    }

    static func outputMatchesPhysicalAspect(
        width: Int,
        height: Int,
        scanArea: ScanArea,
        relativeTolerance: Double = 0.01
    ) -> Bool {
        guard width > 0,
              height > 0,
              scanArea.widthMM.isFinite,
              scanArea.heightMM.isFinite,
              scanArea.widthMM > 0,
              scanArea.heightMM > 0,
              relativeTolerance.isFinite,
              relativeTolerance >= 0 else { return false }
        let expectedWidth = Double(height) * scanArea.widthMM / scanArea.heightMM
        let allowedPixelError = max(2, max(Double(width), expectedWidth) * relativeTolerance)
        return abs(Double(width) - expectedWidth) <= allowedPixelError
    }
}
