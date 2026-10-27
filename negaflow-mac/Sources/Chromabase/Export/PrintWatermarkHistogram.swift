import CoreGraphics
import CoreImage
import Foundation

/// 워터마크 히스토그램의 열 값(0...1). 화면 미리보기와 내보내기가 같은 크기로 줄여 같은 식으로 센다.
public enum PrintWatermarkHistogram {
    /// 이 긴 변까지 줄여 센다. 점 그래프는 32열 × 8행이라 이보다 촘촘한 표본은 결과를 바꾸지 않는다.
    static let sampleLongEdge: CGFloat = 256

    /// sRGB 로 표시되는 밝기(Rec. 709 가중치)의 분포. 가장 높은 열을 1 로 맞춘다.
    public static func columns(
        of image: CIImage,
        count: Int = PrintWatermarkMetrics.histogramColumns,
        context: CIContext
    ) -> [Double]? {
        let extent = image.extent
        guard count > 0,
              extent.width.isFinite, extent.height.isFinite,
              extent.width >= 1, extent.height >= 1 else { return nil }
        let scale = min(1, sampleLongEdge / max(extent.width, extent.height))
        let normalized = image.transformed(by: CGAffineTransform(
            translationX: -extent.minX,
            y: -extent.minY
        ))
        let sample = scale < 1
            ? normalized.applyingFilter(
                "CILanczosScaleTransform",
                parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1]
            )
            : normalized
        let width = max(1, Int(sample.extent.width.rounded(.down)))
        let height = max(1, Int(sample.extent.height.rounded(.down)))
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            sample,
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: srgb
        )
        var bins = [Double](repeating: 0, count: count)
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] == 255 {
            let luma = 0.2126 * Double(pixels[index])
                + 0.7152 * Double(pixels[index + 1])
                + 0.0722 * Double(pixels[index + 2])
            bins[min(count - 1, Int(luma * Double(count) / 256))] += 1
        }
        guard let peak = bins.max(), peak > 0 else { return bins }
        return bins.map { $0 / peak }
    }
}
