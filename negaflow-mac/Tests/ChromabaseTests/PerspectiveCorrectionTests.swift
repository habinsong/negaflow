import CoreGraphics
import CoreImage
import XCTest
import simd
@testable import Chromabase

/// 변환(원근) 보정의 수학과 자동 풀이를 합성 입력으로 잰다.
final class PerspectiveCorrectionTests: XCTestCase {
    private let sizes = [CGSize(width: 1200, height: 800), CGSize(width: 640, height: 960)]

    private func sample(_ seed: Int) -> PerspectiveCorrection {
        var generator = SplitMix(seed: UInt64(seed))
        func r(_ range: ClosedRange<Double>) -> Double { generator.next(in: range) }
        return PerspectiveCorrection(
            mode: .full,
            solvedVertical: r(-12...12), solvedHorizontal: r(-12...12), solvedRotate: r(-6...6),
            vertical: r(-40...40), horizontal: r(-40...40), rotate: r(-5...5),
            aspect: r(-50...50), scale: r(70...130), offsetX: r(-30...30), offsetY: r(-30...30)
        )
    }

    func testIdentityDoesNotTouchTheImage() {
        XCTAssertNil(PerspectiveGeometry.mapping(for: .identity, size: sizes[0]))
        var guidesOnly = PerspectiveCorrection.identity
        guidesOnly.mode = .guided
        guidesOnly.guides = [PerspectiveGuide(start: .zero, end: CGPoint(x: 1, y: 1))]
        XCTAssertFalse(guidesOnly.changesGeometry)
    }

    func testForwardAndInverseRoundTrip() throws {
        for seed in 0..<40 {
            let c = sample(seed)
            for size in sizes {
                let mapping = try XCTUnwrap(PerspectiveGeometry.mapping(for: c, size: size), "\(seed)")
                for u in [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.93, y: 0.71)] {
                    let f = try XCTUnwrap(mapping.forwardUnit(u))
                    let back = try XCTUnwrap(mapping.inverseUnit(f))
                    XCTAssertEqual(back.x, u.x, accuracy: 1e-9)
                    XCTAssertEqual(back.y, u.y, accuracy: 1e-9)
                }
            }
        }
    }

    /// 카메라를 기울여도 그림 중심은 프레임 가운데에 남는다. 예전 식은 세로 15° 에서 중심을 높이의
    /// 24% 아래로 밀어, 바로 세운 건물 꼭대기를 프레임 밖으로 잘랐다.
    func testCorrectionKeepsThePhotoCenteredInTheFrame() throws {
        let corrections = [
            PerspectiveCorrection(mode: .full, solvedVertical: -15, solvedHorizontal: 5),
            PerspectiveCorrection(mode: .vertical, solvedVertical: 20, rotate: 3),
            PerspectiveCorrection(vertical: -60, horizontal: 40),
        ]
        for c in corrections {
            let size = CGSize(width: 2400, height: 1600)
            let mapping = try XCTUnwrap(PerspectiveGeometry.mapping(for: c, size: size))
            let center = try XCTUnwrap(PerspectiveGeometry.apply(mapping.forward, CGPoint(x: 1200, y: 800)))
            XCTAssertEqual(center.x, 1200, accuracy: 1e-6)
            XCTAssertEqual(center.y, 800, accuracy: 1e-6)
        }
    }

    /// 90° 회전·뒤집기 뒤 옮긴 값은 같은 보정을 돌린 것과 정확히 같아야 한다: P'(Q·x) = Q·P(x).
    func testOrientationChangesCarryTheExactSameCorrection() throws {
        typealias Turn = (CGPoint) -> CGPoint
        let cases: [(String, (PerspectiveCorrection) -> PerspectiveCorrection, Turn, Bool)] = [
            ("cw", { $0.rotatedQuarterTurn(clockwise: true) }, { CGPoint(x: 1 - $0.y, y: $0.x) }, true),
            ("ccw", { $0.rotatedQuarterTurn(clockwise: false) }, { CGPoint(x: $0.y, y: 1 - $0.x) }, true),
            ("flipH", { $0.mirroredHorizontally() }, { CGPoint(x: 1 - $0.x, y: $0.y) }, false),
            ("flipV", { $0.mirroredVertically() }, { CGPoint(x: $0.x, y: 1 - $0.y) }, false),
        ]
        for seed in 0..<25 {
            let c = sample(seed)
            for size in sizes {
                let old = try XCTUnwrap(PerspectiveGeometry.mapping(for: c, size: size))
                for (name, remap, turn, swaps) in cases {
                    let newSize = swaps ? CGSize(width: size.height, height: size.width) : size
                    let new = try XCTUnwrap(PerspectiveGeometry.mapping(for: remap(c), size: newSize))
                    for u in [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.77, y: 0.61)] {
                        let expected = turn(try XCTUnwrap(old.forwardUnit(u)))
                        let actual = try XCTUnwrap(new.forwardUnit(turn(u)))
                        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, "\(name) \(seed)")
                        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, "\(name) \(seed)")
                    }
                }
            }
        }
    }

    func testImpossibleValuesLeaveTheImageAloneInsteadOfProducingNaN() {
        let extreme = PerspectiveCorrection(mode: .full, solvedVertical: 40, solvedHorizontal: 40,
                                            vertical: 100, horizontal: 100)
        XCTAssertNil(PerspectiveGeometry.mapping(for: extreme, size: sizes[0]))
        let image = CIImage(color: .gray).cropped(to: CGRect(origin: .zero, size: sizes[0]))
        let out = ImageTransformStage.apply(to: image, transform: ImageTransform(perspective: extreme), fill: .transparent)
        XCTAssertEqual(out.extent, image.extent)
    }

    /// 알려진 원근으로 일그러뜨린 격자를 각 모드가 펴는가.
    func testFullModeStraightensASyntheticKeystonedGrid() throws {
        let size = CGSize(width: 900, height: 600)
        let distortion = PerspectiveCorrection(solvedVertical: 9, solvedHorizontal: -6, solvedRotate: 2.5)
        let (luma, w, h) = try warpedGrid(size: size, distortion: distortion)
        let segments = PerspectiveLineDetector.detect(luma: luma, width: w, height: h)
        XCTAssertGreaterThan(segments.count, 10)
        let solution = try XCTUnwrap(PerspectiveSolver.solve(mode: .full, segments: segments, size: size))
        // R(−ω) 가 R(ω) 의 역이라 정답은 정확히 부호를 바꾼 값이다.
        XCTAssertEqual(solution.vertical, -9, accuracy: 0.6)
        XCTAssertEqual(solution.horizontal, 6, accuracy: 0.6)
        XCTAssertEqual(solution.rotate, -2.5, accuracy: 0.3)

        let level = try XCTUnwrap(PerspectiveSolver.solve(mode: .level, segments: segments, size: size))
        XCTAssertEqual(level.vertical, 0)
        XCTAssertEqual(level.horizontal, 0)
        let vertical = try XCTUnwrap(PerspectiveSolver.solve(mode: .vertical, segments: segments, size: size))
        XCTAssertEqual(vertical.horizontal, 0)
        XCTAssertEqual(vertical.vertical, -9, accuracy: 1.5)
        // 균형 모드는 과하게 늘이지 않는다 — 원근은 같은 쪽으로, 크기는 전체 이하.
        let auto = try XCTUnwrap(PerspectiveSolver.solve(mode: .auto, segments: segments, size: size))
        XCTAssertLessThan(auto.vertical, 0)
        XCTAssertLessThanOrEqual(abs(auto.vertical), abs(solution.vertical) + 0.1)
    }

    func testPlainTextureWithoutLinesFindsNothing() {
        var generator = SplitMix(seed: 7)
        let w = 300, h = 200
        let noise = (0..<(w * h)).map { _ in Float(0.45 + generator.next(in: -0.02...0.02)) }
        XCTAssertNil(PerspectiveSolver.solve(
            mode: .full,
            segments: PerspectiveLineDetector.detect(luma: noise, width: w, height: h),
            size: CGSize(width: w, height: h)
        ))
    }

    func testGuidesDriveTheGuidedMode() throws {
        let size = CGSize(width: 1000, height: 800)
        // 위로 갈수록 모이는 두 수직 안내선.
        let guides = [
            PerspectiveLineSegment(start: CGPoint(x: 0.30, y: 0.9), end: CGPoint(x: 0.36, y: 0.1), length: 1),
            PerspectiveLineSegment(start: CGPoint(x: 0.72, y: 0.9), end: CGPoint(x: 0.66, y: 0.1), length: 1),
        ]
        let solution = try XCTUnwrap(PerspectiveSolver.solve(mode: .guided, segments: guides, size: size))
        let mapping = try XCTUnwrap(PerspectiveGeometry.mapping(
            for: PerspectiveCorrection(solvedVertical: solution.vertical, solvedHorizontal: solution.horizontal,
                                       solvedRotate: solution.rotate),
            size: size))
        for guide in guides {
            let a = try XCTUnwrap(mapping.forwardUnit(guide.start))
            let b = try XCTUnwrap(mapping.forwardUnit(guide.end))
            let lean = atan2(Double((b.x - a.x) * size.width), Double((b.y - a.y) * size.height)) * 180 / .pi
            XCTAssertEqual(abs(lean).truncatingRemainder(dividingBy: 180), 180, accuracy: 0.05)
        }
    }

    /// 렌더 결과: 빈 곳은 부르는 쪽이 고른 채움(흰색·투명)이고, 어느 쪽이든 크기는 같다. 자르기 제한을
    /// 켜면 빈 곳이 없다.
    func testRenderFillsEmptyAreaAsRequestedAndConstrainCropRemovesIt() throws {
        let size = CGSize(width: 240, height: 160)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4)).cropped(to: CGRect(origin: .zero, size: size))
        var correction = PerspectiveCorrection(mode: .vertical, vertical: 40)
        // 위가 넓어지면 아래 모서리가 빈다(메모리 마지막 행 = 아래).
        let bottomLeft = ((Int(size.height) - 1) * Int(size.width)) * 4
        let center = ((Int(size.height) / 2) * Int(size.width) + Int(size.width) / 2) * 4

        let white = render(ImageTransformStage.apply(to: image, transform: ImageTransform(perspective: correction), fill: .white))
        XCTAssertEqual(white.count, Int(size.width * size.height) * 4)
        XCTAssertTrue(white.indices.filter { $0 % 4 == 3 }.allSatisfy { white[$0] > 0.999 })
        XCTAssertGreaterThan(white[bottomLeft], 0.99)

        let clear = ImageTransformStage.apply(to: image, transform: ImageTransform(perspective: correction), fill: .transparent)
        XCTAssertEqual(clear.extent.size, size, "투명 채움도 출력 사각형 전체를 유지해야 뒤 단계 좌표가 맞습니다")
        let clearPixels = render(clear)
        XCTAssertEqual(clearPixels[bottomLeft + 3], 0, accuracy: 1e-6, "빈 곳은 알파 0 이어야 합니다")
        XCTAssertEqual(clearPixels[bottomLeft], 0, accuracy: 1e-6, "빈 곳에 색이 남으면 오버레이가 사진을 덮습니다")
        XCTAssertEqual(clearPixels[center + 3], 1, accuracy: 1e-4)
        XCTAssertEqual(clearPixels[center + 2], white[center + 2], accuracy: 1e-4, "사진 부분은 채움과 무관합니다")

        correction.constrainCrop = true
        for fill in [ImageTransformFill.white, .transparent] {
            let constrained = ImageTransformStage.apply(to: image, transform: ImageTransform(perspective: correction), fill: fill)
            XCTAssertLessThan(constrained.extent.width, size.width)
            XCTAssertEqual(constrained.extent.width / constrained.extent.height, size.width / size.height, accuracy: 0.02)
            let reference = render(image)
            let pixels = render(constrained)
            var worst: Float = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                worst = max(worst, abs(pixels[i] - reference[0]), abs(pixels[i + 2] - reference[2]),
                            abs(pixels[i + 3] - 1))
            }
            XCTAssertLessThan(worst, 0.002, "자르기 제한 안에 빈 곳이 섞였습니다")
        }
    }

    /// 투명한 오버레이(색역·클리핑 경고)를 변환해도 사진을 덮는 판이 되지 않는다 — 1.2.6 흰 화면 회귀.
    func testTransparentOverlayStaysTransparentThroughPerspective() throws {
        let size = CGSize(width: 300, height: 200)
        let overlay = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: CGRect(origin: .zero, size: size))
        let correction = PerspectiveCorrection(mode: .off, vertical: 22)
        let transform = ImageTransform(cropRect: SIMD4(0.2, 0, 0.6, 1), straightenAngle: -0.2, perspective: correction)
        let pixels = render(ImageTransformStage.apply(to: overlay, transform: transform, fill: .transparent))
        XCTAssertFalse(pixels.isEmpty)
        XCTAssertEqual(pixels.max() ?? 1, 0, accuracy: 1e-6, "투명 오버레이가 변환 뒤 불투명해졌습니다")
    }

    /// 화소 읽기·스포이드: 빈 곳은 원본이 아니고, 사진 위 점은 원본 좌표로 풀린다.
    func testSourceUnitRejectsTheUncoveredArea() throws {
        let base = CGSize(width: 1500, height: 1000)
        let transform = ImageTransform(perspective: PerspectiveCorrection(mode: .off, vertical: 40))
        XCTAssertNil(transform.sourceUnit(atDisplayUnit: CGPoint(x: 0.01, y: 0.99), baseSize: base))
        let center = try XCTUnwrap(transform.sourceUnit(atDisplayUnit: CGPoint(x: 0.5, y: 0.5), baseSize: base))
        XCTAssertEqual(center.x, 0.5, accuracy: 1e-6)
        XCTAssertTrue((0...1).contains(center.y))
        // 원근이 없으면 화면 전체가 원본이다.
        XCTAssertNotNil(ImageTransform(straightenAngle: 3).sourceUnit(atDisplayUnit: CGPoint(x: 0, y: 1), baseSize: base))
    }

    /// 마스크·브러시가 쓰는 화면 ↔ 원본 좌표 변환이 원근과 수평 보정·크롭·회전을 함께 정확히 푼다.
    func testDisplayAndBaseCoordinatesRoundTripThroughPerspective() throws {
        let base = CGSize(width: 1500, height: 1000)
        for seed in 0..<15 {
            var c = sample(seed)
            c.constrainCrop = seed % 2 == 0
            let transform = ImageTransform(
                rotation: seed % 3 == 0 ? .deg90 : .deg0,
                flipHorizontal: seed % 4 == 1,
                cropRect: SIMD4(0.1, 0.12, 0.7, 0.75),
                straightenAngle: Double(seed % 5) - 2,
                perspective: c
            )
            for p in [CGPoint(x: 0.3, y: 0.4), CGPoint(x: 0.8, y: 0.2)] {
                let b = transform.displayUnitToBase(p, baseSize: base)
                let back = transform.baseUnitToDisplay(b, baseSize: base)
                XCTAssertEqual(back.x, p.x, accuracy: 1e-7, "\(seed)")
                XCTAssertEqual(back.y, p.y, accuracy: 1e-7, "\(seed)")
            }
        }
    }

    func testCodableKeepsOldCatalogBytesAndRejectsGarbage() throws {
        let plain = ImageTransform(rotation: .deg90, straightenAngle: 1.5)
        let json = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("perspective"))
        let decoded = try JSONDecoder().decode(ImageTransform.self, from: Data("""
        {"rotation":0,"flipHorizontal":false,"flipVertical":false,"straightenAngle":0,
         "perspective":{"mode":"bogus","vertical":900,"scale":1e9,"guides":[]}}
        """.utf8))
        XCTAssertEqual(decoded.perspective.mode, .off)
        XCTAssertEqual(decoded.perspective.vertical, 100)
        XCTAssertEqual(decoded.perspective.scale, 150)
        let roundTrip = ImageTransform(perspective: sample(3))
        XCTAssertEqual(try JSONDecoder().decode(ImageTransform.self, from: JSONEncoder().encode(roundTrip)), roundTrip)
    }

    // MARK: 도우미

    /// 가로·세로 막대 격자를 `distortion` 으로 일그러뜨린 감마 밝기 그림(해석적으로 샘플링).
    private func warpedGrid(size: CGSize, distortion: PerspectiveCorrection) throws -> ([Float], Int, Int) {
        let w = Int(size.width), h = Int(size.height)
        let inverse = cameraTiltInverse(distortion, size: size)
        var luma = [Float](repeating: 0.85, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                guard let source = PerspectiveGeometry.apply(inverse, CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                else { continue }
                let sx = Double(source.x), sy = Double(source.y)
                guard sx >= 0, sy >= 0, sx < Double(w), sy < Double(h) else { luma[y * w + x] = 0.5; continue }
                let onVertical = (sx + 30).truncatingRemainder(dividingBy: 90) < 7
                let onHorizontal = (sy + 30).truncatingRemainder(dividingBy: 90) < 7
                luma[y * w + x] = onVertical || onHorizontal ? 0.15 : 0.85
            }
        }
        return (luma, w, h)
    }

    /// 실제 카메라를 기울인 것과 같은 왜곡의 역 호모그래피(픽셀 → 픽셀). 보정 식과 달리 중심을 되돌리지
    /// 않는다 — 실제 사진의 원근은 이미지 중심을 주점으로 한 순수 회전이고, 풀이도 그 모형을 쓴다.
    private func cameraTiltInverse(_ c: PerspectiveCorrection, size: CGSize) -> simd_double3x3 {
        let w = Double(size.width), h = Double(size.height), s = max(w, h) / 2
        let f = PerspectiveGeometry.focalLength
        let toNormal = simd_double3x3(rows: [SIMD3(1 / s, 0, -w / 2 / s), SIMD3(0, 1 / s, -h / 2 / s), SIMD3(0, 0, 1)])
        let toPixel = simd_double3x3(rows: [SIMD3(s, 0, w / 2), SIMD3(0, s, h / 2), SIMD3(0, 0, 1)])
        let k = simd_double3x3(rows: [SIMD3(f, 0, 0), SIMD3(0, f, 0), SIMD3(0, 0, 1)])
        let r = PerspectiveGeometry.rotationMatrix(-PerspectiveGeometry.rotationVector(for: c))
        return toPixel * k * r * k.inverse * toNormal
    }

    private func render(_ image: CIImage) -> [Float] {
        let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var pixels = [Float](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &pixels, rowBytes: w * 16, bounds: image.extent,
                       format: .RGBAf, colorSpace: space)
        return pixels
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func nextUInt() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextUInt() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}

/// 원근 보정의 빈 곳(알파 0)은 자동 톤·화이트 밸런스 통계에 들어가지 않는다.
final class TransformCoverageStatisticsTests: XCTestCase {
    func testAutoAdjustStatisticsIgnoreTheUncoveredArea() throws {
        let width = 400, height = 300
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func image(transparentRight: Bool) throws -> CGImage {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: 0.35, green: 0.30, blue: 0.25, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if transparentRight {
                context.clear(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
            } else {
                // 같은 자리를 흰색으로 구우면(예전 동작) 통계가 하이라이트 쪽으로 끌려간다.
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
            }
            return try XCTUnwrap(context.makeImage())
        }
        let photoOnly = try XCTUnwrap(AutoAdjust.imageStats(try image(transparentRight: true)))
        XCTAssertEqual(photoOnly.avgR, 0.35, accuracy: 0.01)
        XCTAssertEqual(photoOnly.avgB, 0.25, accuracy: 0.01)
        XCTAssertEqual(photoOnly.lumaHist.suffix(10).reduce(0, +), 0, accuracy: 1e-9, "빈 곳이 하이라이트로 세어졌습니다")
        let whiteBaked = try XCTUnwrap(AutoAdjust.imageStats(try image(transparentRight: false)))
        XCTAssertGreaterThan(whiteBaked.avgR, 0.6, "대조군: 흰색으로 구우면 평균이 크게 밝아진다")
    }
}
