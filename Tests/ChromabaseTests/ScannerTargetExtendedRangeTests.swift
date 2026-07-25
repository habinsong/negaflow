import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

final class ScannerTargetExtendedRangeTests: XCTestCase {
    func testRelativeScannerGradePreservesValuesOutsideMeasuredCubeDomain() {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let source: [Float] = [
            -0.05, 0.20, 0.30, 1,
             0.20, 0.40, 1.10, 1,
             0.35, 0.50, 0.65, 1,
        ]
        let image = CIImage(
            bitmapData: Data(bytes: source, count: source.count * MemoryLayout<Float>.size),
            bytesPerRow: 3 * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: 3, height: 1),
            format: .RGBAf,
            colorSpace: linear
        )
        let signature = ScannerTargetGrade.Signature(
            tone: ScannerTargetGrade.designToneXs.map { min($0 + 0.08, 0.998) },
            neutralBins: [],
            hueAnchors: []
        )

        let output = ScannerTargetGrade.apply(
            to: image,
            signature: signature,
            target: .noritsu
        )
        let rendered = render(output, colorSpace: linear)

        for pixel in 0..<2 {
            for channel in 0..<3 {
                let index = pixel * 4 + channel
                XCTAssertEqual(
                    rendered[index],
                    source[index],
                    accuracy: 1e-5,
                    "measured cube 밖의 작업값을 endpoint로 clamp하면 안 됩니다"
                )
            }
        }
        XCTAssertGreaterThan(
            abs(rendered[2 * 4 + 1] - source[2 * 4 + 1]),
            0.01,
            "[0,1] 안의 픽셀에는 상대 scanner tone이 적용되어야 합니다"
        )
    }

    private func render(_ image: CIImage, colorSpace: CGColorSpace) -> [Float] {
        let context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .workingFormat: CIFormat.RGBAf,
        ])
        var pixels = [Float](repeating: 0, count: 3 * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: 3 * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 3, height: 1),
            format: .RGBAf,
            colorSpace: colorSpace
        )
        return pixels
    }
}
