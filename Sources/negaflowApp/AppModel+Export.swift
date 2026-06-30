import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import UniformTypeIdentifiers

extension AppModel {
    /// 저장 패널을 띄워 현재 내보내기 설정(format/color/dpi/size)으로 내보낸다. 상단 Export 버튼과
    /// 좌측탭 Output의 Export 버튼이 공유한다.
    func exportWithPanel(_ frame: ScanFrame) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat.exportContentType]
        panel.nameFieldStringValue = "frame\(frame.scanIndex).\(exportFormat.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportFrame(frame, to: url, format: exportFormat, writeSidecar: exportWriteSidecar, options: exportOptions)
    }

    /// Quick Export: 저장 패널 없이 미리 선택된 폴더에 미리 선택된 포맷/DPI로 즉시 저장한다.
    func quickExport(_ frame: ScanFrame) {
        let folder = quickExportFolderURL
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueExportURL(in: folder, baseName: "frame\(frame.scanIndex)", ext: quickExportFormat.fileExtension)
        exportFrame(frame, to: url, format: quickExportFormat, writeSidecar: false, options: quickExportOptions)
    }

    /// 같은 폴더에 동명 파일이 있으면 -1, -2 … 를 붙여 겹치지 않게 한다.
    private func uniqueExportURL(in folder: URL, baseName: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent("\(baseName).\(ext)")
        var index = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(baseName)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }

    func exportFrame(_ frame: ScanFrame, to url: URL, format: ExportFormat, writeSidecar: Bool = false,
                     options: ExportOptions = .standard) {
        var effectiveParams = frame.preset.map { DevelopParameters(preset: $0, overrides: frame.params) } ?? frame.params
        effectiveParams.filmType = frame.filmType
        effectiveParams.developTarget = frame.params.developTarget
        effectiveParams.imageTransform = frame.imageTransform
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID
        )
        let cachedBase = frame.cachedBaseKey == baseKey ? frame.cachedBase : nil
        // rawScanTIFF(원본 그대로 보관)는 원본 raw를, 그 외 현상 export는 cleaned raw(메모리)를
        // 입력으로 써서 결함 제거가 반영되게 한다.
        let useICE = format != .rawScanTIFF
        let snapshot = ExportFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            preloadedRaw: useICE ? frame.cleanedRawImage : nil,
            cleanedRawURL: useICE ? frame.cleanedRawDiskURL : nil,
            outputURL: url,
            format: format,
            filmType: frame.filmType,
            params: effectiveParams,
            baseMode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            cachedBase: cachedBase,
            scannerModel: devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : nil),
            resolutionDPI: frame.hasDevelopedOnce ? resolutionChoice.dpi : nil,
            backendUsed: (backend?.backendType).map { $0.rawValue },
            presetName: frame.preset?.id,
            scannerProfileID: effectiveParams.scannerProfileID,
            cropRect: frame.imageTransform.cropRect,
            virtualCopy: frame.sidecarVirtualCopyInfo,
            rating: frame.rating,
            pickState: frame.pickState,
            developHistory: frame.developHistory,
            developSnapshots: frame.developSnapshots.map(\.sidecarRecord),
            writeSidecar: writeSidecar,
            exportOptions: options
        )
        frame.isDeveloping = true
        statusMessage = "내보내는 중"
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ExportFrameWriter.write(snapshot)
                }.value
                if let base = result.base {
                    frame.cachedBaseKey = baseKey
                    frame.cachedBase = base
                    frame.baseRGB = base.rgb
                }
                frame.isDeveloping = false
                statusMessage = "내보내기 완료 → \(url.lastPathComponent)"
            } catch {
                frame.isDeveloping = false
                statusMessage = "내보내기 실패: \(error.localizedDescription)"
            }
        }
    }
}

extension ExportFormat {
    /// 저장 패널/파일 타입용 UTType.
    var exportContentType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff16, .rawScanTIFF: return .tiff
        }
    }
}
