import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    /// 스캐너 원본은 방향 태그 없이 물리적으로 180° 뒤집혀 저장된다(가져오기의 loadImported 는 EXIF
    /// orientation 을 적용하지만 스캔의 loadScannerTIFF 는 방향을 읽지 않아 캔버스·썸네일이 함께 뒤집힘).
    /// 사용자가 방향을 따로 잡지 않았으면(carryover·템플릿 모두 identity) 설정 > 스캔의 기본 회전
    /// (`defaultScanRotation`, 기본 180°)을 준다 — 현상 파이프라인과 orientedThumbnail 이 같은
    /// imageTransform 을 적용해 함께 정립된다. 사용자가 한 번 방향을 잡으면 그 방향이 carryover/템플릿으로
    /// 이어져 이중 적용되지 않는다.
    static func scannerInitialTransform(
        carryover: ImageTransform?, template: ImageTransform, defaultRotation: ImageRotation
    ) -> ImageTransform {
        let base = carryover ?? template
        return base.isIdentity ? ImageTransform(rotation: defaultRotation) : base
    }

    struct PreviewScanCarryover {
        var transform: ImageTransform
        var defectDisplayROI: CGRect?
        var defectSensitivity: Double
    }

    func previewCarryoverFromSelectedPreviewFrame() -> PreviewScanCarryover? {
        guard let frame = actionableFrame,
              frame.sourceKind == .scannerTIFF,
              frame.isPreviewScan else { return nil }
        return PreviewScanCarryover(
            transform: frame.imageTransform,
            defectDisplayROI: regionDisplayROI(from: frame),
            defectSensitivity: frame.defectSensitivity
        )
    }

    /// Overview는 세션 전용입니다. 새 overview가 성공하면 이전 overview를, 본 스캔이 성공하면
    /// 모든 overview를 라이브러리에서 제거하고 앱이 만든 임시 TIFF만 정리합니다.
    func removeEphemeralPreviewFrames(keeping frameID: UUID?) {
        let staleFrames = frames.filter { $0.isPreviewScan && $0.id != frameID }
        guard !staleFrames.isEmpty else { return }
        if let flatbedPreviewFrameID,
           staleFrames.contains(where: { $0.id == flatbedPreviewFrameID }) {
            resetFlatbedPreviewState()
        }
        let urls = staleFrames.map(\.rawScanURL)
        removeFramesFromLibrary(staleFrames, undoable: false)
        for url in urls { Self.removeOwnedPreviewFile(at: url) }
    }

    nonisolated static func removeOwnedPreviewFile(at url: URL) {
        let standardized = url.standardizedFileURL
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        guard standardized.deletingLastPathComponent() == temporaryDirectory,
              standardized.lastPathComponent.hasPrefix("negaflow_preview_") else { return }
        try? FileManager.default.removeItem(at: standardized)
    }

    nonisolated static func removeUncommittedScanOutput(
        _ resultURL: URL,
        infraredURL: URL?,
        requestedURL: URL?
    ) {
        guard let requestedURL,
              resultURL.standardizedFileURL == requestedURL.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: resultURL)
        let expectedInfraredURL = URL(fileURLWithPath: requestedURL.path + ".ir.tiff")
        if infraredURL?.standardizedFileURL == expectedInfraredURL.standardizedFileURL {
            try? FileManager.default.removeItem(at: expectedInfraredURL)
        }
    }

    private func regionDisplayROI(from frame: ScanFrame) -> CGRect? {
        guard let roiYup = frame.defectROICIyup, let baseSize = frame.defectBaseSize,
              baseSize.width > 0, baseSize.height > 0 else { return nil }
        let roiTopYDown = Double(frame.defectROIPixelY0)
        let by0 = roiTopYDown / baseSize.height
        let by1 = by0 + Double(roiYup.height) / baseSize.height
        let bx0 = Double(frame.defectROIPixelX0) / baseSize.width
        let bx1 = bx0 + Double(roiYup.width) / baseSize.width
        let transform = frame.imageTransform
        let corners = [CGPoint(x: bx0, y: by0), CGPoint(x: bx1, y: by0),
                       CGPoint(x: bx0, y: by1), CGPoint(x: bx1, y: by1)]
            .map { transform.baseUnitToDisplay($0, baseSize: baseSize) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }


}
