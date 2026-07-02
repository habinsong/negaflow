import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

struct ExportFrameSnapshot: @unchecked Sendable {
    let rawScanURL: URL
    // raw 입력 출처(로더 분기). 기본은 스캐너 TIFF.
    var sourceKind: FrameSource = .scannerTIFF
    // ICE 적용된 raw(메모리 CGImage). 있으면 이걸 입력으로 써서 결함 제거가 export에도 반영된다.
    let preloadedRaw: CGImage?
    // 메모리 적재본이 없을 때의 디스크 백킹(ICE 적용된 raw TIFF).
    let cleanedRawURL: URL?
    let outputURL: URL
    let format: ExportFormat
    let filmType: FilmType
    let params: DevelopParameters
    let baseMode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let cachedBase: FilmBase?
    let scannerModel: String?
    let resolutionDPI: Int?
    let backendUsed: String?
    let presetName: String?
    let scannerProfileID: String?
    let cropRect: SIMD4<Double>?
    let virtualCopy: Sidecar.VirtualCopyInfo?
    let rating: Int
    let pickState: FramePickState
    let developHistory: [DevelopHistoryEntry]
    let developSnapshots: [Sidecar.DevelopSnapshotRecord]
    let writeSidecar: Bool
    let writeMainFlatMaster: Bool
    let exportOptions: ExportOptions
}

struct ExportFrameResult: @unchecked Sendable {
    let base: FilmBase?
    let mainFlatMasterURL: URL?
}

enum ExportFrameWriter {
    static func write(_ snapshot: ExportFrameSnapshot) throws -> ExportFrameResult {
        let engine = ChromabaseEngine()
        let rawInput: CIImage
        if let pre = snapshot.preloadedRaw {
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            rawInput = CIImage(cgImage: pre, options: [.colorSpace: linear])
        } else if let url = snapshot.cleanedRawURL, let ci = ImageLoader.loadScannerTIFF(url) {
            rawInput = ci
        } else if let loaded = (snapshot.sourceKind == .importedFile
                                ? engine.loadImportedImage(snapshot.rawScanURL)
                                : engine.loadScannerImage(snapshot.rawScanURL)) {
            rawInput = loaded
        } else {
            throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
        }
        let base = snapshot.filmType.requiresInversion
            ? snapshot.cachedBase ?? engine.estimateFilmBase(
                in: rawInput,
                mode: snapshot.baseMode,
                manual: snapshot.manualBaseRGB,
                filmStockDminID: snapshot.params.filmStockDminID
            )
            : nil
        // DPI는 내보내기 옵션이 지정하면 그 값을, 아니면 스캔 해상도를 기록한다.
        let effectiveDPI = snapshot.exportOptions.dpi > 0 ? snapshot.exportOptions.dpi : snapshot.resolutionDPI
        let meta = ExportMeta(
            scannerModel: snapshot.scannerModel,
            resolutionDPI: effectiveDPI,
            filmType: snapshot.filmType.rawValue,
            software: "negaflow 0.1.0"
        )
        let developed = engine.developScanner(image: rawInput, base: base, params: snapshot.params)
        let mainFlatMaster = (snapshot.writeMainFlatMaster && snapshot.format != .rawScanTIFF)
            ? engine.developScanner(image: rawInput, base: base, params: snapshot.params.mainFlatMasterParameters())
            : nil
        let exportResult = try ExportEngine.writePaired(
            developed,
            mainFlatMaster: mainFlatMaster,
            to: snapshot.outputURL,
            format: snapshot.format,
            using: renderContext(),
            metadata: meta,
            options: snapshot.exportOptions,
            writeMainFlatMaster: snapshot.writeMainFlatMaster
        )
        if snapshot.writeSidecar {
            writeSidecars(for: snapshot, base: base)
        }
        return ExportFrameResult(base: base, mainFlatMasterURL: exportResult.mainFlatMasterURL)
    }

    private static func renderContext() -> CIContext {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }

    private static func writeSidecars(for snapshot: ExportFrameSnapshot, base: FilmBase?) {
        var sidecar = Sidecar(filmType: snapshot.filmType, parameters: snapshot.params)
        sidecar.scannerModel = snapshot.scannerModel
        sidecar.backendUsed = snapshot.backendUsed
        sidecar.scanResolution = snapshot.resolutionDPI
        sidecar.bitDepth = 16
        sidecar.presetName = snapshot.presetName
        sidecar.virtualCopy = snapshot.virtualCopy
        sidecar.rating = snapshot.rating
        sidecar.pickState = snapshot.pickState
        sidecar.developHistory = snapshot.developHistory
        sidecar.developSnapshots = snapshot.developSnapshots
        if let profileID = snapshot.scannerProfileID,
           let profile = ScannerProfileRegistry.load(named: profileID) {
            sidecar.scannerProfile = Sidecar.ScannerProfileInfo(profile)
            sidecar.scannerProfileGradeDiagnostics = ScannerProfileGradeDiagnostics(profile: profile)
        }
        if let crop = snapshot.cropRect {
            sidecar.crop = Sidecar.CropRect(x: crop.x, y: crop.y, w: crop.z, h: crop.w)
        }
        if let base {
            sidecar.baseSample = Sidecar.BaseSample(base)
            sidecar.filmBaseDiagnostics = Sidecar.FilmBaseDiagnostics(base)
        }
        try? sidecar.write(to: rawSidecarURL(for: snapshot))
        try? sidecar.writeXMP(to: rawXMPSidecarURL(for: snapshot))

        let exportSidecar = snapshot.outputURL
            .deletingPathExtension()
            .appendingPathExtension("negaflow.json")
        var exportSidecarBody = sidecar
        exportSidecarBody.exportHistory.append(Sidecar.ExportRecord(
            path: snapshot.outputURL.path,
            format: snapshot.format.rawValue,
            at: Date()
        ))
        try? exportSidecarBody.write(to: exportSidecar)
        try? exportSidecarBody.writeXMP(to: exportXMPSidecarURL(for: snapshot.outputURL))
    }

    private static func rawSidecarURL(for snapshot: ExportFrameSnapshot) -> URL {
        let base = snapshot.rawScanURL.deletingPathExtension()
        guard let copyNumber = snapshot.virtualCopy?.copyNumber else {
            return base.appendingPathExtension("negaflow.json")
        }
        return base.appendingPathExtension("copy-\(copyNumber).negaflow.json")
    }

    private static func rawXMPSidecarURL(for snapshot: ExportFrameSnapshot) -> URL {
        let base = snapshot.rawScanURL.deletingPathExtension()
        guard let copyNumber = snapshot.virtualCopy?.copyNumber else {
            return base.appendingPathExtension("xmp")
        }
        return base.appendingPathExtension("copy-\(copyNumber).xmp")
    }

    private static func exportXMPSidecarURL(for outputURL: URL) -> URL {
        outputURL.deletingPathExtension().appendingPathExtension("xmp")
    }
}
