import AppKit
import Chromabase
import CoreImage

/// 인화 한 장의 화면 배치. 워터마크가 켜져 있으면 `unitFrame` 이 띠와 사진 자리를 담는다.
struct PrintPagePlan {
    let composition: PrintCompositionSettings
    let layout: PrintCompositionLayout
    let unitFrame: PrintWatermarkFrameLayout?
    /// 판 좌표의 사진 자리(띠 제외). 색역 경고 겹침이 여기에 붙는다.
    let photoRect: CGRect
}

/// 화면 이미지나 출력 방식이 바뀌면 미리보기를 다시 그린다.
struct PrintFramedPreviewRequest: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case presentation(PrintPresentationStyle)
        case framed(PrintCompositionSettings)
    }

    /// 어느 사진의 미리보기인지. 새로 그리는 동안 직전 결과를 보여 줄 때 다른 사진의 것을 걸지 않는다.
    let frameID: ObjectIdentifier
    let imageID: ObjectIdentifier
    /// 블러 바탕·히스토그램에 쓰는 필름스트립 썸네일. 바뀌면 다시 그린다.
    let referenceID: ObjectIdentifier?
    let content: Content
}

struct PrintFramedPreview: @unchecked Sendable {
    let request: PrintFramedPreviewRequest
    let image: NSImage

    /// 내보내기와 같은 렌더러에 화면 해상도의 이미지를 넘긴다.
    static func render(
        _ request: PrintFramedPreviewRequest,
        image: CGImage,
        reference: CGImage?
    ) -> PrintFramedPreview? {
        let context = ChromabaseEngine.sharedLinearRenderContext
        let source = CIImage(cgImage: image)
        let unit: CIImage
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? srgb
        switch request.content {
        case let .presentation(style):
            unit = PrintPresentationRenderer.apply(to: source, style: style)
        case let .framed(settings):
            guard let placed = PrintCompositionRenderer.placedUnit(
                for: source,
                settings: settings,
                reference: reference.map { CIImage(cgImage: $0) },
                context: context
            ) else { return nil }
            unit = placed
        }
        guard let output = context.createCGImage(
            unit,
            from: unit.extent,
            format: .RGBA8,
            colorSpace: space
        ) else { return nil }
        return PrintFramedPreview(
            request: request,
            image: NSImage(cgImage: output, size: NSSize(width: output.width, height: output.height))
        )
    }
}
