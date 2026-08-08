import CoreGraphics
import CoreImage
import XCTest
@testable import Chromabase

/// 출력 양자화처럼 명확한 수학 계약만 검증한다.
///
/// MAIN/PRINT/NORITSU/FUJI/EXPIRED의 색감과 전체 이미지 품질은 단색 패치 평균이나 임의의
/// RGB 임계값으로 판정하지 않는다. 파이프라인 구조와 전 프레임 정보 보존은
/// `DevelopTargetWholeFrameCompositionTests`가 검증하며, 타겟 유사도는 동일 원본의 실제
/// reference 출력과 사람이 확인할 렌더 아티팩트가 있을 때만 평가할 수 있다.
final class PrintBasePipelineDiagnosticTests: XCTestCase {
    /// 8-bit 양자화 경계의 단일 톤이 인접 코드로 분산되고 평균 톤은 보존되는지 검증한다.
    func testOutputDitherDistributesQuantizationBoundary() {
        let width = 48
        let height = 48
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let srgbMid = 200.5 / 255.0
        let linearValue = srgbMid <= 0.04045
            ? srgbMid / 12.92
            : pow((srgbMid + 0.055) / 1.055, 2.4)
        let image = CIImage(
            color: CIColor(
                red: linearValue,
                green: linearValue,
                blue: linearValue,
                colorSpace: linear
            )!
        ).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        let context = CIContext(options: [
            .workingColorSpace: linear,
            .outputColorSpace: srgb,
        ])
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(
            OutputDither.apply(to: image),
            toBitmap: &pixels,
            rowBytes: width * 4,
            bounds: image.extent,
            format: .RGBA8,
            colorSpace: srgb
        )

        var values = Set<Int>()
        var sum = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            values.insert(Int(pixels[offset]))
            sum += Int(pixels[offset])
        }
        let mean = Double(sum) / Double(width * height)

        XCTAssertGreaterThanOrEqual(values.count, 2)
        XCTAssertEqual(mean, 200.5, accuracy: 0.8)
    }
}
