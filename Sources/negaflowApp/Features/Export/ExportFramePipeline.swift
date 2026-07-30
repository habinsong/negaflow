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
            && snapshot.params.developTarget == .print
        let appliesPrintWorkspaceOutputProfile = snapshot.format != .rawScanTIFF
            && snapshot.printComposition != nil
        let printerOutputProfile: ICCOutputProfileSnapshot?
        if (requiresPrinterOutputProfile || appliesPrintWorkspaceOutputProfile),
           let profile = snapshot.printerOutputProfile {
            guard profile.validatedColorSpace() != nil else {
                throw ChromabaseError.writeFailed(
                    "PRINT export requires a valid RGB printer-class ICC profile"
                )
            }
            printerOutputProfile = profile
        } else if requiresPrinterOutputProfile {
            throw ChromabaseError.writeFailed(
                "PRINT export requires a valid RGB printer-class ICC profile"
            )
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

        // 디코드 입력으로 쓸 원본 사본은 **원본과 같은 볼륨**의 임시 폴더에 만든다. 같은 볼륨이면
        // APFS 클론이라 사실상 공짜지만, 예전처럼 대상 폴더 안에 두면 외장/네트워크로 내보낼 때
        // 원본 전체가 그 볼륨으로 실제 복사됐다가 지워졌다(동기화 폴더면 업로드까지 유발).
        // 산출물 스테이징은 원자적 rename 때문에 대상 폴더에 그대로 둔다.
        let sourceStagingDirectory = try makeSourceStagingDirectory(
            for: snapshot.rawScanURL,
            fallback: stagingDirectory,
            fileManager: fileManager
        )
        defer {
            if sourceStagingDirectory != stagingDirectory {
                try? fileManager.removeItem(at: sourceStagingDirectory)
            }
        }
        let stagedSourceURL = sourceStagingDirectory.appendingPathComponent(
            ".negaflow-source-input"
                + (snapshot.rawScanURL.pathExtension.isEmpty
                    ? ""
                    : ".\(snapshot.rawScanURL.pathExtension)"),
            isDirectory: false
        )
        let printProxyLongEdge: CGFloat?
        if let composition = snapshot.printComposition,
           !snapshot.writeMainFlatMaster,
           !snapshot.writeSidecar {
            let paper = composition.paperDimensionsMM
            let outputLongEdge = max(paper.width, paper.height)
                * CGFloat(composition.dpi) / 25.4
            printProxyLongEdge = ExportDevelopedFrameRenderer.proxyInputLongEdge(
                outputLongEdge: outputLongEdge,
                imageTransform: snapshot.params.imageTransform,
                sourcePixelSize: snapshot.sourcePixelSize
            )
        } else {
            // Main Flat과 RenderManifest decode provenance는 원본 해상도 decode 계약을 유지한다.
            printProxyLongEdge = nil
        }
        let frameRender = try ExportDevelopedFrameRenderer.prepare(
            snapshot,
            stagedSourceURL: stagedSourceURL,
            proxyLongEdge: printProxyLongEdge,
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
        // 산출물 전체 해시는 사이드카(RenderManifest)가 그 값을 요구할 때와 strict 검증에서만
        // 계산한다. 그 외에는 ICC/픽셀 크기만 확인하고, 커밋 직전 재확인은 파일 identity 로 한다
        // (저널의 durable 기록은 promotePreparation 이 어차피 실제 해시로 남긴다).
        let requiresArtifactIdentity = snapshot.writeSidecar
            || snapshot.verificationLevel.rehashesOnRecheck
        let primaryArtifact: RenderManifest.OutputArtifact?
        if requiresArtifactIdentity {
            primaryArtifact = try RenderManifestArtifactInspector.inspect(
                stagedLayout.outputURL,
                format: snapshot.format,
                expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        } else {
            primaryArtifact = nil
            try RenderManifestArtifactInspector.validate(
                stagedLayout.outputURL,
                expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        }
        // 재확인용 기준점. dev/inode 뿐 아니라 size/mtime/ctime 까지 담는 sourceFile 식별자를 쓴다 —
        // 같은 inode 를 제자리에서 다시 쓴 경우도 잡아야 하기 때문이다.
        let primaryFileIdentity = ExportArtifactFileIdentityInspector.sourceFile(
            at: stagedLayout.outputURL
        )
        if var completedManifest = renderManifest {
            guard let primaryArtifact else {
                throw ChromabaseError.writeFailed("rendered artifact identity is unavailable")
            }
            completedManifest.outputArtifact = primaryArtifact
            try completedManifest.validate()
            renderManifest = completedManifest
        }
        try writeOriginalRawIfNeeded(
            sourceURL: stagedSourceURL,
            expectedIdentity: snapshot.sourceIdentity,
            to: stagedLayout.originalRawURL,
            level: snapshot.verificationLevel
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
        if snapshot.verificationLevel.rehashesOnRecheck {
            guard let primaryArtifact,
                  try RenderManifestArtifactInspector.inspect(
                      stagedLayout.outputURL,
                      format: snapshot.format,
                      expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
                  ) == primaryArtifact else {
                throw ChromabaseError.writeFailed(
                    "rendered artifact changed after profile verification"
                )
            }
        } else {
            // 해시 없이도 ICC/픽셀 크기는 다시 확인하고, 바이트 변경은 size/mtime/ctime 으로 잡는다.
            try RenderManifestArtifactInspector.validate(
                stagedLayout.outputURL,
                expectedOutputProfileSHA256: printerOutputProfile?.profileSHA256
            )
            guard let primaryFileIdentity,
                  ExportArtifactFileIdentityInspector.sourceFile(at: stagedLayout.outputURL)
                    == primaryFileIdentity else {
                throw ChromabaseError.writeFailed(
                    "rendered artifact changed after profile verification"
                )
            }
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
                fileManager: fileManager,
                level: snapshot.verificationLevel
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

    /// 검증된 스테이징 사본을 원본 pair 로 한 번 더 복사한다. standard 는 길이 일치로 판정하고
    /// (저널이 곧 실제 해시를 남긴다), strict 는 사본 전체를 다시 해시한다.
    private static func writeOriginalRawIfNeeded(
        sourceURL: URL,
        expectedIdentity: RenderManifest.SourceIdentity,
        to destination: URL?,
        level: ExportVerificationLevel
    ) throws {
        guard let destination else { return }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        if !level.rehashesOnRecheck {
            let resolved = destination.resolvingSymlinksInPath()
            let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            guard let size, Int64(size) == expectedIdentity.byteCount else {
                throw ChromabaseError.writeFailed("original export pair identity mismatch")
            }
            return
        }
        guard try RenderManifest.sourceIdentity(for: destination) == expectedIdentity else {
            throw ChromabaseError.writeFailed("original export pair identity mismatch")
        }
    }

    /// 원본과 같은 볼륨의 교체용 임시 폴더. 만들 수 없으면(읽기 전용 볼륨 등) 기존처럼
    /// 산출물 스테이징 폴더를 그대로 쓴다 — 느려질 뿐 동작은 같다.
    private static func makeSourceStagingDirectory(
        for sourceURL: URL,
        fallback: URL,
        fileManager: FileManager
    ) throws -> URL {
        (try? fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: sourceURL.resolvingSymlinksInPath(),
            create: true
        )) ?? fallback
    }

    private static func renderContext() -> CIContext {
        sharedRenderContext
    }

}
