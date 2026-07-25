import Foundation
import Chromabase

extension ExportFrameWriter {
    static func writeSidecars(
        for snapshot: ExportFrameSnapshot,
        to layout: ExportArtifactLayout,
        base: FilmBase?,
        scannerProfile: ScannerProfile?,
        renderManifest: RenderManifest?,
        sourceMetadata: ExportSourceMetadata?
    ) throws {
        var sidecar = Sidecar(
            filmType: snapshot.filmType,
            parameters: snapshot.params,
            appVersion: snapshot.appVersion,
            engineVersion: snapshot.rendererVersion
        )
        sidecar.scannerModel = snapshot.scannerModel
        sidecar.backendUsed = snapshot.backendUsed
        sidecar.scanResolution = snapshot.resolutionDPI
        sidecar.bitDepth = snapshot.sourceBitDepth
        sidecar.presetName = snapshot.presetName
        sidecar.virtualCopy = snapshot.virtualCopy
        sidecar.rating = snapshot.rating
        sidecar.pickState = snapshot.pickState
        sidecar.developHistory = snapshot.developHistory
        sidecar.developSnapshots = snapshot.developSnapshots
        sidecar.sourceDate = snapshot.sourceDate
        sidecar.metadataDate = snapshot.metadataDate
        sidecar.renderManifest = renderManifest
        sidecar.exportEncoding = Sidecar.ExportEncodingInfo(snapshot.exportOptions)
        sidecar.exportMetadataPolicy = snapshot.exportOptions.metadataPolicy
        sidecar.exportSourceMetadata = sourceMetadata?.filtered(
            for: snapshot.exportOptions.metadataPolicy
        )
        if let identity = snapshot.exportRecipeIdentity {
            sidecar.exportRecipe = Sidecar.ExportRecipeInfo(
                presetID: identity.presetID?.uuidString,
                presetName: identity.presetName,
                configurationSHA256: identity.configurationSHA256
            )
        }
        if let profile = scannerProfile {
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
        // 내보내기 sidecar는 산출물 옆에만 쓴다. 원본 옆 기존 사이드카 XMP를
        // 병합 없이 덮어쓰는 동작은 하지 않는다.
        guard let exportSidecar = layout.sidecarURL,
              let exportXMP = layout.xmpURL else {
            throw ChromabaseError.writeFailed("sidecar layout missing: \(snapshot.outputURL.path)")
        }
        var exportSidecarBody = sidecar
        exportSidecarBody.exportHistory.append(Sidecar.ExportRecord(
            path: snapshot.outputURL.path,
            format: snapshot.format.rawValue,
            at: snapshot.metadataDate
        ))
        try exportSidecarBody.write(to: exportSidecar)
        try exportSidecarBody.writeXMP(to: exportXMP)
    }
}
