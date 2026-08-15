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
    /// `proxyLongEdge` 를 주면 현상 **전에** 원본을 그 크기로 줄인다. 인화 시트처럼 최종 셀이
    /// 작을 때 풀해상도로 현상한 뒤 줄이면 쓰지도 않을 픽셀을 장마다 계산하게 된다.
    /// 산출물이 요구하는 크기에서 계산하므로 화질 손해 없이 시간과 메모리만 줄어든다.
    static func prepare(
        _ snapshot: ExportFrameSnapshot,
        stagedSourceURL: URL,
        proxyLongEdge: CGFloat? = nil,
        fileManager: FileManager = .default
    ) throws -> ExportDevelopedFrameRender {
        try prepare(
            snapshot,
            sourceAccessURL: stagedSourceURL,
            stagesSource: true,
            proxyLongEdge: proxyLongEdge,
            fileManager: fileManager
        )
    }

    /// 여러 사진을 한 페이지로 합성할 때는 원본을 출력 폴더로 복제하지 않고 직접 읽는다.
    /// 렌더 전후의 source identity 검증은 그대로 유지되므로 원본이 도중에 바뀐 결과는 게시되지 않는다.
    static func prepareForPrintComposite(
        _ snapshot: ExportFrameSnapshot,
        proxyLongEdge: CGFloat,
        fileManager: FileManager = .default
    ) throws -> ExportDevelopedFrameRender {
        try prepare(
            snapshot,
            sourceAccessURL: snapshot.rawScanURL,
            stagesSource: false,
            proxyLongEdge: proxyLongEdge,
            fileManager: fileManager
        )
    }

    /// 출력 픽셀을 만들기에 필요한 입력 긴 변. crop/수평 보정으로 버려질 영역만큼 보수적으로
    /// 더 읽어, 먼저 줄여 읽더라도 최종 셀 해상도는 부족하지 않게 한다.
    static func proxyInputLongEdge(
        outputLongEdge: CGFloat,
        imageTransform: ImageTransform,
        sourcePixelSize: CGSize? = nil
    ) -> CGFloat? {
        guard outputLongEdge.isFinite, outputLongEdge >= 1 else { return nil }
        if let sourcePixelSize,
           let transformedLongEdge = transformedLongEdge(
                sourcePixelSize,
                imageTransform: imageTransform
           ) {
            let sourceLongEdge = max(sourcePixelSize.width, sourcePixelSize.height)
            return outputLongEdge * 1.02 * sourceLongEdge / transformedLongEdge
        }
        var retainedFraction: Double = 1
        if let crop = imageTransform.cropRect {
            guard crop.z.isFinite, crop.w.isFinite, crop.z > 0, crop.w > 0 else { return nil }
            retainedFraction *= min(crop.z, crop.w)
        }
        let radians = abs(imageTransform.straightenAngle) * .pi / 180
        if radians > 1e-6 {
            retainedFraction /= abs(cos(radians)) + abs(sin(radians))
        }
        guard retainedFraction.isFinite, retainedFraction > 0 else { return nil }
        return outputLongEdge * 1.02 / CGFloat(max(retainedFraction, 0.01))
    }

    private static func transformedLongEdge(
        _ sourceSize: CGSize,
        imageTransform: ImageTransform
    ) -> CGFloat? {
        guard sourceSize.width.isFinite,
              sourceSize.height.isFinite,
              sourceSize.width > 0,
              sourceSize.height > 0 else { return nil }
        var width = sourceSize.width
        var height = sourceSize.height
        if imageTransform.rotation == .deg90 || imageTransform.rotation == .deg270 {
            swap(&width, &height)
        }
        if abs(imageTransform.straightenAngle) > 1e-4 {
            let radians = imageTransform.straightenAngle * .pi / 180
            let cosine = abs(cos(radians))
            let sine = abs(sin(radians))
            let insetHeight = min(
                width * height / (width * cosine + height * sine),
                height * height / (width * sine + height * cosine)
            )
            width = width / height * insetHeight
            height = insetHeight
        }
        if let crop = imageTransform.cropRect {
            guard crop.z.isFinite, crop.w.isFinite, crop.z > 0, crop.w > 0 else { return nil }
            width *= crop.z
            height *= crop.w
        }
        let longEdge = max(width, height)
        return longEdge.isFinite && longEdge > 0 ? longEdge : nil
    }

    static func verifyOriginalSourceIdentity(_ snapshot: ExportFrameSnapshot) throws {
        try verifySourceIsUnchanged(snapshot)
    }

    private static func prepare(
        _ snapshot: ExportFrameSnapshot,
        sourceAccessURL: URL,
        stagesSource: Bool,
        proxyLongEdge: CGFloat?,
        fileManager: FileManager
    ) throws -> ExportDevelopedFrameRender {
        guard validSourceIdentity(snapshot.sourceIdentity) else {
            throw ChromabaseError.loadFailed("export source identity changed")
        }
        try verifySourceIsUnchanged(snapshot)
        if stagesSource {
            try fileManager.copyItem(at: snapshot.rawScanURL, to: sourceAccessURL)
            try verifyStagedCopy(snapshot, stagedSourceURL: sourceAccessURL)
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
        // Image I/O thumbnail은 JPEG/PNG 최종 정밀도에는 충분하지만, 16-bit TIFF가 요구하는
        // 입력 정밀도까지 계약하지는 않는다. TIFF16은 원본 정밀도로 decode하고 CI graph의
        // scale을 develop 앞에 두어 계산량만 줄인다.
        let decodeProxyLongEdge = snapshot.format == .tiff16 ? nil : proxyLongEdge
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
            if verified, let cleaned = loadCleanedSource(
                cleanedRawURL,
                proxyLongEdge: decodeProxyLongEdge
            ) {
                rawInput = cleaned.image
                selectedInputKind = .cleanedFile
                selectedDecodeProvenance = cleaned.provenance
            } else if snapshot.requiresCleanedRaw {
                throw ChromabaseError.loadFailed(cleanedRawURL.path)
            } else if let source = loadSource(
                snapshot,
                sourceURL: sourceAccessURL,
                proxyLongEdge: decodeProxyLongEdge
            ) {
                rawInput = source.image
                selectedInputKind = .source
                selectedDecodeProvenance = source.provenance
            } else {
                throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
            }
        } else if snapshot.requiresCleanedRaw {
            throw ChromabaseError.loadFailed("required cleaned raw is unavailable")
        } else if let source = loadSource(
            snapshot,
            sourceURL: sourceAccessURL,
            proxyLongEdge: decodeProxyLongEdge
        ) {
            rawInput = source.image
            selectedInputKind = .source
            selectedDecodeProvenance = source.provenance
        } else {
            throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
        }

        let developInput = downscaledIfNeeded(rawInput, longEdge: proxyLongEdge)
        let engine = ChromabaseEngine()
        let base = snapshot.format != .rawScanTIFF && snapshot.filmType.requiresInversion
            ? snapshot.cachedBase ?? engine.estimateFilmBase(
                in: developInput,
                mode: snapshot.baseMode,
                manual: snapshot.manualBaseRGB,
                filmStockDminID: snapshot.params.filmStockDminID,
                lightSourceProfileID: snapshot.params.lightSourceProfileID,
                filmType: snapshot.filmType
            )
            : nil
        let developedImage = snapshot.format == .rawScanTIFF
            ? rawInput
            : engine.developScanner(image: developInput, base: base, params: snapshot.params)

        return ExportDevelopedFrameRender(
            rawInput: rawInput,
            selectedInputKind: selectedInputKind,
            selectedDecodeProvenance: selectedDecodeProvenance,
            base: base,
            developedImage: developedImage
        )
    }

    /// 요청 크기보다 큰 원본만 줄인다. 확대는 하지 않는다 — 없는 해상도를 만들지 않는다.
    private static func downscaledIfNeeded(_ image: CIImage, longEdge: CGFloat?) -> CIImage {
        guard let longEdge, longEdge >= 1 else { return image }
        let extent = image.extent
        let currentLongEdge = max(extent.width, extent.height)
        guard currentLongEdge.isFinite,
              currentLongEdge > longEdge * 1.05,
              extent.width > 0,
              extent.height > 0 else { return image }
        let scale = longEdge / currentLongEdge
        return image
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1,
            ])
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
        sourceURL: URL,
        proxyLongEdge: CGFloat?
    ) -> LoadedSource? {
        if let proxyLongEdge,
           let preview = snapshot.sourceKind == .importedFile
            ? ImageLoader.loadImportedPreview(
                sourceURL,
                maxDimension: proxyLongEdge,
                highResolutionThreshold: proxyLongEdge,
                rawRendering: .forDigitalSource(snapshot.params.isDigitalSource)
            )
            : ImageLoader.loadScannerPreview(
                sourceURL,
                maxDimension: proxyLongEdge,
                highResolutionThreshold: proxyLongEdge
            ) {
            return LoadedSource(image: preview.image, provenance: nil)
        }
        let decoded = snapshot.sourceKind == .importedFile
            ? ImageLoader.loadImportedDecoded(
                sourceURL,
                rawRendering: .forDigitalSource(snapshot.params.isDigitalSource)
            )
            : ImageLoader.loadScannerTIFFDecoded(sourceURL)
        return decoded.map { LoadedSource(image: $0.image, provenance: $0.provenance) }
    }

    private static func loadCleanedSource(
        _ sourceURL: URL,
        proxyLongEdge: CGFloat?
    ) -> LoadedSource? {
        if let proxyLongEdge,
           let preview = ImageLoader.loadScannerPreview(
                sourceURL,
                maxDimension: proxyLongEdge,
                highResolutionThreshold: proxyLongEdge
           ) {
            return LoadedSource(image: preview.image, provenance: nil)
        }
        return ImageLoader.loadScannerTIFFDecoded(sourceURL).map {
            LoadedSource(image: $0.image, provenance: $0.provenance)
        }
    }

    private struct LoadedSource {
        let image: CIImage
        let provenance: ImageLoader.DecodeProvenance?
    }

    private static func validSourceIdentity(_ identity: RenderManifest.SourceIdentity) -> Bool {
        identity.byteCount > 0
            && identity.sha256.utf8.count == 64
            && identity.sha256.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }
}
