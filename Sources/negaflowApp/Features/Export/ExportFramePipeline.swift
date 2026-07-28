import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

enum ExportFrameWriter {
    // Apple Core Image 권장대로 context의 kernel/cache 상태를 export 간 재사용한다.
    private static let sharedRenderContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func write(_ snapshot: ExportFrameSnapshot) throws -> ExportFrameResult {
        try write(snapshot, beforeCommit: {})
    }

    /// 원본 교체 race를 결정적으로 재현하는 내부 테스트 seam.
    static func write(
        _ snapshot: ExportFrameSnapshot,
        beforeCommit: () throws -> Void
    ) throws -> ExportFrameResult {
        let fileManager = FileManager.default
        let requiresPrinterOutputProfile = snapshot.format != .rawScanTIFF
            && (snapshot.params.developTarget == .print || snapshot.printComposition != nil)
        let printerOutputProfile: ICCOutputProfileSnapshot?
        if requiresPrinterOutputProfile {
            guard let profile = snapshot.printerOutputProfile,
                  profile.validatedColorSpace() != nil else {
                throw ChromabaseError.writeFailed(
                    "PRINT export requires a valid RGB printer-class ICC profile"
                )
            }
            printerOutputProfile = profile
        } else {
            printerOutputProfile = nil
        }
        let finalLayout = ExportArtifactLayout(
            outputURL: snapshot.outputURL,
            format: snapshot.format,
            sourceURL: snapshot.rawScanURL,
            writeSidecar: snapshot.writeSidecar,
            writeMainFlatMaster: snapshot.writeMainFlatMaster,
            writeOriginalRaw: snapshot.writeOriginalRaw
        )
        try validateDestinationsAreAvailable(
            finalLayout,
            protectedSource: snapshot.rawScanURL,
            fileManager: fileManager
        )
        let commitTransactionID = UUID()
        let stagingDirectory = snapshot.outputURL.deletingLastPathComponent().appendingPathComponent(
            ".negaflow-export-\(commitTransactionID.uuidString).tmp",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )
        try ExportArtifactCommitJournal.beginPreparation(
            transactionID: commitTransactionID,
            stagingDirectory: stagingDirectory,
            fileManager: fileManager
        )
        defer {
            ExportArtifactCommitJournal.cancelPreparation(
                transactionID: commitTransactionID,
                fileManager: fileManager
            )
        }
        let stagedLayout = finalLayout.staged(in: stagingDirectory)

        let stagedSourceURL = stagingDirectory.appendingPathComponent(
            ".negaflow-source-input"
                + (snapshot.rawScanURL.pathExtension.isEmpty
                    ? ""
                    : ".\(snapshot.rawScanURL.pathExtension)"),
            isDirectory: false
        )
        let frameRender = try ExportDevelopedFrameRenderer.prepare(
            snapshot,
            stagedSourceURL: stagedSourceURL,
            fileManager: fileManager
        )
        let scannerProfile = snapshot.scannerProfileID.flatMap { ScannerProfileRegistry.load(named: $0) }
        var renderManifest: RenderManifest?
        if snapshot.writeSidecar {
            let inputKind: RenderManifest.RenderInputKind
            let inputIdentity: RenderManifest.SourceIdentity?
            let coverage: RenderManifest.Coverage
            if frameRender.selectedInputKind == .cleanedMemory {
                inputKind = .cleanedMemory
                inputIdentity = nil
                coverage = .sourceAndDevelopRecipe
            } else if frameRender.selectedInputKind == .cleanedFile,
                      let cleanedRawURL = snapshot.cleanedRawURL {
                inputKind = .cleanedFile
                inputIdentity = try RenderManifest.sourceIdentity(for: cleanedRawURL)
                coverage = .completeRenderInput
            } else {
                inputKind = .source
                inputIdentity = nil
                coverage = .completeRenderInput
            }
            renderManifest = try RenderManifest(
                source: snapshot.sourceIdentity,
                developRecipeSHA256: RenderManifest.developRecipeSHA256(for: snapshot.params),
                scannerProfileID: scannerProfile?.id ?? snapshot.scannerProfileID,
                scannerProfileHash: scannerProfile?.profileHash,
                rendererVersion: snapshot.rendererVersion,
                renderInputKind: inputKind,
                renderInput: inputIdentity,
                coverage: coverage,
                decodeProvenance: frameRender.selectedDecodeProvenance,
                defectRecipeSHA256: inputKind == .source
                    ? nil
                    : snapshot.cleanedRawIdentity?.recipeSHA256,
                exportRecipeSHA256: snapshot.exportRecipeIdentity?.configurationSHA256,
                outputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        } else {
            renderManifest = nil
        }
        // DPI는 내보내기 옵션이 지정하면 그 값을, 아니면 스캔 해상도를 기록한다.
        let effectiveDPI = snapshot.exportOptions.dpi > 0 ? snapshot.exportOptions.dpi : snapshot.resolutionDPI
        if let overlay = snapshot.appMetadataOverlay,
           overlay.sourceMetadataSHA256 != snapshot.sourceMetadataSHA256 {
            throw ChromabaseError.writeFailed("app metadata overlay conflicts with source metadata")
        }
        let embeddedSourceMetadata = ExportSourceMetadata.read(from: stagedSourceURL)
        let sourceMetadata = snapshot.appMetadataOverlay?.applying(to: embeddedSourceMetadata)
            ?? embeddedSourceMetadata
        // 촬영 기록을 적어 두면 그 카메라가 EXIF Make/Model 이다 — 사진을 찍은 장비가 스캐너보다
        // 먼저다. 스캐너 식별자는 사이드카에 그대로 남는다.
        let filmShot = snapshot.appMetadataOverlay?.filmShot
        let meta = ExportMeta(
            scannerMake: filmShot?.cameraMake == nil ? snapshot.scannerMake : nil,
            scannerModel: filmShot?.cameraModel == nil
                ? (snapshot.scannerDeviceModel ?? snapshot.scannerModel)
                : nil,
            resolutionDPI: effectiveDPI,
            filmType: snapshot.filmType.rawValue,
            filmStock: filmShot?.filmStock,
            software: "negaflow \(snapshot.appVersion)",
            sourceDate: snapshot.sourceDate,
            metadataDate: snapshot.metadataDate,
            sourceMetadata: sourceMetadata,
            metadataPolicy: snapshot.exportOptions.metadataPolicy
        )
        // Raw TIFF는 source pixel을 16-bit TIFF로 보존하는 경로다. 현재 develop recipe,
        // scanner profile, defect cache를 적용하지 않는다.
        let developed: CIImage
        if let printComposition = snapshot.printComposition {
            guard snapshot.format != .rawScanTIFF,
                  let composed = PrintCompositionRenderer.apply(
                    to: frameRender.developedImage,
                    settings: printComposition,
                    filmType: snapshot.filmType
                  ) else {
                throw ChromabaseError.writeFailed("invalid print composition")
            }
            developed = composed
        } else {
            developed = frameRender.developedImage
        }
        let mainFlatMaster = (snapshot.writeMainFlatMaster && snapshot.format != .rawScanTIFF)
            ? ChromabaseEngine().developScanner(
                image: frameRender.rawInput,
                base: frameRender.base,
                params: snapshot.params.mainFlatMasterParameters()
            )
            : nil
        _ = try ExportEngine.writePaired(
            developed,
            mainFlatMaster: mainFlatMaster,
            to: stagedLayout.outputURL,
            format: snapshot.format,
            using: renderContext(),
            metadata: meta,
            options: snapshot.exportOptions,
            primaryOutputProfile: printerOutputProfile,
            writeMainFlatMaster: snapshot.writeMainFlatMaster
        )
        let primaryArtifact = try RenderManifestArtifactInspector.inspect(
            stagedLayout.outputURL,
            format: snapshot.format,
            expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
        )
        if var completedManifest = renderManifest {
            completedManifest.outputArtifact = primaryArtifact
            try completedManifest.validate()
            renderManifest = completedManifest
        }
        try writeOriginalRawIfNeeded(
            sourceURL: stagedSourceURL,
            expectedIdentity: snapshot.sourceIdentity,
            to: stagedLayout.originalRawURL
        )
        if snapshot.writeSidecar {
            try writeSidecars(
                for: snapshot,
                to: stagedLayout,
                base: frameRender.base,
                scannerProfile: scannerProfile,
                renderManifest: renderManifest,
                sourceMetadata: sourceMetadata
            )
        }
        try beforeCommit()
        try ExportDevelopedFrameRenderer.verifySourceIdentity(
            snapshot,
            stagedSourceURL: stagedSourceURL
        )
        try validateStagedArtifacts(stagedLayout, fileManager: fileManager)
        guard try RenderManifestArtifactInspector.inspect(
            stagedLayout.outputURL,
            format: snapshot.format,
            expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
        ) == primaryArtifact else {
            throw ChromabaseError.writeFailed(
                "rendered artifact changed after profile verification"
            )
        }
        try ExportArtifactCommitJournal.promotePreparation(
            transactionID: commitTransactionID,
            stagingDirectory: stagingDirectory,
            stagedLayout: stagedLayout,
            finalLayout: finalLayout,
            fileManager: fileManager
        )
        try? ExportArtifactCommitJournal.completePreparation(
            transactionID: commitTransactionID,
            fileManager: fileManager
        )
        do {
            try commit(
                transactionID: commitTransactionID,
                stagedLayout: stagedLayout,
                finalLayout: finalLayout,
                fileManager: fileManager
            )
            guard ExportArtifactCommitJournal.cleanupOwnedStaging(
                transactionID: commitTransactionID,
                fileManager: fileManager
            ) else {
                throw ChromabaseError.writeFailed("export staging cleanup failed")
            }
        } catch {
            ExportArtifactCommitJournal.cancelUncommitted(
                transactionID: commitTransactionID,
                fileManager: fileManager
            )
            throw error
        }
        return ExportFrameResult(
            commitTransactionID: commitTransactionID,
            base: frameRender.base,
            mainFlatMasterURL: finalLayout.mainFlatMasterURL,
            originalRawURL: finalLayout.originalRawURL,
            artifactURLs: finalLayout.allURLs
        )
    }

    private static func writeOriginalRawIfNeeded(
        sourceURL: URL,
        expectedIdentity: RenderManifest.SourceIdentity,
        to destination: URL?
    ) throws {
        guard let destination else { return }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        guard try RenderManifest.sourceIdentity(for: destination) == expectedIdentity else {
            throw ChromabaseError.writeFailed("original export pair identity mismatch")
        }
    }

    private static func renderContext() -> CIContext {
        sharedRenderContext
    }

}
