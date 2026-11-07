import Chromabase
import CoreGraphics
import simd
import XCTest
@testable import negaflowApp

/// 앱 경로(현상본 CGImage → 방향 → 축소 → 선 찾기 → 풀이)와 회전·뒤집기 때의 보정 유지.
@MainActor
final class PerspectiveControlsTests: XCTestCase {
    private let size = CGSize(width: 1200, height: 800)
    private let distortion = PerspectiveCorrection(solvedVertical: 8, solvedHorizontal: -5, solvedRotate: 2)

    func testAppPathRecoversTheDistortionAndFollowsAQuarterTurn() throws {
        let image = try warpedGridImage()
        let solved = try XCTUnwrap(AppModel.detectAndSolve(image, orientation: .identity, mode: .full))
        XCTAssertEqual(solved.vertical, -8, accuracy: 0.8)
        XCTAssertEqual(solved.horizontal, 5, accuracy: 0.8)
        XCTAssertEqual(solved.rotate, -2, accuracy: 0.4)

        // 같은 사진을 시계방향으로 돌리면 답은 축이 옮겨진 같은 보정이어야 한다.
        let turned = try XCTUnwrap(AppModel.detectAndSolve(
            image, orientation: ImageTransform(rotation: .deg90), mode: .full))
        let expected = PerspectiveCorrection(
            solvedVertical: solved.vertical, solvedHorizontal: solved.horizontal, solvedRotate: solved.rotate
        ).rotatedQuarterTurn(clockwise: true)
        XCTAssertEqual(turned.vertical, expected.solvedVertical, accuracy: 0.8)
        XCTAssertEqual(turned.horizontal, expected.solvedHorizontal, accuracy: 0.8)
        XCTAssertEqual(turned.rotate, expected.solvedRotate, accuracy: 0.4)
    }

    func testRotatingAndFlippingAfterCorrectionKeepsTheSameCorrectionOnScreen() {
        let model = AppModel()
        let frame = makeFrame()
        frame.updateTransform {
            $0.perspective = PerspectiveCorrection(mode: .vertical, solvedVertical: 6, vertical: 20, rotate: 3,
                                                   offsetX: 10)
        }
        model.rotate(frame, clockwise: true)
        XCTAssertEqual(frame.imageTransform.perspective.solvedHorizontal, 6, accuracy: 1e-12)
        XCTAssertEqual(frame.imageTransform.perspective.horizontal, 20, accuracy: 1e-12)
        model.rotate(frame, clockwise: false)
        XCTAssertEqual(frame.imageTransform.perspective.solvedVertical, 6, accuracy: 1e-12)
        XCTAssertEqual(frame.imageTransform.perspective.vertical, 20, accuracy: 1e-12)
        XCTAssertEqual(frame.imageTransform.perspective.offsetX, 10, accuracy: 1e-12)
        model.flipHorizontally(frame)
        XCTAssertEqual(frame.imageTransform.perspective.rotate, -3, accuracy: 1e-12)
        XCTAssertEqual(frame.imageTransform.perspective.offsetX, -10, accuracy: 1e-12)
        model.flipHorizontally(frame)
        XCTAssertEqual(frame.imageTransform.perspective.rotate, 3, accuracy: 1e-12)
    }

    func testGuidedModeSolvesFromGuidesAndClearingThemUndoesIt() {
        let model = AppModel()
        let frame = makeFrame(width: 1000, height: 800)
        model.setPerspectiveGuides(frame, guides: [
            PerspectiveGuide(start: CGPoint(x: 0.3, y: 0.9), end: CGPoint(x: 0.36, y: 0.1)),
            PerspectiveGuide(start: CGPoint(x: 0.72, y: 0.9), end: CGPoint(x: 0.66, y: 0.1)),
        ])
        let p = frame.imageTransform.perspective
        XCTAssertEqual(p.mode, .guided)
        XCTAssertNotEqual(p.solvedVertical, 0)
        XCTAssertEqual(p.solvedHorizontal, 0)
        model.setPerspectiveGuides(frame, guides: [])
        XCTAssertEqual(frame.imageTransform.perspective.solvedVertical, 0)
        XCTAssertFalse(frame.imageTransform.perspective.changesGeometry)
    }

    private func makeFrame(width: Int? = nil, height: Int? = nil) -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-perspective-\(UUID().uuidString).tiff"),
            filmType: .colorNegative,
            sourcePixelWidth: width,
            sourcePixelHeight: height
        )
    }

    /// 격자를 `distortion` 으로 일그러뜨린 sRGB 회색 CGImage.
    private func warpedGridImage() throws -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        let inverse = cameraTiltInverse(distortion, size: size)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var v: UInt8 = 128
                if let s = PerspectiveGeometry.apply(inverse, CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)),
                   s.x >= 0, s.y >= 0, Double(s.x) < Double(w), Double(s.y) < Double(h) {
                    let onLine = (Double(s.x) + 40).truncatingRemainder(dividingBy: 110) < 8
                        || (Double(s.y) + 40).truncatingRemainder(dividingBy: 110) < 8
                    v = onLine ? 40 : 220
                }
                let i = (y * w + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }

    /// 실제 카메라를 기울인 것과 같은 왜곡의 역 호모그래피(픽셀 → 픽셀). 보정 식과 달리 중심을 되돌리지
    /// 않는다 — 실제 사진의 원근은 이미지 중심을 주점으로 한 순수 회전이고, 풀이도 그 모형을 쓴다.
    private func cameraTiltInverse(_ c: PerspectiveCorrection, size: CGSize) -> simd_double3x3 {
        let w = Double(size.width), h = Double(size.height), s = max(w, h) / 2
        let f = PerspectiveGeometry.focalLength
        let toNormal = simd_double3x3(rows: [SIMD3(1 / s, 0, -w / 2 / s), SIMD3(0, 1 / s, -h / 2 / s), SIMD3(0, 0, 1)])
        let toPixel = simd_double3x3(rows: [SIMD3(s, 0, w / 2), SIMD3(0, s, h / 2), SIMD3(0, 0, 1)])
        let k = simd_double3x3(rows: [SIMD3(f, 0, 0), SIMD3(0, f, 0), SIMD3(0, 0, 1)])
        // 로드리게스 공식(R(−ω) = R(ω)⁻¹).
        let omega = -PerspectiveGeometry.rotationVector(for: c)
        let angle = simd_length(omega)
        var r = matrix_identity_double3x3
        if angle > 1e-12 {
            let a = omega / angle
            let kx = simd_double3x3(rows: [SIMD3(0, -a.z, a.y), SIMD3(a.z, 0, -a.x), SIMD3(-a.y, a.x, 0)])
            r = matrix_identity_double3x3 + sin(angle) * kx + (1 - cos(angle)) * (kx * kx)
        }
        return toPixel * k * r * k.inverse * toNormal
    }
}
