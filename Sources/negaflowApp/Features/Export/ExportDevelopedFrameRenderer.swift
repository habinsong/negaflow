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
        guard validSourceIdentity(snapshot.sourceIdentity),
              try RenderManifest.sourceIdentity(for: snapshot.rawScanURL) == snapshot.sourceIdentity else {
            throw ChromabaseError.loadFailed("export source identity changed")
        }
        try fileManager.copyItem(at: snapshot.rawScanURL, to: stagedSourceURL)
        guard try RenderManifest.sourceIdentity(for: stagedSourceURL) == snapshot.sourceIdentity else {
            throw ChromabaseError.loadFailed("export source changed while staging")
        }

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
        guard try RenderManifest.sourceIdentity(for: stagedSourceURL) == snapshot.sourceIdentity,
              try RenderManifest.sourceIdentity(for: snapshot.rawScanURL) == snapshot.sourceIdentity else {
            throw ChromabaseError.loadFailed("export source identity changed")
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
