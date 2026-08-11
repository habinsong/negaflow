import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit
import Metal

extension DevelopFrameRenderer {
    static func renderRawPreview(_ snapshot: DevelopFrameSnapshot) throws -> CGImage {
        let engine = ChromabaseEngine()
        let context = renderContext()
        guard let input = resolveRenderInput(snapshot, engine: engine, context: context) else {
            throw loadError(for: snapshot)
        }
        return try renderRawPreview(
            from: displayProxy(input.image, maxDimension: snapshot.proxyMaxDimension),
            transform: snapshot.imageTransform,
            context: context
        ).transformed
    }

    struct RenderInput {
        let image: CIImage
        let generatedPreviewRaw: DevelopFramePreviewRaw?
    }

    /// 입력을 못 구한 이유를 가른다. cleaned raw 를 기다리는 중이면 실패가 아니라 보류다 —
    /// 사용자에게 "이미지 로드 실패"를 띄우거나 진단에 실패로 남기면 안 된다.
    static func loadError(for snapshot: DevelopFrameSnapshot) -> DevelopFrameRenderError {
        snapshot.requiresCleanedRaw
            && snapshot.preloadedRaw == nil
            && verifiedCleanedRawURL(snapshot) == nil
            ? .cleanedRawPending
            : .loadFailed
    }

    static func resolveRenderInput(
        _ snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) -> RenderInput? {
        let verifiedCleanedRawURL = verifiedCleanedRawURL(snapshot)
        if snapshot.requiresCleanedRaw,
           snapshot.preloadedRaw == nil,
           verifiedCleanedRawURL == nil {
            return nil
        }
        if let cached = snapshot.preloadedPreviewRaw {
            return RenderInput(image: ciImage(from: cached), generatedPreviewRaw: nil)
        }
        // 요청 치수 캐시가 없어도 정착(풀) raw 프록시가 있으면 GPU 다운스케일로 파생한다.
        // 수십 MP 원본을 디스크에서 재디코딩(수백 ms)하는 대신 한 번의 Lanczos 축소로 끝난다.
        if let full = snapshot.preloadedFullPreviewRaw {
            let fullImage = ciImage(from: full)
            let extent = fullImage.extent.integral
            if max(extent.width, extent.height) <= snapshot.proxyMaxDimension {
                return RenderInput(image: fullImage, generatedPreviewRaw: nil)
            }
            if let proxy = materializedPreviewRaw(
                displayProxy(fullImage, maxDimension: snapshot.proxyMaxDimension),
                usesLinearSRGB: full.usesLinearSRGB,
                context: rawProxyContext(usesLinearSRGB: full.usesLinearSRGB)
            ) {
                return RenderInput(image: ciImage(from: proxy), generatedPreviewRaw: proxy)
            }
        }
        // 활성 프레임의 메모리 결함 제거 raw(cleanedRawImage)는 항상 최신이다 — 커밋 시 동기 갱신되는 반면
        // 디스크 백킹(cleanedRawURL)은 커밋 후 비동기로 저장된다. 여기서 메모리 raw 를 프록시로 파생해,
        // 저장 지연으로 아직 stale/부재한 cleanedRawURL(→원본)로 내려가 방금 제거한 결함이 되살아나거나
        // 반영이 안 되는(브러시·가이드 오락가락) 문제를 막는다. 메모리가 없을 때만 아래 디스크/원본으로 폴백.
        if let pre = snapshot.preloadedRaw {
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            let fullImage = CIImage(cgImage: pre, options: [.colorSpace: linear])
            let extent = fullImage.extent.integral
            if max(extent.width, extent.height) <= snapshot.proxyMaxDimension {
                return RenderInput(image: fullImage, generatedPreviewRaw: nil)
            }
            if let proxy = materializedPreviewRaw(
                displayProxy(fullImage, maxDimension: snapshot.proxyMaxDimension),
                usesLinearSRGB: true,
                context: rawProxyContext(usesLinearSRGB: true)
            ) {
                return RenderInput(image: ciImage(from: proxy), generatedPreviewRaw: proxy)
            }
        }
        if let preview = resolvePreviewInput(
            snapshot,
            cleanedRawURL: verifiedCleanedRawURL
        ) {
            let proxy = materializedPreviewRaw(
                preview.image,
                usesLinearSRGB: preview.usesLinearSRGB,
                context: rawProxyContext(usesLinearSRGB: preview.usesLinearSRGB)
            )
            return RenderInput(
                image: proxy.map(ciImage(from:)) ?? preview.image,
                generatedPreviewRaw: proxy
            )
        }
        guard let rawInput = resolveRawInput(
            snapshot,
            engine: engine,
            cleanedRawURL: verifiedCleanedRawURL
        ) else { return nil }
        guard shouldCachePreviewInput(rawInput.extent, maxDimension: snapshot.proxyMaxDimension) else {
            return RenderInput(image: rawInput, generatedPreviewRaw: nil)
        }
        let usesLinear = snapshot.preloadedRaw != nil
            || verifiedCleanedRawURL != nil
            || rawInput.colorSpace?.name == CGColorSpace(name: CGColorSpace.linearSRGB)?.name
        let proxy = materializedPreviewRaw(
            displayProxy(rawInput, maxDimension: snapshot.proxyMaxDimension),
            usesLinearSRGB: usesLinear,
            context: rawProxyContext(usesLinearSRGB: usesLinear)
        )
        return RenderInput(
            image: proxy.map(ciImage(from:)) ?? rawInput,
            generatedPreviewRaw: proxy
        )
    }

    private static func resolvePreviewInput(
        _ snapshot: DevelopFrameSnapshot,
        cleanedRawURL: URL?
    ) -> ImageLoader.PreviewImage? {
        if let url = cleanedRawURL {
            return ImageLoader.loadScannerPreview(
                url,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        }
        switch snapshot.sourceKind {
        case .scannerTIFF:
            return ImageLoader.loadScannerPreview(
                snapshot.rawScanURL,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        case .importedFile:
            return ImageLoader.loadImportedPreview(
                snapshot.rawScanURL,
                maxDimension: snapshot.proxyMaxDimension,
                highResolutionThreshold: fullMaxDimension
            )
        }
    }

    private static func materializedPreviewRaw(
        _ input: CIImage,
        usesLinearSRGB: Bool,
        context: CIContext
    ) -> DevelopFramePreviewRaw? {
        let colorSpace = usesLinearSRGB
            ? CGColorSpace(name: CGColorSpace.linearSRGB)!
            : CGColorSpace(name: CGColorSpace.sRGB)!
        let format: CIFormat = usesLinearSRGB ? .RGBA16 : .RGBA8
        guard let cg = context.createCGImage(input, from: input.extent.integral, format: format, colorSpace: colorSpace) else {
            return nil
        }
        return DevelopFramePreviewRaw(image: cg, usesLinearSRGB: usesLinearSRGB)
    }

    private static func ciImage(from preview: DevelopFramePreviewRaw) -> CIImage {
        if preview.usesLinearSRGB {
            return CIImage(cgImage: preview.image, options: [.colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!])
        }
        return CIImage(cgImage: preview.image)
    }

    private static func rawProxyContext(usesLinearSRGB: Bool) -> CIContext {
        usesLinearSRGB ? linearRawProxyContext : srgbRawProxyContext
    }

    private static func shouldCachePreviewInput(_ extent: CGRect, maxDimension: CGFloat) -> Bool {
        guard maxDimension > 0, extent.width > 0, extent.height > 0 else { return false }
        return max(extent.width, extent.height) > fullMaxDimension
            && max(extent.width, extent.height) > maxDimension
    }

    /// 우선순위: 결함 제거 메모리 raw → 결함 제거 디스크 백킹 → 원본 파일. 앞 둘이면 결함 제거가 반영된다.
    private static func resolveRawInput(
        _ snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        cleanedRawURL: URL?
    ) -> CIImage? {
        if let pre = snapshot.preloadedRaw {
            let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
            return CIImage(cgImage: pre, options: [.colorSpace: linear])
        }
        if let url = cleanedRawURL, let ci = ImageLoader.loadScannerTIFF(url) {
            return ci
        }
        if snapshot.requiresCleanedRaw { return nil }
        // 원본 파일 로드는 출처에 따라 분기한다. 스캐너 TIFF는 임베디드 ICC를 존중하고 프로필 없는
        // 16bit raw만 linear로 해석한다. 가져온 파일은 RAW 데모사이크와 동일한 프로필 규칙을 쓴다.
        switch snapshot.sourceKind {
        case .scannerTIFF:  return engine.loadScannerImage(snapshot.rawScanURL)
        case .importedFile: return engine.loadImportedImage(snapshot.rawScanURL)
        }
    }

    private static func verifiedCleanedRawURL(_ snapshot: DevelopFrameSnapshot) -> URL? {
        guard let url = snapshot.cleanedRawURL else { return nil }
        if snapshot.cleanedRawFrameID == nil, snapshot.cleanedRawIdentity == nil {
            return url
        }
        guard let frameID = snapshot.cleanedRawFrameID,
              let identity = snapshot.cleanedRawIdentity,
              identity.sourceIdentity != nil,
              CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frameID) else { return nil }
        return url
    }


}
