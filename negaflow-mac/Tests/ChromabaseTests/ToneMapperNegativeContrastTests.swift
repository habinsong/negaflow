import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

final class ToneMapperNegativeContrastTests: XCTestCase {
    func testNegativeContrastPreservesBlackPointInsteadOfFloatingWhite() {
        let input = makeLinearRamp()
        let baseline = renderLinearRGBA8(ToneMapper.applyToneCurves(to: input, params: DevelopParameters()))
        var params = DevelopParameters()
        params.contrast = -1

        let softened = renderLinearRGBA8(ToneMapper.applyToneCurves(to: input, params: params))

        XCTAssertLessThan(
            meanLuma(softened, xRange: 0..<1),
            2,
            "Contrast -1이 절대 검정을 회색으로 들어올리면 이미지가 하얗게 붕뜹니다."
        )
        XCTAssertLessThan(
            meanLuma(softened, xRange: 0..<4),
            meanLuma(baseline, xRange: 0..<4) + 4,
            "Contrast -1이 near-black 톤을 baseline보다 과하게 띄우면 안 됩니다."
        )
        XCTAssertLessThan(
            meanLuma(softened, xRange: 4..<16),
            meanLuma(baseline, xRange: 4..<16) + 18,
            "Contrast -1은 저역 대비를 부드럽게 해야지 검은 영역 전체를 백화시키면 안 됩니다."
        )
    }

    private func makeLinearRamp(width: Int = 128, height: Int = 32) -> CIImage {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 1, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = Float(x) / Float(width - 1)
                let offset = (y * width + x) * 4
                pixels[offset] = value * 1.04
                pixels[offset + 1] = value
                pixels[offset + 2] = value * 0.94
            }
        }
        return CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf,
            colorSpace: linear
        )
    }

    private func renderLinearRGBA8(_ image: CIImage, width: Int = 128, height: Int = 32) -> [UInt8] {
        let ctx = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        var rendered = [UInt8](repeating: 0, count: width * height * 4)
        ctx.render(
            image,
            toBitmap: &rendered,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return rendered
    }

    private func meanLuma(_ rgba: [UInt8], xRange: Range<Int>, width: Int = 128, height: Int = 32) -> Double {
        var sum = 0.0
        var count = 0
        for y in 4..<(height - 4) {
            for x in xRange {
                let i = (y * width + x) * 4
                sum += Double(rgba[i]) * 0.2126
                    + Double(rgba[i + 1]) * 0.7152
                    + Double(rgba[i + 2]) * 0.0722
                count += 1
            }
        }
        return sum / Double(count)
    }
}
