import AppKit
import Chromabase

extension ScanFrame {
    /// 인화 화면이 종이 위에 얹는 사진.
    ///
    /// 화면용 현상 결과는 원근 보정의 빈 곳이 투명하다. 현상 캔버스는 그 밑에 흰 바탕을 깔지만, 인화
    /// 화면은 사진을 시트(검정·회색·흰색) 위에 바로 놓으므로 빈 곳이 시트 색으로 보였다. 내보낸 인화는
    /// 빈 곳이 흰색이다 — 그와 같게 흰색으로 덮은 그림을 한 번 만들어 둔다. 빈 곳이 없으면 그대로 쓴다.
    var printPresentationImage: NSImage? {
        guard let developed = developedImage else { return thumbnailImage }
        let transform = developedPreviewTransform ?? imageTransform
        guard transform.perspective.leavesUncoveredArea else { return developed }
        let key = ObjectIdentifier(developed)
        if let cached = printPresentationCache, cached.source == key { return cached.image }
        guard let flattened = Self.flattenedOverWhite(developed) else { return developed }
        printPresentationCache = (key, flattened)
        return flattened
    }

    private static func flattenedOverWhite(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let space = cg.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(cg, in: bounds)
        guard let opaque = context.makeImage() else { return nil }
        return NSImage(cgImage: opaque, size: image.size)
    }
}
