import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

/// Validates ImageTransform.displayUnitToBase against the REAL ImageTransformStage: place a
/// marker pixel at a known base position, transform the image, locate the marker in the
/// display, and confirm displayUnitToBase maps it back to the base position. This keeps brush
/// strokes (stored in base coords) aligned through rotate/flip/crop.
final class ImageTransformMappingTests: XCTestCase {
    private let W = 48, H = 72
    private let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!

    /// White marker at base (bx,by) y-down normalized; black elsewhere.
    private func markerImage(bx: Double, by: Double) -> CIImage {
        var px = [UInt8](repeating: 0, count: W*H*4)
        let mx = Int(bx * Double(W)), my = Int(by * Double(H))   // y-down pixel
        for dy in -1...1 { for dx in -1...1 {
            let x = mx+dx, y = my+dy
            guard x >= 0, x < W, y >= 0, y < H else { continue }
            let i = (y*W + x)*4
            px[i]=255; px[i+1]=255; px[i+2]=255; px[i+3]=255
        }}
        let data = Data(px)
        return CIImage(bitmapData: data, bytesPerRow: W*4, size: CGSize(width: W, height: H),
                       format: .RGBA8, colorSpace: linear)
    }

    /// Find marker centroid in an image → y-down normalized.
    private func findMarker(_ image: CIImage) -> CGPoint? {
        let ext = image.extent.integral
        let w = Int(ext.width), h = Int(ext.height)
        var px = [UInt8](repeating: 0, count: w*h*4)
        let ctx = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        ctx.render(image, toBitmap: &px, rowBytes: w*4,
                   bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: linear)
        var sx = 0.0, sy = 0.0, n = 0.0
        for y in 0..<h { for x in 0..<w {
            if px[(y*w+x)*4] > 128 { sx += Double(x); sy += Double(y); n += 1 }
        }}
        guard n > 0 else { return nil }
        // CIContext.render with these bounds yields y-DOWN rows → already y-down.
        return CGPoint(x: (sx/n + 0.5)/Double(w), y: (sy/n + 0.5)/Double(h))
    }

    private func check(_ t: ImageTransform, bx: Double, by: Double, file: StaticString = #filePath, line: UInt = #line) {
        let base = markerImage(bx: bx, by: by)
        let display = ImageTransformStage.apply(to: base, transform: t)
        guard let disp = findMarker(display) else { return XCTFail("marker lost", file: file, line: line) }
        let mapped = t.displayUnitToBase(disp)
        XCTAssertEqual(Double(mapped.x), bx, accuracy: 0.04, "x for \(t.displayName)", file: file, line: line)
        XCTAssertEqual(Double(mapped.y), by, accuracy: 0.04, "y for \(t.displayName)", file: file, line: line)
    }

    func testRotationsAndFlipsRoundTrip() {
        let bx = 0.30, by = 0.20
        for rot in ImageRotation.allCases {
            check(ImageTransform(rotation: rot), bx: bx, by: by)
            check(ImageTransform(rotation: rot, flipHorizontal: true), bx: bx, by: by)
            check(ImageTransform(rotation: rot, flipVertical: true), bx: bx, by: by)
            check(ImageTransform(rotation: rot, flipHorizontal: true, flipVertical: true), bx: bx, by: by)
        }
    }

    func testCropRoundTrip() {
        // marker at (0.5,0.4) base; crop a region (y-up) that contains it.
        check(ImageTransform(cropRect: SIMD4(0.2, 0.25, 0.6, 0.6)), bx: 0.5, by: 0.4)
        check(ImageTransform(rotation: .deg90, cropRect: SIMD4(0.2, 0.2, 0.6, 0.6)), bx: 0.5, by: 0.4)
        check(ImageTransform(rotation: .deg270, flipHorizontal: true, cropRect: SIMD4(0.15, 0.15, 0.7, 0.7)), bx: 0.5, by: 0.45)
    }

    // straightenAngle(미세 회전) 왕복: 내접 크롭 때문에 base 픽셀 크기를 넘겨야 정확히 역매핑된다.
    private func checkStraighten(_ t: ImageTransform, bx: Double, by: Double,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let base = markerImage(bx: bx, by: by)
        let display = ImageTransformStage.apply(to: base, transform: t)
        guard let disp = findMarker(display) else { return XCTFail("marker lost \(t.displayName) θ=\(t.straightenAngle)", file: file, line: line) }
        let mapped = t.displayUnitToBase(disp, baseSize: CGSize(width: W, height: H))
        XCTAssertEqual(Double(mapped.x), bx, accuracy: 0.05, "x straighten θ=\(t.straightenAngle) \(t.displayName)", file: file, line: line)
        XCTAssertEqual(Double(mapped.y), by, accuracy: 0.05, "y straighten θ=\(t.straightenAngle) \(t.displayName)", file: file, line: line)
    }

    func testStraightenRoundTrip() {
        // 중앙 근처 marker(내접 크롭 밖으로 나가지 않도록) + 작은 각도.
        for angle in [-10.0, -5.0, 6.0, 12.0] {
            checkStraighten(ImageTransform(straightenAngle: angle), bx: 0.46, by: 0.42)
            checkStraighten(ImageTransform(rotation: .deg90, straightenAngle: angle), bx: 0.46, by: 0.42)
            checkStraighten(ImageTransform(rotation: .deg180, straightenAngle: angle), bx: 0.5, by: 0.5)
            checkStraighten(ImageTransform(flipHorizontal: true, straightenAngle: angle), bx: 0.46, by: 0.42)
        }
    }

    func testStraightenWithCropRoundTrip() {
        // straighten 후 큰 crop. marker는 내접 크롭·crop 모두 안에 있어야 한다.
        checkStraighten(ImageTransform(cropRect: SIMD4(0.2, 0.2, 0.6, 0.6), straightenAngle: 8), bx: 0.5, by: 0.5)
        checkStraighten(ImageTransform(rotation: .deg90, cropRect: SIMD4(0.2, 0.2, 0.6, 0.6), straightenAngle: -7), bx: 0.5, by: 0.5)
    }

    // baseSize 미지정이면 straighten 역변환을 건너뛴다(하위호환). straightenAngle==0 케이스는
    // baseSize 유무와 무관하게 기존 rotation/flip/crop 경로와 동일해야 한다.
    // baseUnitToDisplay ∘ displayUnitToBase = identity (양방향). 미리보기/클릭 좌표의 정확성 보장.
    func testBaseDisplayRoundTripBothWays() {
        let size = CGSize(width: W, height: H)
        let transforms: [ImageTransform] = [
            ImageTransform(rotation: .deg90, flipHorizontal: true),
            ImageTransform(rotation: .deg270, flipVertical: true, cropRect: SIMD4(0.1, 0.1, 0.8, 0.8)),
            ImageTransform(straightenAngle: 7),
            ImageTransform(rotation: .deg90, cropRect: SIMD4(0.15, 0.2, 0.6, 0.6), straightenAngle: -6),
            ImageTransform(rotation: .deg180, flipHorizontal: true, straightenAngle: 9),
        ]
        for t in transforms {
            for p in [CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.62, y: 0.55)] {
                let d = t.baseUnitToDisplay(p, baseSize: size)
                let back = t.displayUnitToBase(d, baseSize: size)
                XCTAssertEqual(Double(back.x), Double(p.x), accuracy: 1e-6, "x roundtrip \(t.displayName) θ=\(t.straightenAngle)")
                XCTAssertEqual(Double(back.y), Double(p.y), accuracy: 1e-6, "y roundtrip \(t.displayName) θ=\(t.straightenAngle)")
            }
        }
    }

    func testNoStraightenUnaffectedByBaseSize() {
        let t = ImageTransform(rotation: .deg90, flipHorizontal: true, cropRect: SIMD4(0.2, 0.2, 0.6, 0.6))
        let p = CGPoint(x: 0.37, y: 0.58)
        let a = t.displayUnitToBase(p)
        let b = t.displayUnitToBase(p, baseSize: CGSize(width: W, height: H))
        XCTAssertEqual(Double(a.x), Double(b.x), accuracy: 1e-9)
        XCTAssertEqual(Double(a.y), Double(b.y), accuracy: 1e-9)
    }
}
