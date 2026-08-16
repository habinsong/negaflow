import CoreGraphics
import CoreImage
import Foundation
import XCTest
@testable import Chromabase

/// `CIVibrance` 의 **사상**을 알려진 격자로 뽑아 준다(REQUEST-3 요청 A, REQUEST-4 요청 A·B).
///
/// Apple 내장 필터라 커널 소스가 없다. 수식을 추측해 옮기는 대신 입출력 격자를 넘겨
/// Windows 포팅본이 값으로 맞추게 한다.
///
/// ```
/// NEGAFLOW_VIBRANCE_GOLDEN_DIR=/path/to/docs/verification/macos-golden/vibrance \
/// swift test --filter VibranceMappingGoldenTests
/// ```
final class VibranceMappingGoldenTests: XCTestCase {

    /// 한 판의 규약. `edge³` 개 점을 `width × height` 이미지 앞쪽에 채우고 나머지는 0 으로 둔다.
    private struct Grid {
        let edge: Int
        let width: Int
        let height: Int
        let prefix: String

        var count: Int { edge * edge * edge }

        /// i → (R, G, B) = (i / edge², (i / edge) % edge, i % edge) / (edge − 1), alpha 1.
        func pixels() -> [Float] {
            var pixels = [Float](repeating: 0, count: width * height * 4)
            let plane = edge * edge
            let divisor = Float(edge - 1)
            for i in 0..<count {
                pixels[i * 4 + 0] = Float(i / plane) / divisor
                pixels[i * 4 + 1] = Float((i / edge) % edge) / divisor
                pixels[i * 4 + 2] = Float(i % edge) / divisor
                pixels[i * 4 + 3] = 1.0
            }
            return pixels
        }
    }

    private static let grid17 = Grid(edge: 17, width: 128, height: 39, prefix: "civibrance")
    private static let grid33 = Grid(edge: 33, width: 256, height: 141, prefix: "civibrance33")
    private static let grid65 = Grid(edge: 65, width: 640, height: 430, prefix: "civibrance65")

    /// REQUEST-3. 되돌림 방지를 위해 그대로 둔다.
    func testEmitsVibranceMappingGrid() throws {
        try emit(Self.grid17, amounts: [0.0, 0.1, 0.252, 0.259, 0.5], writesInput: true)
    }

    /// REQUEST-4 요청 A — 33³, 파이프라인이 실제로 내는 amount 범위를 고르게 덮는다.
    /// `amount = min(0.5, max(0, (0.24 − meanSat) × 3))` 이라 0.5 를 넘지 않고 0.01 이하는
    /// 단계 자체를 건너뛴다.
    func testEmitsDenseVibranceMappingGrid() throws {
        try emit(
            Self.grid33,
            amounts: stride(from: 0.05, through: 0.50, by: 0.05).map { $0 },
            writesInput: true
        )
    }

    /// REQUEST-4 요청 B — 33³ 의 충분함을 33³ 자신으로 판정할 수 없으므로 독립 자료 한 판.
    func testEmitsVerificationGrid() throws {
        try emit(Self.grid65, amounts: [0.25], writesInput: true)
    }

    // MARK: 방출

    private func emit(_ grid: Grid, amounts: [Double], writesInput: Bool) throws {
        guard let raw = ProcessInfo.processInfo.environment["NEGAFLOW_VIBRANCE_GOLDEN_DIR"],
              !raw.isEmpty else {
            throw XCTSkip("NEGAFLOW_VIBRANCE_GOLDEN_DIR 를 지정하면 격자를 생성합니다.")
        }
        let directory = URL(fileURLWithPath: raw, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.linearSRGB))
        let input = grid.pixels()
        let rowBytes = grid.width * 4 * MemoryLayout<Float>.size
        let image = CIImage(
            bitmapData: input.withUnsafeBufferPointer { Data(buffer: $0) },
            bytesPerRow: rowBytes,
            size: CGSize(width: grid.width, height: grid.height),
            format: .RGBAf,
            colorSpace: linear
        )
        // 현상 파이프라인이 vibrance 를 거는 것과 같은 작업공간·같은 컨텍스트 풀을 쓴다.
        let context = SamplingContextPool.context(workingColorSpace: linear)

        for amount in amounts {
            let output: CIImage = amount == 0
                ? image
                : image.applyingFilter("CIVibrance", parameters: ["inputAmount": amount])
                    .cropped(to: image.extent)
            var bitmap = [Float](repeating: 0, count: grid.width * grid.height * 4)
            bitmap.withUnsafeMutableBytes { buffer in
                context.render(
                    output,
                    toBitmap: buffer.baseAddress!,
                    rowBytes: rowBytes,
                    bounds: CGRect(x: 0, y: 0, width: grid.width, height: grid.height),
                    format: .RGBAf,
                    colorSpace: linear
                )
            }
            let name = String(
                format: "%@-a%.3f-%dx%d.f32", grid.prefix, amount, grid.width, grid.height
            )
            try bitmap.withUnsafeBufferPointer { Data(buffer: $0) }
                .write(to: directory.appendingPathComponent(name), options: .atomic)

            // amount 0 은 항등이어야 한다 — 렌더 경로가 값을 건드리지 않는다는 확인이다.
            if amount == 0 {
                for index in 0..<(grid.count * 4) {
                    XCTAssertEqual(
                        bitmap[index], input[index], accuracy: 1e-6,
                        "amount 0 에서 렌더 경로가 값을 바꿨다 (index \(index))"
                    )
                }
            }
        }

        guard writesInput else { return }
        // 입력 격자도 남긴다 — 받는 쪽이 인덱스 규약을 재구성하지 않아도 된다.
        try input.withUnsafeBufferPointer { Data(buffer: $0) }.write(
            to: directory.appendingPathComponent(
                "\(grid.prefix)-input-\(grid.width)x\(grid.height).f32"
            ),
            options: .atomic
        )
    }
}
