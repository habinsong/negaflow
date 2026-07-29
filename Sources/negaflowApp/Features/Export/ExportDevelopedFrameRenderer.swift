import Chromabase
import CoreGraphics
import CoreImage
import Foundation

struct ExportDevelopedFrameRender {
    let rawInput: CIImage
    let selectedInputKind: RenderManifest.RenderInputKind
    let selectedDecodeProvenance: ImageLoader.DecodeProvenance?
    let base: FilmBase?
    let developedImage: CIImage
}

enum ExportDevelopedFrameRenderer {
    static func prepare(
        _ snapshot: ExportFrameSnapshot,
        stagedSourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> ExportDevelopedFrameRender {
        guard validSourceIdentity(snapshot.sourceIdentity) else {
            throw ChromabaseError.loadFailed("export source identity changed")
        }
        try verifySourceIsUnchanged(snapshot)
        try fileManager.copyItem(at: snapshot.rawScanURL, to: stagedSourceURL)
        try verifyStagedCopy(snapshot, stagedSourceURL: stagedSourceURL)

        let currentDefectSourceIdentity = try? AppModel.defectSourceIdentity(
            for: snapshot.rawScanURL
        )
        if snapshot.requiresCleanedRaw {
            guard let bound = snapshot.cleanedRawIdentity?.sourceIdentity,
                  bound == currentDefectSourceIdentity,
                  UInt64(snapshot.sourceIdentity.byteCount) == bound.byteCount else {
                throw ChromabaseError.loadFailed("required cleaned raw source identity changed")
            }
        }

        let rawInput: CIImage
        let selectedInputKind: RenderManifest.RenderInputKind
        let selectedDecodeProvenance: ImageLoader.DecodeProvenance?
        if let preloaded = snapshot.preloadedRaw {
            guard !snapshot.requiresCleanedRaw || snapshot.cleanedRawIdentity?.sourceIdentity != nil else {
                throw ChromabaseError.loadFailed("required cleaned raw identity is unavailable")
            }
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            rawInput = CIImage(cgImage: preloaded, options: [.colorSpace: linear])
            selectedInputKind = .cleanedMemory
            selectedDecodeProvenance = nil
        } else if let cleanedRawURL = snapshot.cleanedRawURL {
            let verified = snapshot.cleanedRawFrameID.map { frameID in
                snapshot.cleanedRawIdentity?.sourceIdentity != nil
                    && snapshot.cleanedRawIdentity?.sourceIdentity == currentDefectSourceIdentity
                    && CleanedRawCacheFile.isOwnedCacheURL(cleanedRawURL, frameID: frameID)
            } ?? false
            if verified, let cleaned = ImageLoader.loadScannerTIFFDecoded(cleanedRawURL) {
                rawInput = cleaned.image
                selectedInputKind = .cleanedFile
                selectedDecodeProvenance = cleaned.provenance
            } else if snapshot.requiresCleanedRaw {
                throw ChromabaseError.loadFailed(cleanedRawURL.path)
            } else if let source = loadSource(snapshot, sourceURL: stagedSourceURL) {
                rawInput = source.image
                selectedInputKind = .source
                selectedDecodeProvenance = source.provenance
            } else {
                throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
            }
        } else if snapshot.requiresCleanedRaw {
            throw ChromabaseError.loadFailed("required cleaned raw is unavailable")
        } else if let source = loadSource(snapshot, sourceURL: stagedSourceURL) {
            rawInput = source.image
            selectedInputKind = .source
            selectedDecodeProvenance = source.provenance
        } else {
            throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
        }

        let engine = ChromabaseEngine()
        let base = snapshot.format != .rawScanTIFF && snapshot.filmType.requiresInversion
            ? snapshot.cachedBase ?? engine.estimateFilmBase(
                in: rawInput,
                mode: snapshot.baseMode,
                manual: snapshot.manualBaseRGB,
                filmStockDminID: snapshot.params.filmStockDminID,
                lightSourceProfileID: snapshot.params.lightSourceProfileID,
                filmType: snapshot.filmType
            )
            : nil
        let developedImage = snapshot.format == .rawScanTIFF
            ? rawInput
            : engine.developScanner(image: rawInput, base: base, params: snapshot.params)

        return ExportDevelopedFrameRender(
            rawInput: rawInput,
            selectedInputKind: selectedInputKind,
            selectedDecodeProvenance: selectedDecodeProvenance,
            base: base,
            developedImage: developedImage
        )
    }

    static func verifySourceIdentity(
        _ snapshot: ExportFrameSnapshot,
        stagedSourceURL: URL
    ) throws {
        try verifyStagedCopy(snapshot, stagedSourceURL: stagedSourceURL)
        try verifySourceIsUnchanged(snapshot)
    }

    /// 원본이 snapshot 세대 그대로인지 확인한다. standard 는 stat identity 가 그대로면 통과하고,
    /// 하나라도 다르면 전체 해시로 실제 판정한다(바뀌지 않았는데 실패하는 경우를 만들지 않는다).
    private static func verifySourceIsUnchanged(_ snapshot: ExportFrameSnapshot) throws {
        if !snapshot.verificationLevel.rehashesOnRecheck,
           let expected = snapshot.sourceFileIdentity,
           ExportArtifactFileIdentityInspector.sourceFile(at: snapshot.rawScanURL) == expected {
            return
        }
        guard try RenderManifest.sourceIdentity(for: snapshot.rawScanURL)
                == snapshot.sourceIdentity else {
            throw ChromabaseError.loadFailed("export source identity changed")
        }
    }

    /// 스테이징 사본이 snapshot 세대의 바이트인지 확인한다. standard 는 "원본이 그대로 + 사본 길이가
    /// 같음"으로 판정한다 — 성공한 copyItem 과 변하지 않은 원본이면 사본은 그 바이트다.
    /// strict 는 사본 전체를 다시 해시해 그 추론까지 확인한다.
    private static func verifyStagedCopy(
        _ snapshot: ExportFrameSnapshot,
        stagedSourceURL: URL
    ) throws {
        if !snapshot.verificationLevel.rehashesOnRecheck, snapshot.sourceFileIdentity != nil {
            try verifySourceIsUnchanged(snapshot)
            // copyItem 은 심볼릭 링크를 따라가지 않고 링크 자체를 복사한다. 해시 경로가
            // resolvingSymlinksInPath 로 대상 파일을 읽는 것과 같은 대상을 재도록 여기서도 푼다.
            let resolved = stagedSourceURL.resolvingSymlinksInPath()
            let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            guard let size, Int64(size) == snapshot.sourceIdentity.byteCount else {
                throw ChromabaseError.loadFailed("export source changed while staging")
            }
            return
        }
        guard try RenderManifest.sourceIdentity(for: stagedSourceURL)
                == snapshot.sourceIdentity else {
            throw ChromabaseError.loadFailed("export source changed while staging")
        }
    }

    private static func loadSource(
        _ snapshot: ExportFrameSnapshot,
        sourceURL: URL
    ) -> ImageLoader.DecodedImage? {
        snapshot.sourceKind == .importedFile
            ? ImageLoader.loadImportedDecoded(sourceURL)
            : ImageLoader.loadScannerTIFFDecoded(sourceURL)
    }

    private static func validSourceIdentity(_ identity: RenderManifest.SourceIdentity) -> Bool {
        identity.byteCount > 0
            && identity.sha256.utf8.count == 64
            && identity.sha256.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}
