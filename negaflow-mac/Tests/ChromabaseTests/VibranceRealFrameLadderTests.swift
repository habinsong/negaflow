import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// 실제 사진 버퍼를 amount 사다리로 통과시킨 결과(REQUEST-4 요청 C 의 대체안).
///
/// 요청 C 는 "다른 사진 한 쌍"을 원했지만, 지금 있는 스캔 중 vibrance 가 실제로 도는 것은
/// `GT-X900_frame_4` 하나뿐이다 — 나머지는 전부 채도가 높아
/// `amount = min(0.5, max(0, (0.24 − meanSat) × 3))` 이 0 이 되고 단계를 건너뛴다
/// (8100 frame_1 meanSat 0.4099, color_nega 0.3417, fa_2_colornegative 0.4032,
/// fa_color_negative_2x2slot 0.2634 — 모두 amount 0.000).
///
/// 대신 같은 사진의 vibrance **입력 버퍼**를 여러 amount 로 통과시켜 준다. 격자가 아니라
/// 실제 화소 분포이므로 "격자에 맞추고 사진에서 틀리는" 것을 잡는 목적은 그대로 달성된다.
///
/// ```
/// NEGAFLOW_VIBRANCE_GOLDEN_DIR=/path/to/docs/verification/macos-golden/vibrance \
/// swift test --filter VibranceRealFrameLadderTests
/// ```
final class VibranceRealFrameLadderTests: XCTestCase {
    private static let width = 320
    private static let height = 488
    private static let amounts: [Double] = [0.05, 0.10, 0.15, 0.25, 0.35, 0.50]

    func testEmitsRealFrameAmountLadder() throws {
        guard let raw = ProcessInfo.processInfo.environment["NEGAFLOW_VIBRANCE_GOLDEN_DIR"],
              !raw.isEmpty else {
            throw XCTSkip("NEGAFLOW_VIBRANCE_GOLDEN_DIR 를 지정하면 사다리를 생성합니다.")
        }
        let directory = URL(fileURLWithPath: raw, isDirectory: true)
        let source = directory.appendingPathComponent(
            "frame4-preview-\(Self.width)x\(Self.height).f32"
        )
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: source.path),
            "frame4-preview 덤프가 먼저 있어야 합니다(NEGA_DUMP_PROXY 로 생성)."
        )

        let data = try Data(contentsOf: source)
        let expected = Self.width * Self.height * 4 * MemoryLayout<Float>.size
        XCTAssertEqual(data.count, expected, "덤프 크기가 320×488 RGBAf 가 아닙니다")

        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let rowBytes = Self.width * 4 * MemoryLayout<Float>.size
        let image = CIImage(
            bitmapData: data,
            bytesPerRow: rowBytes,
            size: CGSize(width: Self.width, height: Self.height),
            format: .RGBAf,
            colorSpace: linear
        )
        let context = SamplingContextPool.context(workingColorSpace: linear)

        for amount in Self.amounts {
            let output = image
                .applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
                .cropped(to: image.extent)
            var bitmap = [Float](repeating: 0, count: Self.width * Self.height * 4)
            bitmap.withUnsafeMutableBytes { buffer in
                context.render(
                    output,
                    toBitmap: buffer.baseAddress!,
                    rowBytes: rowBytes,
                    bounds: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                    format: .RGBAf,
                    colorSpace: linear
                )
            }
            let name = String(
                format: "frame4-postvib-a%.3f-%dx%d.f32", amount, Self.width, Self.height
            )
            try bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
                .write(to: directory.appendingPathComponent(name), options: .atomic)
        }
    }
}
