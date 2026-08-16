import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// `CIVibrance` 의 **사상**을 알려진 격자로 뽑아 준다(REQUEST-3 요청 A).
///
/// Apple 내장 필터라 커널 소스가 없다. 수식을 추측해 옮기는 대신 입출력 격자를 넘겨
/// Windows 포팅본이 값으로 맞추게 한다.
///
/// ```
/// NEGAFLOW_VIBRANCE_GOLDEN_DIR=/path/to/docs/verification/macos-golden/vibrance \
/// swift test --filter VibranceMappingGoldenTests
/// ```
final class VibranceMappingGoldenTests: XCTestCase {
    /// 17³ = 4913 격자. 128 × 39 = 4992 화소 중 앞 4913 만 채우고 나머지는 0.
    private static let width = 128
    private static let height = 39
    private static let gridCount = 4_913
    private static let amounts: [Double] = [0.0, 0.1, 0.252, 0.259, 0.5]

    func testEmitsVibranceMappingGrid() throws {
        guard let raw = ProcessInfo.processInfo.environment["NEGAFLOW_VIBRANCE_GOLDEN_DIR"],
              !raw.isEmpty else {
            throw XCTSkip("NEGAFLOW_VIBRANCE_GOLDEN_DIR 를 지정하면 격자를 생성합니다.")
        }
        let directory = URL(fileURLWithPath: raw, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let input = Self.gridPixels()
        let image = CIImage(
            bitmapData: input.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: Self.width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: Self.width, height: Self.height),
            format: .RGBAf,
            colorSpace: linear
        )
        // 현상 파이프라인이 vibrance 를 거는 것과 같은 작업공간·같은 컨텍스트 풀을 쓴다.
        let context = SamplingContextPool.context(workingColorSpace: linear)

        for amount in Self.amounts {
            let output: CIImage = amount == 0
                ? image
                : image.applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
                    .cropped(to: image.extent)
            var bitmap = [Float](repeating: 0, count: Self.width * Self.height * 4)
            bitmap.withUnsafeMutableBytes { buffer in
                context.render(
                    output,
                    toBitmap: buffer.baseAddress!,
                    rowBytes: Self.width * 4 * MemoryLayout<Float>.size,
                    bounds: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                    format: .RGBAf,
                    colorSpace: linear
                )
            }
            let name = String(format: "civibrance-a%.3f-%dx%d.f32", amount, Self.width, Self.height)
            let url = directory.appendingPathComponent(name)
            try bitmap.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url, options: .atomic)

            // amount 0 은 항등이어야 한다 — 렌더 경로가 값을 건드리지 않는다는 확인이다.
            if amount == 0 {
                for index in 0..<(Self.gridCount * 4) {
                    XCTAssertEqual(
                        bitmap[index], input[index], accuracy: 1e-6,
                        "amount 0 에서 렌더 경로가 값을 바꿨다 (index \(index))"
                    )
                }
            }
        }

        // 입력 격자도 함께 남긴다 — 받는 쪽이 인덱스 규약을 재구성하지 않아도 된다.
        try input.withUnsafeBufferPointer { Data(buffer: $0) }.write(
            to: directory.appendingPathComponent(
                "civibrance-input-\(Self.width)x\(Self.height).f32"
            ),
            options: .atomic
        )
    }

    /// i → (R, G, B) = (i/289, (i/17)%17, i%17) / 16, 알파 1. 나머지 화소는 0.
    static func gridPixels() -> [Float] {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<gridCount {
            pixels[i * 4 + 0] = Float(i / 289) / 16.0
            pixels[i * 4 + 1] = Float((i / 17) % 17) / 16.0
            pixels[i * 4 + 2] = Float(i % 17) / 16.0
            pixels[i * 4 + 3] = 1.0
        }
        return pixels
    }
}
