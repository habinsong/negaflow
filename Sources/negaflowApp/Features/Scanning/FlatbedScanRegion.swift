import CoreGraphics
import Foundation
import ScannerKit

enum FlatbedScanRegionSource: Equatable, Sendable {
    case automatic
    case manual
}

struct FlatbedScanRegion: Identifiable, Equatable, Sendable {
    let id: UUID
    var unitRect: CGRect
    var straightenAngle: Double
    var source: FlatbedScanRegionSource

    init(
        id: UUID = UUID(),
        unitRect: CGRect,
        straightenAngle: Double = 0,
        source: FlatbedScanRegionSource = .manual
    ) {
        self.id = id
        self.unitRect = clampedUnitRect(unitRect)
        self.straightenAngle = straightenAngle.isFinite
            ? min(max(straightenAngle, -45), 45)
            : 0
        self.source = source
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
        relativeTolerance: Double = 0.01,
        minimumPixelTolerance: Int = 2
    ) -> Bool {
        guard width > 0,
              height > 0,
              scanArea.widthMM.isFinite,
              scanArea.heightMM.isFinite,
              scanArea.widthMM > 0,
              scanArea.heightMM > 0,
              relativeTolerance.isFinite,
              relativeTolerance >= 0,
              minimumPixelTolerance >= 0 else { return false }
        let expectedWidth = Double(height) * scanArea.widthMM / scanArea.heightMM
        let allowedPixelError = max(
            Double(minimumPixelTolerance),
            max(Double(width), expectedWidth) * relativeTolerance
        )
        return abs(Double(width) - expectedWidth) <= allowedPixelError
    }

    /// 실패를 실기 없이 판정할 수 있도록 적용 ROI, 결과 픽셀, 그리고 비율상 기대치와의
    /// 편차를 함께 남긴다. 요청 영역이 적용 영역과 다르면 그 차이도 덧붙인다.
    static func outputAspectDiagnostic(
        width: Int,
        height: Int,
        scanArea: ScanArea,
        requestedScanArea: ScanArea? = nil
    ) -> String {
        var diagnostic = String(
            format: "[ROI %.3f,%.3f + %.3f×%.3f mm; %d×%d px",
            scanArea.originXMM,
            scanArea.originYMM,
            scanArea.widthMM,
            scanArea.heightMM,
            width,
            height
        )
        if scanArea.heightMM > 0, scanArea.widthMM > 0, height > 0 {
            let expectedWidth = Double(height) * scanArea.widthMM / scanArea.heightMM
            let expectedHeight = Double(width) * scanArea.heightMM / scanArea.widthMM
            diagnostic += String(
                format: "; expected %.1f×%.1f px; delta %+.1f×%+.1f px",
                expectedWidth,
                expectedHeight,
                Double(width) - expectedWidth,
                Double(height) - expectedHeight
            )
        }
        if let requestedScanArea, requestedScanArea != scanArea {
            diagnostic += String(
                format: "; requested %.3f,%.3f + %.3f×%.3f mm",
                requestedScanArea.originXMM,
                requestedScanArea.originYMM,
                requestedScanArea.widthMM,
                requestedScanArea.heightMM
            )
        }
        return diagnostic + "]"
    }
}
