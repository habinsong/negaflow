import XCTest
import CoreImage
import CoreGraphics
@testable import Chromabase

// InfraredDefectRemoval 합성 픽스처 테스트. 실제 이미지 없이 수치로 검증한다:
//   • 먼지/스크래치(IR 에서 어두움)는 잡고, 이미지 누설(red 상관)·비네팅·홀더 마진은 잡지 않는다.
//   • IR↔raw 정수 오프셋을 복원해 마스크가 raw 좌표에 놓인다.
//   • 마스크 과대(흑백/정렬 실패급)는 적용을 포기한다.
final class InfraredDefectTests: XCTestCase {

    private let width = 256
    private let height = 224

    /// 결정적 의사난수(테스트 재현성).
    private struct SeededNoise {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float((state >> 33) & 0xFFFF) / 65535.0 - 0.5
        }
    }

    /// 합성 장면: red = 완만한 경사 + 강한 세로 스텝 에지, ir = c + a·ln(red) 누설 + 노이즈.
    private func makeScene(leak: Float = 0.05, noiseSigma: Float = 0.004,
                           vignette: Float = 0) -> (red: [Float], ir: [Float]) {
        var red = [Float](repeating: 0, count: width * height)
        var ir = [Float](repeating: 0, count: width * height)
        var noise = SeededNoise(seed: 42)
        for y in 0..<height {
            for x in 0..<width {
                var r: Float = 0.2 + 0.45 * Float(x) / Float(width)
                if x >= 128 { r += 0.2 }            // 강한 세로 스텝 에지(이미지 구조)
                if (y / 24) % 2 == 0 { r += 0.08 }  // 가로 줄무늬(y 방향 구조 — 정렬 anchor)
                var v: Float = 1
                if vignette > 0 {
                    let dx = Float(x) / Float(width) - 0.5
                    let dy = Float(y) / Float(height) - 0.5
                    v = 1 - vignette * (dx * dx + dy * dy) * 4
                }
                let i = y * width + x
                red[i] = min(1, r * v)
                ir[i] = min(1, (0.82 + leak * log(max(red[i], 1e-4))) * v) + noiseSigma * noise.next() * 2
            }
        }
        return (red, ir)
    }

    private func stampSpot(_ plane: inout [Float], cx: Int, cy: Int, radius: Int, depth: Float) {
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let dx = x - cx, dy = y - cy
                if dx * dx + dy * dy <= radius * radius {
                    plane[y * width + x] = max(0, plane[y * width + x] - depth)
                }
            }
        }
    }

    private func stampVerticalScratch(_ plane: inout [Float], x: Int, y0: Int, y1: Int, depth: Float) {
        for y in y0...y1 {
            for xx in x...(x + 1) {
                plane[y * width + xx] = max(0, plane[y * width + xx] - depth)
            }
        }
    }

    /// 클러스터 마스크가 raw(y-down) 픽셀 (x, y)를 흰색으로 덮는가.
    private func maskCovers(_ detection: InfraredDefectRemoval.Detection, x: Int, y: Int) -> Bool {
        for cluster in detection.clusters {
            let x0 = Int(cluster.roiYup.minX)
            let y0 = detection.height - Int(cluster.roiYup.maxY)   // y-up rect → y-down top
            let lx = x - x0, ly = y - y0
            guard lx >= 0, lx < cluster.width, ly >= 0, ly < cluster.height else { continue }
            if cluster.maskRGBA8[(ly * cluster.width + lx) * 4] == 255 { return true }
        }
        return false
    }

    private var fastParameters: InfraredDefectRemoval.Parameters {
        InfraredDefectRemoval.Parameters(alignmentSearchRadius: 0)
    }

    // MARK: 검출/비검출

    func testDetectsSpotsAndScratchButNotImageEdgesOrVignette() throws {
        var (red, ir) = makeScene(leak: 0.05, vignette: 0.12)
        let spots = [(40, 40), (200, 60), (70, 160), (150, 190)]
        for (cx, cy) in spots { stampSpot(&ir, cx: cx, cy: cy, radius: 3, depth: 0.35) }
        stampVerticalScratch(&ir, x: 96, y0: 30, y1: 190, depth: 0.3)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()

        XCTAssertGreaterThanOrEqual(detection.components.count, 5, "먼지 4 + 스크래치 1 이상 검출돼야 한다.")
        for (cx, cy) in spots {
            XCTAssertTrue(maskCovers(detection, x: cx, y: cy), "먼지(\(cx),\(cy))가 마스크에 덮여야 한다.")
        }
        XCTAssertTrue(maskCovers(detection, x: 96, y: 110), "스크래치가 마스크에 덮여야 한다.")
        XCTAssertTrue(detection.components.contains { $0.classification == .scratchVertical },
                      "세로로 긴 결함은 scratchVertical 로 분류돼야 한다.")
        // 이미지 스텝 에지(x=128)는 red 상관 누설 — 스펙트럴 클린으로 걸러져야 한다.
        // 스탬프한 결함(먼지/스크래치) 근처는 검사에서 제외한다.
        for y in stride(from: 8, to: height - 8, by: 16) {
            for x in 126...130 {
                let nearDefect = spots.contains { abs($0.0 - x) < 10 && abs($0.1 - y) < 10 }
                guard !nearDefect else { continue }
                XCTAssertFalse(maskCovers(detection, x: x, y: y),
                               "이미지 에지(x=\(x),y=\(y))가 결함으로 오검출되면 안 된다.")
            }
        }
        XCTAssertLessThan(detection.coverage, 0.01, "정상 장면에서 마스크 커버리지는 1% 미만이어야 한다.")
    }

    /// 컬러 네거티브는 염료가 IR 을 거의 다 통과시킨다(GT-X900 실측: 평균 투과 98.9%,
    /// 표준편차 0.9%). 그러면 결함의 국소 상대 대비가 수 % 에 그쳐서, 고정 하한 0.035 를
    /// 쓰면 실제 먼지가 통째로 문턱 아래로 묻힌다. 하한을 실측 잡음에서 끌어내야 잡힌다.
    func testDetectsShallowDefectsOnHighTransmissionFilm() throws {
        // IR 이 0.99 근처에 몰린 균일한 평면 — 실측 컬러 네거티브 거동.
        var red = [Float](repeating: 0, count: width * height)
        var ir = [Float](repeating: 0, count: width * height)
        var noise = SeededNoise(seed: 7)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                red[i] = 0.30 + 0.35 * Float(x) / Float(width)
                ir[i] = 0.989 + 0.003 * noise.next() * 2
            }
        }
        // 투과율이 높은 만큼 결함도 얕게 찍힌다(대비 약 3%).
        let spots = [(60, 50), (170, 90), (100, 170)]
        for (cx, cy) in spots { stampSpot(&ir, cx: cx, cy: cy, radius: 3, depth: 0.030) }

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()
        for (cx, cy) in spots {
            XCTAssertTrue(maskCovers(detection, x: cx, y: cy),
                          "얕은 먼지(\(cx),\(cy))가 검출돼야 한다 — 고정 하한이면 묻힌다.")
        }
        XCTAssertLessThan(detection.coverage, 0.02, "균일한 배경이 결함으로 번지면 안 된다.")
    }

    func testRejectsComponentsBelowMinArea() throws {
        var (red, ir) = makeScene()
        ir[100 * width + 30] = max(0, ir[100 * width + 30] - 0.4)   // 1px 노이즈
        stampSpot(&ir, cx: 180, cy: 100, radius: 3, depth: 0.35)     // 진짜 먼지

        var params = fastParameters
        params.minArea = 3
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        XCTAssertEqual(detection.components.count, 1, "minArea 미만 1px 성분은 버려야 한다.")
        XCTAssertTrue(maskCovers(detection, x: 180, y: 100))
        XCTAssertFalse(maskCovers(detection, x: 30, y: 100))
    }

    func testExcludesBorderConnectedDarkMargins() throws {
        var (red, ir) = makeScene()
        // 왼쪽 24열 = 필름 홀더(IR/red 모두 거의 불투과), 테두리 연결.
        for y in 0..<height {
            for x in 0..<24 {
                ir[y * width + x] = 0.02
                red[y * width + x] = 0.02
            }
        }
        stampSpot(&ir, cx: 150, cy: 100, radius: 3, depth: 0.35)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()
        XCTAssertTrue(maskCovers(detection, x: 150, y: 100))
        for y in stride(from: 4, to: height - 4, by: 12) {
            for x in 0..<30 {
                XCTAssertFalse(maskCovers(detection, x: x, y: y),
                               "홀더 마진(x=\(x))이 결함으로 잡히면 안 된다.")
            }
        }
    }

    func testAbortsWhenMaskCoverageExplodes() {
        var (red, ir) = makeScene()
        // 내부(테두리 비연결)에 광범위 어두운 패치 — 흑백/정렬 실패급 상황.
        for y in 40..<180 {
            for x in 40..<216 where (x / 3 + y / 3) % 2 == 0 {
                ir[y * width + x] = max(0, ir[y * width + x] - 0.4)
            }
        }
        let outcome = InfraredDefectRemoval.detect(infrared: ir, red: red,
                                         width: width, height: height,
                                         parameters: fastParameters)
        guard case .failure(.coverageTooHigh(let coverage)) = outcome else {
            return XCTFail("커버리지 폭주는 coverageTooHigh 로 중단돼야 한다: \(outcome)")
        }
        XCTAssertGreaterThan(coverage, 0.05)
    }

    func testCleanSceneReportsNoDefects() {
        let (red, ir) = makeScene()
        let outcome = InfraredDefectRemoval.detect(infrared: ir, red: red,
                                         width: width, height: height,
                                         parameters: fastParameters)
        guard case .failure(.noDefects) = outcome else {
            return XCTFail("결함 없는 장면은 noDefects 여야 한다: \(outcome)")
        }
    }

    func testRemovesNonlinearSceneLeakageWithoutMaskingRealDust() throws {
        var red = [Float](repeating: 0, count: width * height)
        var infrared = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let redValue = 0.08 + 0.86 * Float(x) / Float(width - 1)
                let logRed = log(redValue)
                let index = y * width + x
                red[index] = redValue
                infrared[index] = 0.78 + 0.055 * logRed + 0.022 * logRed * logRed
            }
        }
        stampSpot(&infrared, cx: 176, cy: 96, radius: 3, depth: 0.30)

        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: fastParameters
        ).get()

        XCTAssertTrue(maskCovers(detection, x: 176, y: 96))
        XCTAssertLessThan(detection.coverage, 0.002)
        for x in stride(from: 16, to: width - 16, by: 16) where abs(x - 176) > 12 {
            XCTAssertFalse(maskCovers(detection, x: x, y: 96))
        }
    }

    func testRelativeContrastDetectsDustAcrossIlluminationLevels() throws {
        var red = [Float](repeating: 0, count: width * height)
        var infrared = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let brightness = 0.20 + 0.70 * Float(x) / Float(width - 1)
                let index = y * width + x
                red[index] = brightness
                infrared[index] = brightness
            }
        }
        stampSpot(&infrared, cx: 48, cy: 112, radius: 3, depth: 0.09)
        stampSpot(&infrared, cx: 208, cy: 112, radius: 3, depth: 0.27)

        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: fastParameters
        ).get()

        XCTAssertTrue(maskCovers(detection, x: 48, y: 112))
        XCTAssertTrue(maskCovers(detection, x: 208, y: 112))
        XCTAssertLessThan(detection.coverage, 0.004)
    }

    func testInvalidParametersAreClampedAndDoNotCrashClusterRendering() throws {
        var parameters = InfraredDefectRemoval.Parameters(
            sensitivity: .nan,
            dilateRadius: -4,
            minArea: 0,
            maxCoverage: .infinity,
            alignmentSearchRadius: -8,
            clusterTile: 0,
            clusterPadding: -12
        )
        XCTAssertEqual(parameters.sensitivity, 0.5)
        XCTAssertEqual(parameters.dilateRadius, 0)
        XCTAssertEqual(parameters.minArea, 1)
        XCTAssertEqual(parameters.maxCoverage, 0.05)
        XCTAssertEqual(parameters.alignmentSearchRadius, 0)
        XCTAssertEqual(parameters.clusterTile, 1)
        XCTAssertEqual(parameters.clusterPadding, 0)

        parameters.sensitivity = .nan
        parameters.dilateRadius = -4
        parameters.minArea = 0
        parameters.maxCoverage = .infinity
        parameters.alignmentSearchRadius = -8
        parameters.clusterTile = 0
        parameters.clusterPadding = -12
        var (red, infrared) = makeScene()
        stampSpot(&infrared, cx: 80, cy: 80, radius: 3, depth: 0.4)
        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: parameters
        ).get()

        XCTAssertTrue(maskCovers(detection, x: 80, y: 80))
    }

    // MARK: 정렬

    func testRecoversIntegerOffsetAndPlacesMaskInRawCoordinates() throws {
        var (red, irAligned) = makeScene(leak: 0.08)
        stampSpot(&irAligned, cx: 120, cy: 90, radius: 3, depth: 0.35)
        // IR 패스가 (3, 2)만큼 어긋난 상황: irShifted(x, y) = irAligned(x-3, y-2).
        var dummy = [Bool](repeating: false, count: width * height)
        let irShifted = InfraredDefectRemoval.shiftPlane(irAligned, width: width, height: height,
                                               dx: -3, dy: -2, outOfBounds: &dummy)

        var params = fastParameters
        params.alignmentSearchRadius = 8
        let detection = try InfraredDefectRemoval.detect(infrared: irShifted, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        XCTAssertEqual(detection.offsetX, 3, "IR→raw x 오프셋을 복원해야 한다.")
        XCTAssertEqual(detection.offsetY, 2, "IR→raw y 오프셋을 복원해야 한다.")
        XCTAssertEqual(detection.alignment.status, .aligned)
        XCTAssertNotNil(detection.alignment.peakCorrelation)
        XCTAssertTrue(maskCovers(detection, x: 120, y: 90),
                      "마스크는 raw 좌표(오프셋 보정 후)에 놓여야 한다.")
    }

    func testRejectsAlignmentWhenInfraredHasNoRegistrationTexture() {
        let red = [Float](repeating: 0.5, count: width * height)
        let infrared = [Float](repeating: 0.8, count: width * height)
        let outcome = InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: InfraredDefectRemoval.Parameters(alignmentSearchRadius: 6)
        )

        guard case .failure(.alignmentUnreliable(let diagnostics)) = outcome else {
            return XCTFail("정렬 단서가 없으면 IR 마스크를 적용하면 안 됩니다: \(outcome)")
        }
        XCTAssertEqual(diagnostics.status, .insufficientTexture)
    }

    func testRejectsAlignmentAtSearchBoundary() {
        let (red, alignedInfrared) = makeScene(leak: 0.08)
        var excluded = [Bool](repeating: false, count: width * height)
        let shiftedInfrared = InfraredDefectRemoval.shiftPlane(
            alignedInfrared,
            width: width,
            height: height,
            dx: -6,
            dy: 0,
            outOfBounds: &excluded
        )
        let outcome = InfraredDefectRemoval.detect(
            infrared: shiftedInfrared,
            red: red,
            width: width,
            height: height,
            parameters: InfraredDefectRemoval.Parameters(alignmentSearchRadius: 6)
        )

        guard case .failure(.alignmentUnreliable(let diagnostics)) = outcome else {
            return XCTFail("최적점이 탐색 경계면이면 더 큰 오프셋 가능성을 숨기면 안 됩니다: \(outcome)")
        }
        XCTAssertEqual(diagnostics.status, .searchLimitReached)
        XCTAssertEqual(abs(diagnostics.offsetX), 6)
    }

    // MARK: 클러스터 마스크 형식

    func testClusterMaskDilatesAndMapsROIYUp() throws {
        var (red, ir) = makeScene()
        stampSpot(&ir, cx: 60, cy: 50, radius: 2, depth: 0.4)
        var params = fastParameters
        params.dilateRadius = 2
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        // 팽창: 스팟 가장자리 밖 1~2px 도 마스크에 포함된다.
        XCTAssertTrue(maskCovers(detection, x: 60 + 3, y: 50), "dilate=2 면 스팟 rim 바깥도 덮어야 한다.")
        // 멀리 떨어진 픽셀은 덮지 않는다.
        XCTAssertFalse(maskCovers(detection, x: 60 + 12, y: 50))
        for cluster in detection.clusters {
            XCTAssertEqual(cluster.maskRGBA8.count, cluster.width * cluster.height * 4)
            XCTAssertGreaterThanOrEqual(Int(cluster.roiYup.minY), 0)
            XCTAssertLessThanOrEqual(Int(cluster.roiYup.maxY), detection.height)
        }
    }

    // MARK: 복원 통합(클러스터 마스크 → SoftwareDefectRemoval.repair)

    func testClusterMaskDrivesRepairThatRemovesSpotAndPreservesRest() throws {
        var (red, ir) = makeScene()
        stampSpot(&ir, cx: 128, cy: 112, radius: 3, depth: 0.4)
        var params = fastParameters
        params.dilateRadius = 2
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        let cluster = try XCTUnwrap(detection.clusters.first)

        // 합성 raw: 평탄 0.5 회색 + 같은 위치의 어두운 결함(0.1).
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        var pixels = [Float](repeating: 0.5, count: width * height * 4)
        for i in stride(from: 3, to: pixels.count, by: 4) { pixels[i] = 1 }
        for y in (112 - 3)...(112 + 3) {
            for x in (128 - 3)...(128 + 3) where (x - 128) * (x - 128) + (y - 112) * (y - 112) <= 9 {
                let o = (y * width + x) * 4
                pixels[o] = 0.1; pixels[o + 1] = 0.1; pixels[o + 2] = 0.1
            }
        }
        // CIImage(bitmapData:)는 첫 행=위(y-down) — 검출 마스크와 같은 규약.
        let raw = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: width, height: height),
            format: .RGBAf, colorSpace: linear
        )
        let maskCI = CIImage(
            bitmapData: cluster.maskRGBA8, bytesPerRow: cluster.width * 4,
            size: CGSize(width: cluster.width, height: cluster.height),
            format: .RGBA8, colorSpace: linear
        ).transformed(by: CGAffineTransform(translationX: cluster.roiYup.minX,
                                            y: cluster.roiYup.minY))
        let repaired = SoftwareDefectRemoval.repair(image: raw, roi: cluster.roiYup, mask: maskCI)

        let context = CIContext(options: [.workingColorSpace: linear, .outputColorSpace: linear])
        var out = [Float](repeating: 0, count: width * height * 4)
        context.render(repaired, toBitmap: &out, rowBytes: width * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: linear)
        // render 는 y-up 원점 기준 → 버퍼 첫 행이 이미지 위쪽(y-down 표기와 동일 행 순서).
        let spotIdx = (112 * width + 128) * 4
        XCTAssertEqual(Double(out[spotIdx]), 0.5, accuracy: 0.06,
                       "결함 픽셀이 주변값(0.5)으로 복원돼야 한다.")
        let farIdx = (30 * width + 30) * 4
        XCTAssertEqual(Double(out[farIdx]), 0.5, accuracy: 0.01,
                       "결함에서 먼 픽셀은 변하지 않아야 한다.")
    }

    // MARK: CI 평면 렌더 (R 채널, y-down 행 순서)

    func testRenderRedPlaneExtractsRedChannelTopDown() throws {
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let w = 4, h = 2
        // 위 행 R=0.8, 아래 행 R=0.2 (G/B 는 다른 값 — R 만 나와야 한다).
        var pixels = [Float]()
        for y in 0..<h {
            for _ in 0..<w {
                let r: Float = y == 0 ? 0.8 : 0.2
                pixels += [r, 0.11, 0.93, 1]
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes: pixels, count: pixels.count * MemoryLayout<Float>.size),
            bytesPerRow: w * 4 * MemoryLayout<Float>.size,
            size: CGSize(width: w, height: h),
            format: .RGBAf, colorSpace: linear
        )
        let plane = try XCTUnwrap(InfraredDefectRemoval.renderRedPlane(image, width: w, height: h))
        XCTAssertEqual(plane.count, w * h)
        XCTAssertEqual(Double(plane[0]), 0.8, accuracy: 0.01, "첫 행은 이미지 위쪽(R=0.8)이어야 한다.")
        XCTAssertEqual(Double(plane[w]), 0.2, accuracy: 0.01, "둘째 행은 아래쪽(R=0.2)이어야 한다.")
    }
}
