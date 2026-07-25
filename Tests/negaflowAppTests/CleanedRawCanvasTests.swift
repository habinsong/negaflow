import AppKit
import CoreGraphics
import CoreImage
import XCTest
@testable import negaflowApp

// CleanedRawCanvas(증분 CPU 블릿 + CoW 스냅샷)가 기존 CI 풀 flatten 과 같은 픽셀을 내는지
// 보증한다 — 편집당 풀프레임 GPU flatten 제거의 안전 근거. 합성 픽스처 + 수치 비교만 사용.
@MainActor
final class CleanedRawCanvasTests: XCTestCase {
    private let width = 160
    private let height = 120

    func testCompositeMatchesCIFlattenAtFullStrength() throws {
        let base = try makeBase()
        let p1 = try makePatch(rect: CGRect(x: 20, y: 80, width: 12, height: 10), gray: 0.85)
        let p2 = try makePatch(rect: CGRect(x: 90, y: 14, width: 8, height: 8), gray: 0.15)

        let canvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        let composed = try XCTUnwrap(canvas.composite(base: base, patches: [(p1, 1.0), (p2, 1.0)]))
        let expected = try ciFlatten(base: base, patches: [(p1, 1.0), (p2, 1.0)])

        assertPixelsEqual(composed, expected, tolerance: 0, "강도 1.0 캔버스 ≠ CI flatten")
    }

    func testCompositeMatchesCIFlattenAtPartialStrength() throws {
        let base = try makeBase()
        let p1 = try makePatch(rect: CGRect(x: 40, y: 40, width: 16, height: 12), gray: 0.9)

        let canvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        let composed = try XCTUnwrap(canvas.composite(base: base, patches: [(p1, 0.5)]))
        let expected = try ciFlatten(base: base, patches: [(p1, 0.5)])

        // 강도 블렌드는 CG 16bit 반올림 vs CI float 경로 차이로 최대 몇 스텝까지 허용.
        assertPixelsEqual(composed, expected, tolerance: 4.0 / 65535.0, "강도 0.5 캔버스 ≠ CI flatten")
    }

    func testIncrementalCompositeOnPreviousSnapshotMatchesScratchBuild() throws {
        let base = try makeBase()
        let p1 = try makePatch(rect: CGRect(x: 20, y: 80, width: 12, height: 10), gray: 0.85)
        let p2 = try makePatch(rect: CGRect(x: 24, y: 84, width: 10, height: 10), gray: 0.35)

        // 증분: base+p1 스냅샷을 base 로 p2 — 실제 append 경로.
        let canvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        let snap1 = try XCTUnwrap(canvas.composite(base: base, patches: [(p1, 1.0)]))
        let incremental = try XCTUnwrap(canvas.composite(base: snap1, patches: [(p2, 1.0)]))

        let scratchCanvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        let scratch = try XCTUnwrap(
            scratchCanvas.composite(base: base, patches: [(p1, 1.0), (p2, 1.0)])
        )
        assertPixelsEqual(incremental, scratch, tolerance: 0, "증분 합성 ≠ 처음부터 합성")
    }

    func testSameBaseRecompositeRestoresPreviousRects() throws {
        let base = try makeBase()
        let p1 = try makePatch(rect: CGRect(x: 50, y: 30, width: 14, height: 14), gray: 0.95)

        // 라이브 강도 드래그: 같은 base 로 강도만 바꿔 재합성 — rect 복원 경로.
        let canvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        _ = try XCTUnwrap(canvas.composite(base: base, patches: [(p1, 1.0)]))
        let redone = try XCTUnwrap(canvas.composite(base: base, patches: [(p1, 0.4)]))

        let freshCanvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        let fresh = try XCTUnwrap(freshCanvas.composite(base: base, patches: [(p1, 0.4)]))
        assertPixelsEqual(redone, fresh, tolerance: 0, "rect 복원 재합성 ≠ 신규 합성")
    }

    func testSwitchingToDifferentBaseWithSameSizeDoesNotReuseStaleContent() throws {
        // 서로 다른 base 인스턴스(같은 크기)로 연속 합성 — 두 번째 합성은 반드시 새 base 를
        // 풀 블릿해야 한다(정체성 오판 시 첫 base 위 픽셀이 남는다).
        let baseA = try makeBase()
        let patch = try makePatch(rect: CGRect(x: 10, y: 10, width: 8, height: 8), gray: 0.9)
        let uniform = CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let baseB = try XCTUnwrap(cleanedRawContext.createCGImage(
            uniform, from: uniform.extent, format: .RGBA16, colorSpace: linearColorSpace
        ))

        let canvas = try XCTUnwrap(CleanedRawCanvas(width: width, height: height))
        _ = try XCTUnwrap(canvas.composite(base: baseA, patches: [(patch, 1.0)]))
        let switched = try XCTUnwrap(canvas.composite(base: baseB, patches: []))

        assertPixelsEqual(switched, baseB, tolerance: 0, "다른 base 교체 시 stale 픽셀이 남음")
    }

    // MARK: fixtures

    /// 실제 파이프라인과 동일하게 cleanedRawContext 로 만든 RGBA16 linear 베이스(그라데이션).
    private func makeBase() throws -> CGImage {
        let gradient = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
            "inputColor0": CIColor(red: 0.2, green: 0.25, blue: 0.3),
            "inputColor1": CIColor(red: 0.7, green: 0.65, blue: 0.6),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(cleanedRawContext.createCGImage(
            gradient, from: gradient.extent, format: .RGBA16, colorSpace: linearColorSpace
        ))
    }

    /// rect 크기의 단색 RGBA16 패치(실제 패치와 같은 생성 경로).
    private func makePatch(rect: CGRect, gray: CGFloat) throws -> DefectPatch {
        let color = CIImage(color: CIColor(red: gray, green: gray, blue: gray))
            .cropped(to: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        let image = try XCTUnwrap(cleanedRawContext.createCGImage(
            color, from: color.extent, format: .RGBA16, colorSpace: linearColorSpace
        ))
        return DefectPatch(rect: rect, image: image)
    }

    /// 기존 빌드 경로와 동일한 CI 체인 + 풀 flatten.
    private func ciFlatten(base: CGImage,
                           patches: [(DefectPatch, Double)]) throws -> CGImage {
        var working = CIImage(cgImage: base, options: [.colorSpace: linearColorSpace])
        for (patch, strength) in patches {
            working = patch.composited(over: working, strength: strength,
                                       colorSpace: linearColorSpace)
        }
        return try XCTUnwrap(cleanedRawContext.createCGImage(
            working, from: working.extent, format: .RGBA16, colorSpace: linearColorSpace
        ))
    }

    private func assertPixelsEqual(_ lhs: CGImage, _ rhs: CGImage,
                                   tolerance: Float, _ message: String) {
        let a = render(lhs)
        let b = render(rhs)
        XCTAssertEqual(a.count, b.count)
        var maxDiff: Float = 0
        for i in 0..<min(a.count, b.count) {
            maxDiff = max(maxDiff, abs(a[i] - b[i]))
        }
        XCTAssertLessThanOrEqual(maxDiff, tolerance + 1e-7, "\(message) (maxDiff=\(maxDiff))")
    }

    private func render(_ image: CGImage) -> [Float] {
        let ci = CIImage(cgImage: image, options: [.colorSpace: linearColorSpace])
        var out = [Float](repeating: 0, count: image.width * image.height * 4)
        cleanedRawContext.render(
            ci, toBitmap: &out, rowBytes: image.width * 4 * MemoryLayout<Float>.size,
            bounds: ci.extent, format: .RGBAf, colorSpace: linearColorSpace
        )
        return out
    }
}
