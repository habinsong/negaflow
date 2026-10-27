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

/// 띠 포함 미리보기를 다시 그릴지 가르는 열쇠. 화면 이미지(객체)가 바뀌거나 설정이 바뀌면 다시 그린다.
struct PrintFramedPreviewRequest: Equatable, Sendable {
    let imageID: ObjectIdentifier
    /// 블러 바탕·히스토그램에 쓰는 필름스트립 썸네일. 바뀌면 다시 그린다.
    let referenceID: ObjectIdentifier?
    let settings: PrintCompositionSettings
}

struct PrintFramedPreview: @unchecked Sendable {
    let request: PrintFramedPreviewRequest
    let image: NSImage

    /// 내보내기와 같은 `PrintCompositionRenderer.placedUnit` 으로 그린다. 화면 이미지는 이미 화면
    /// 해상도이므로 원본을 다시 풀지 않는다.
    static func render(
        _ request: PrintFramedPreviewRequest,
        image: CGImage,
        reference: CGImage?
    ) -> PrintFramedPreview? {
        let context = ChromabaseEngine.sharedLinearRenderContext
        guard let unit = PrintCompositionRenderer.placedUnit(
            for: CIImage(cgImage: image),
            settings: request.settings,
            reference: reference.map { CIImage(cgImage: $0) },
            context: context
        ) else { return nil }
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
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
