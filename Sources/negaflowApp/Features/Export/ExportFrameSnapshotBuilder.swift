import Foundation
import Chromabase

struct ExportDefectRecipeIdentity: Equatable, Sendable {
    let revision: UInt64
    let recipeSHA256: String
    let sourceIdentitySHA256: String

    init?(tracking: LibraryDefectReviewTracking) {
        let values = (
            tracking.currentRecipeRevision,
            tracking.currentRecipeSHA256,
            tracking.currentSourceIdentitySHA256
        )
        if values.0 == nil, values.1 == nil, values.2 == nil {
            return nil
        }
        guard tracking.coverage == .tracked,
              let revision = values.0,
              let recipeSHA256 = values.1,
              let sourceIdentitySHA256 = values.2,
              revision > 0,
              Self.isValidSHA256(recipeSHA256),
              Self.isValidSHA256(sourceIdentitySHA256) else {
            return nil
        }
        self.revision = revision
        self.recipeSHA256 = recipeSHA256
        self.sourceIdentitySHA256 = sourceIdentitySHA256
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }
}

@MainActor
struct ExportFrameTrackingIdentity: Equatable {
    let frameID: UUID
    let sourcePath: String
    let sourceLocationRevision: UInt64
    let renderKind: LibraryExportEvent.RenderKind
    let developRecipeSHA256: String
    let defectRecipeIdentity: ExportDefectRecipeIdentity?

    static func capture(frame: ScanFrame, format: ExportFormat) -> Self? {
        guard let developRecipeSHA256 = frame.currentLibraryDevelopRecipeSHA256() else {
            return nil
        }
        let renderKind: LibraryExportEvent.RenderKind = format == .rawScanTIFF
            ? .rawSource
            : .developed
        if renderKind == .rawSource {
            return Self(
                frameID: frame.id,
                sourcePath: frame.rawScanURL.standardizedFileURL.path,
                sourceLocationRevision: frame.sourceLocationRevision,
                renderKind: renderKind,
                developRecipeSHA256: developRecipeSHA256,
                defectRecipeIdentity: nil
            )
        }
        let defectTracking = frame.libraryWorkflowTrackingState?.defectReviewTracking
            ?? .legacyUnknown
        let currentValues = [
            defectTracking.currentRecipeRevision != nil,
            defectTracking.currentRecipeSHA256 != nil,
            defectTracking.currentSourceIdentitySHA256 != nil,
        ]
        guard currentValues.allSatisfy({ $0 }) || currentValues.allSatisfy({ !$0 }) else {
            return nil
        }
        let defectRecipeIdentity = ExportDefectRecipeIdentity(tracking: defectTracking)
        let hasActiveDefectRecipe = frame.defectEdits.contains {
            $0.enabled && $0.strength > 1e-3
        }
        guard !hasActiveDefectRecipe || defectRecipeIdentity != nil else { return nil }
        return Self(
            frameID: frame.id,
            sourcePath: frame.rawScanURL.standardizedFileURL.path,
            sourceLocationRevision: frame.sourceLocationRevision,
            renderKind: renderKind,
            developRecipeSHA256: developRecipeSHA256,
            defectRecipeIdentity: defectRecipeIdentity
        )
    }

    func matchesCurrentState(
        of frame: ScanFrame,
        format: ExportFormat,
        isOwnedByModel: Bool
    ) -> Bool {
        isOwnedByModel
            && frame.id == frameID
            && frame.rawScanURL.standardizedFileURL.path == sourcePath
            && frame.sourceLocationRevision == sourceLocationRevision
            && Self.capture(frame: frame, format: format) == self
    }
}

struct ExportFrameSourceGeneration: Equatable, Sendable {
    let rawScanURL: URL
    let sourceIdentity: RenderManifest.SourceIdentity

    init(rawScanURL: URL, sourceIdentity: RenderManifest.SourceIdentity) {
        self.rawScanURL = rawScanURL.standardizedFileURL
        self.sourceIdentity = sourceIdentity
    }

    init(snapshot: ExportFrameSnapshot) {
        self.init(
            rawScanURL: snapshot.rawScanURL,
            sourceIdentity: snapshot.sourceIdentity
        )
    }

    static func capture(
        at rawScanURL: URL
    ) async -> ExportFrameSourceVerification? {
        await Task.detached(priority: .userInitiated) {
            verify(rawScanURL.standardizedFileURL, level: .strict, baseline: nil)
        }.value
    }

    /// `baselines`(경로 → 최초 capture 결과)를 주면 standard 수준에서 stat 이 그대로인 원본의
    /// 전체 재해시를 건너뛴다. stat 이 하나라도 다르면 그 경로만 실제 해시로 판정한다.
    static func currentVerifications(
        for generations: [Self],
        level: ExportVerificationLevel = .strict,
        baselines: [String: ExportFrameSourceVerification] = [:]
    ) async -> [ExportFrameSourceVerification?] {
        await Task.detached(priority: .userInitiated) {
            var verificationsByPath: [String: ExportFrameSourceVerification] = [:]
            var failedPaths = Set<String>()
            for generation in generations {
                let path = generation.rawScanURL.path
                guard verificationsByPath[path] == nil, !failedPaths.contains(path) else { continue }
                if let verification = verify(
                    generation.rawScanURL,
                    level: level,
                    baseline: baselines[path]
                ) {
                    verificationsByPath[path] = verification
                } else {
                    failedPaths.insert(path)
                }
            }
            return generations.map { verificationsByPath[$0.rawScanURL.path] }
        }.value
    }

    private static func verify(
        _ url: URL,
        level: ExportVerificationLevel,
        baseline: ExportFrameSourceVerification?
    ) -> ExportFrameSourceVerification? {
        guard let fileIdentityBefore = ExportArtifactFileIdentityInspector.sourceFile(at: url) else {
            return nil
        }
        // stat identity 는 dev/inode/size/mtime/ctime 을 모두 포함한다. 내용을 바꾸면 커널이
        // mtime 과 ctime 을 갱신하고, mtime 을 되돌리는 utimes 호출 자체가 다시 ctime 을 갱신한다.
        // 전부 동일하면 baseline 해시를 계산한 그 바이트 그대로라는 뜻이므로 재해시가 없어도 된다.
        if !level.rehashesOnRecheck,
           let baseline,
           baseline.fileIdentity == fileIdentityBefore {
            return baseline
        }
        guard let sourceIdentity = try? RenderManifest.sourceIdentity(for: url),
              let fileIdentityAfter = ExportArtifactFileIdentityInspector.sourceFile(at: url),
              fileIdentityAfter == fileIdentityBefore else { return nil }
        return ExportFrameSourceVerification(
            sourceIdentity: sourceIdentity,
            fileIdentity: fileIdentityAfter
        )
    }

    @MainActor
    func matchesCurrentState(
        of frame: ScanFrame,
        trackingIdentity: ExportFrameTrackingIdentity,
        format: ExportFormat,
        isOwnedByModel: Bool,
        verification: ExportFrameSourceVerification?
    ) -> Bool {
        verification?.sourceIdentity == sourceIdentity
            && verification?.fileIdentity
                == ExportArtifactFileIdentityInspector.sourceFile(at: rawScanURL)
            && frame.rawScanURL.standardizedFileURL == rawScanURL
            && trackingIdentity.matchesCurrentState(
                of: frame,
                format: format,
                isOwnedByModel: isOwnedByModel
            )
    }
}

struct ExportFrameSourceVerification: Equatable, Sendable {
    let sourceIdentity: RenderManifest.SourceIdentity
    let fileIdentity: ExportSourceFileIdentity
}

@MainActor
enum ExportFilmBaseCacheCommitter {
    @discardableResult
    static func apply(
        _ base: FilmBase,
        baseKey: FilmBaseCacheKey,
        to frame: ScanFrame,
        trackingIdentity: ExportFrameTrackingIdentity,
        format: ExportFormat,
        sourceGeneration: ExportFrameSourceGeneration,
        sourceVerification: ExportFrameSourceVerification?,
        isOwnedByModel: Bool
    ) -> Bool {
        let currentBaseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        guard currentBaseKey == baseKey,
              sourceGeneration.matchesCurrentState(
                of: frame,
                trackingIdentity: trackingIdentity,
                format: format,
                isOwnedByModel: isOwnedByModel,
                verification: sourceVerification
              ) else { return false }
        frame.cachedBaseKey = baseKey
        frame.cachedBase = base
        frame.baseRGB = base.rgb
        return true
    }
}

@MainActor
struct ExportFrameBuildPlan {
    let snapshot: ExportFrameSnapshot
    let baseKey: FilmBaseCacheKey
    let trackingIdentity: ExportFrameTrackingIdentity?

    var sourceGeneration: ExportFrameSourceGeneration {
        ExportFrameSourceGeneration(snapshot: snapshot)
    }
}

@MainActor
enum ExportFrameSnapshotBuilder {
    static func build(
        frame: ScanFrame,
        sourceIdentity: RenderManifest.SourceIdentity,
        outputURL: URL,
        format: ExportFormat,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        options: ExportOptions,
        printerOutputProfile: ICCOutputProfileSnapshot? = nil,
        printComposition: PrintCompositionSettings? = nil,
        exportRecipeIdentity: ExportRecipeIdentity? = nil,
        scannerModel: String?,
        backendUsed: String?,
        scannerMake: String? = nil,
        scannerDeviceModel: String? = nil,
        metadataDate: Date = Date(),
        appVersion: String = NegaflowProductVersion.applicationVersion(),
        rendererVersion: String = NegaflowProductVersion.rendererVersion,
        sourceFileIdentity: ExportSourceFileIdentity? = nil,
        verificationLevel: ExportVerificationLevel = .default
    ) -> ExportFrameBuildPlan {
        var effectiveParams = frame.preset.map { DevelopParameters(preset: $0, overrides: frame.params) } ?? frame.params
        effectiveParams.filmType = frame.filmType
        effectiveParams.developTarget = frame.params.developTarget
        effectiveParams.imageTransform = frame.imageTransform
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            filmStockDminID: frame.params.filmStockDminID,
            lightSourceProfileID: frame.params.lightSourceProfileID
        )
        let cachedBase = frame.cachedBaseKey == baseKey ? frame.cachedBase : nil
        let useDefectRemoval = format != .rawScanTIFF
        let requiresCleanedRaw = useDefectRemoval && frame.defectEdits.contains {
            $0.enabled && $0.strength > 1e-3
        }
        let cleanedIdentity = frame.boundDefectRecipeIdentity
        // 스캐너 프레임의 scannedAt은 실제 디지털화 시각이다. imported frame의 scannedAt은 현재
        // import 시각이므로 원본 EXIF 촬영/디지털화 시각처럼 내보내지 않는다.
        let sourceDate: Date? = frame.sourceKind == .scannerTIFF ? frame.scannedAt : nil
        let snapshot = ExportFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            sourceIdentity: sourceIdentity,
            sourceKind: frame.sourceKind,
            preloadedRaw: useDefectRemoval ? frame.identityMatchedCleanedRawImage : nil,
            cleanedRawURL: useDefectRemoval ? frame.identityMatchedCleanedRawDiskURL : nil,
            requiresCleanedRaw: requiresCleanedRaw,
            outputURL: outputURL,
            format: format,
            filmType: frame.filmType,
            params: effectiveParams,
            baseMode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            cachedBase: cachedBase,
            scannerMake: scannerMake,
            scannerDeviceModel: scannerDeviceModel,
            scannerModel: scannerModel,
            resolutionDPI: frame.sourceResolutionDPI,
            sourceBitDepth: frame.sourceBitDepth,
            backendUsed: backendUsed,
            presetName: frame.preset?.id,
            scannerProfileID: effectiveParams.scannerProfileID,
            cropRect: frame.imageTransform.cropRect,
            virtualCopy: frame.sidecarVirtualCopyInfo,
            rating: frame.rating,
            pickState: frame.pickState,
            developHistory: frame.developHistory,
            developSnapshots: frame.developSnapshots.map(\.sidecarRecord),
            sourceDate: sourceDate,
            metadataDate: metadataDate,
            appVersion: appVersion,
            rendererVersion: rendererVersion,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw,
            exportOptions: options,
            printerOutputProfile: printerOutputProfile,
            printComposition: printComposition,
            exportRecipeIdentity: exportRecipeIdentity,
            appMetadataOverlay: frame.appMetadataOverlay,
            sourceMetadataSHA256: frame.sourceMetadata?.appMetadataIdentitySHA256(),
            cleanedRawFrameID: cleanedIdentity == nil ? nil : frame.id,
            cleanedRawIdentity: cleanedIdentity,
            sourceFileIdentity: sourceFileIdentity,
            verificationLevel: verificationLevel
        )
        return ExportFrameBuildPlan(
            snapshot: snapshot,
            baseKey: baseKey,
            trackingIdentity: ExportFrameTrackingIdentity.capture(frame: frame, format: format)
        )
    }
}
