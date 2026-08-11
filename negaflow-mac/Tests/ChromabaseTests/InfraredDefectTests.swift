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

    /// 먼지·스크래치는 파장에 관계없이 같은 비율로 빛을 막는다. 그래서 픽스처도 IR 과 가시광에
    /// **같은 투과율**을 곱한다. 예전 픽스처는 IR 에만 결함을 찍었는데, 그런 결함은 물리적으로
    /// 존재할 수 없고(가시광을 통과시키는 먼지), 새 파이프라인은 사진에서 확인되지 않는 후보를
    /// 기각하므로 그 픽스처로는 아무것도 검증되지 않는다.
    private func occlude(_ ir: inout [Float], _ visible: inout [Float],
                         at index: Int, depth: Float) {
        let before = ir[index]
        let after = max(0, before - depth)
        ir[index] = after
        visible[index] *= before > 1e-4 ? after / before : 0
    }

    private func stampSpot(_ ir: inout [Float], _ visible: inout [Float],
                           cx: Int, cy: Int, radius: Int, depth: Float) {
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let dx = x - cx, dy = y - cy
                if dx * dx + dy * dy <= radius * radius {
                    occlude(&ir, &visible, at: y * width + x, depth: depth)
                }
            }
        }
    }

    private func stampVerticalScratch(_ ir: inout [Float], _ visible: inout [Float],
                                      x: Int, y0: Int, y1: Int, depth: Float) {
        for y in y0...y1 {
            for xx in x...(x + 1) {
                occlude(&ir, &visible, at: y * width + xx, depth: depth)
            }
        }
    }

    /// raw(y-down) 픽셀 (x, y)에 적용될 가시광 감쇠. 새 경로의 산출물은 이진 마스크가 아니라
    /// 감쇠 창이다 — 대부분의 결함은 부분 폐색이라 나눗셈으로 되돌리고, 코어 마스크에는
    /// 되돌릴 수 없는 완전 폐색만 들어간다.
    private func attenuation(_ detection: InfraredDefectRemoval.Detection,
                             x: Int, y: Int) -> Float {
        for cluster in detection.clusters {
            guard let data = cluster.attenuationR16 else { continue }
            let x0 = Int(cluster.roiYup.minX)
            let y0 = detection.height - Int(cluster.roiYup.maxY)   // y-up rect → y-down top
            let lx = x - x0, ly = y - y0
            guard lx >= 0, lx < cluster.width, ly >= 0, ly < cluster.height else { continue }
            let value = data.withUnsafeBytes { raw in
                raw.bindMemory(to: UInt16.self)[ly * cluster.width + lx]
            }
            if value > 0 { return Float(value) / 65535 }
        }
        return 0
    }

    /// 그 픽셀이 실제로 보정되는가(감쇠 2% 이상 — 그 아래는 잡음과 구분되지 않는다).
    private func corrects(_ detection: InfraredDefectRemoval.Detection, x: Int, y: Int) -> Bool {
        attenuation(detection, x: x, y: y) >= 0.02
    }

    private var fastParameters: InfraredDefectRemoval.Parameters {
        InfraredDefectRemoval.Parameters(alignmentSearchRadius: 0)
    }

    // MARK: 검출/비검출

    func testDetectsSpotsAndScratchButNotImageEdgesOrVignette() throws {
        var (red, ir) = makeScene(leak: 0.05, vignette: 0.12)
        let spots = [(40, 40), (200, 60), (70, 160), (150, 190)]
        for (cx, cy) in spots { stampSpot(&ir, &red, cx: cx, cy: cy, radius: 3, depth: 0.35) }
        stampVerticalScratch(&ir, &red, x: 96, y0: 30, y1: 190, depth: 0.3)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()

        XCTAssertGreaterThanOrEqual(detection.components.count, 5, "먼지 4 + 스크래치 1 이상 검출돼야 한다.")
        for (cx, cy) in spots {
            XCTAssertTrue(corrects(detection, x: cx, y: cy), "먼지(\(cx),\(cy))가 마스크에 덮여야 한다.")
        }
        XCTAssertTrue(corrects(detection, x: 96, y: 110), "스크래치가 마스크에 덮여야 한다.")
        XCTAssertTrue(detection.components.contains { $0.classification == .scratchVertical },
                      "세로로 긴 결함은 scratchVertical 로 분류돼야 한다.")
        // 이미지 스텝 에지(x=128)는 red 상관 누설 — 스펙트럴 클린으로 걸러져야 한다.
        // 스탬프한 결함(먼지/스크래치) 근처는 검사에서 제외한다.
        for y in stride(from: 8, to: height - 8, by: 16) {
            for x in 126...130 {
                let nearDefect = spots.contains { abs($0.0 - x) < 10 && abs($0.1 - y) < 10 }
                guard !nearDefect else { continue }
                XCTAssertFalse(corrects(detection, x: x, y: y),
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
        for (cx, cy) in spots { stampSpot(&ir, &red, cx: cx, cy: cy, radius: 3, depth: 0.030) }

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()
        for (cx, cy) in spots {
            XCTAssertTrue(corrects(detection, x: cx, y: cy),
                          "얕은 먼지(\(cx),\(cy))가 검출돼야 한다 — 고정 하한이면 묻힌다.")
        }
        XCTAssertLessThan(detection.coverage, 0.02, "균일한 배경이 결함으로 번지면 안 된다.")
    }

    func testRejectsComponentsBelowMinArea() throws {
        var (red, ir) = makeScene()
        ir[100 * width + 30] = max(0, ir[100 * width + 30] - 0.4)   // 1px 노이즈
        stampSpot(&ir, &red, cx: 180, cy: 100, radius: 3, depth: 0.35)     // 진짜 먼지

        var params = fastParameters
        params.minArea = 3
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        XCTAssertEqual(detection.components.count, 1, "minArea 미만 1px 성분은 버려야 한다.")
        XCTAssertTrue(corrects(detection, x: 180, y: 100))
        XCTAssertFalse(corrects(detection, x: 30, y: 100))
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
        stampSpot(&ir, &red, cx: 150, cy: 100, radius: 3, depth: 0.35)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()
        XCTAssertTrue(corrects(detection, x: 150, y: 100))
        for y in stride(from: 4, to: height - 4, by: 12) {
            for x in 0..<30 {
                XCTAssertFalse(corrects(detection, x: x, y: y),
                               "홀더 마진(x=\(x))이 결함으로 잡히면 안 된다.")
            }
        }
    }

    func testAbortsWhenMaskCoverageExplodes() {
        var (red, ir) = makeScene()
        // 확인 가능한 작은 결함이 프레임을 뒤덮은 상황(정렬 실패·이물 범벅). 넓은 한 덩어리는
        // 국소 기준선에 통째로 흡수돼 애초에 후보가 되지 않으므로, 폭주는 이렇게 만들어야 한다.
        var cy = 30
        while cy < height - 30 {
            var cx = 30
            while cx < width - 30 {
                stampSpot(&ir, &red, cx: cx, cy: cy, radius: 3, depth: 0.4)
                cx += 9
            }
            cy += 9
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
        stampSpot(&infrared, &red, cx: 176, cy: 96, radius: 3, depth: 0.30)

        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: fastParameters
        ).get()

        XCTAssertTrue(corrects(detection, x: 176, y: 96))
        XCTAssertLessThan(detection.coverage, 0.002)
        for x in stride(from: 16, to: width - 16, by: 16) where abs(x - 176) > 12 {
            XCTAssertFalse(corrects(detection, x: x, y: 96))
        }
    }

    func testRelativeContrastDetectsDustAcrossIlluminationLevels() throws {
        var red = [Float](repeating: 0, count: width * height)
        var infrared = [Float](repeating: 0, count: width * height)
        // 실제 스캔에는 반드시 잡음이 있다. 잡음이 정확히 0 인 평면에서는 문턱을 세울 잡음
        // 자체가 없어(결함 헤일로가 상위 분위를 차지한다) 추정기가 의미를 잃는다.
        var noise = SeededNoise(seed: 11)
        for y in 0..<height {
            for x in 0..<width {
                let brightness = 0.20 + 0.70 * Float(x) / Float(width - 1)
                let index = y * width + x
                red[index] = brightness + 0.004 * noise.next() * 2
                infrared[index] = brightness + 0.004 * noise.next() * 2
            }
        }
        stampSpot(&infrared, &red, cx: 48, cy: 112, radius: 3, depth: 0.09)
        stampSpot(&infrared, &red, cx: 208, cy: 112, radius: 3, depth: 0.27)

        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: fastParameters
        ).get()

        XCTAssertTrue(corrects(detection, x: 48, y: 112))
        XCTAssertTrue(corrects(detection, x: 208, y: 112))
        // coverage 는 이제 이진 마스크 면적이 아니라 **실제로 보정되는 면적**(자락 포함)이다.
        XCTAssertLessThan(detection.coverage, 0.05)
        for x in stride(from: 8, to: width - 8, by: 16) where abs(x - 48) > 20 && abs(x - 208) > 20 {
            XCTAssertFalse(corrects(detection, x: x, y: 112),
                           "결함에서 먼 밝기 구간(x=\(x))을 보정하면 안 된다.")
        }
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
        stampSpot(&infrared, &red, cx: 80, cy: 80, radius: 3, depth: 0.4)
        let detection = try InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: parameters
        ).get()

        XCTAssertTrue(corrects(detection, x: 80, y: 80))
    }

    // MARK: 정렬

    func testRecoversIntegerOffsetAndPlacesMaskInRawCoordinates() throws {
        var (red, irAligned) = makeScene(leak: 0.08)
        stampSpot(&irAligned, &red, cx: 120, cy: 90, radius: 3, depth: 0.35)
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
        XCTAssertTrue(corrects(detection, x: 120, y: 90),
                      "마스크는 raw 좌표(오프셋 보정 후)에 놓여야 한다.")
    }

    /// 전역 정합은 조언이지 관문이 아니다. 단서가 없으면 이동 없이 진행하되, 결함마다
    /// 사진에서 확인되지 않으므로 **아무것도 보정하지 않는다**. 예전처럼 검출을 통째로
    /// 포기하면 정합이 조금 어긋난 실기 스캔에서 멀쩡한 결함까지 못 지운다.
    func testUnalignableInfraredCorrectsNothing() {
        let red = [Float](repeating: 0.5, count: width * height)
        let infrared = [Float](repeating: 0.8, count: width * height)
        let outcome = InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: InfraredDefectRemoval.Parameters(alignmentSearchRadius: 6)
        )
        switch outcome {
        case .failure(.noDefects), .failure(.alignmentUnreliable):
            break
        case .success(let detection):
            for y in stride(from: 8, to: height - 8, by: 16) {
                for x in stride(from: 8, to: width - 8, by: 16) {
                    XCTAssertFalse(corrects(detection, x: x, y: y),
                                   "정합 단서가 없는 입력에서 보정하면 안 된다.")
                }
            }
        case .failure(let other):
            XCTFail("예상치 못한 실패: \(other)")
        }
    }

    /// 큰 오프셋이 남아 있어도, 결함마다 사진에서 다시 맞추므로 결함 위에 보정이 놓인다.
    func testLargeResidualOffsetIsStillPlacedOnTheDefect() throws {
        var (red, aligned) = makeScene(leak: 0.08)
        stampSpot(&aligned, &red, cx: 150, cy: 110, radius: 3, depth: 0.35)
        var excluded = [Bool](repeating: false, count: width * height)
        let shifted = InfraredDefectRemoval.shiftPlane(
            aligned, width: width, height: height, dx: -6, dy: 0, outOfBounds: &excluded
        )
        let detection = try InfraredDefectRemoval.detect(
            infrared: shifted, red: red, width: width, height: height,
            parameters: InfraredDefectRemoval.Parameters(alignmentSearchRadius: 12)
        ).get()
        XCTAssertTrue(corrects(detection, x: 150, y: 110),
                      "보정은 IR 좌표가 아니라 사진 속 결함 위에 놓여야 한다.")
    }

    // MARK: 클러스터 마스크 형식

    func testCorrectionWindowCoversDefectSkirtAndMapsROIYUp() throws {
        var (red, ir) = makeScene()
        stampSpot(&ir, &red, cx: 60, cy: 50, radius: 2, depth: 0.4)
        var params = fastParameters
        params.dilateRadius = 2
        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: params).get()
        // 보정은 심에서 가장 세고 바깥으로 갈수록 옅어진다 — 이진 마스크가 아니다.
        let center = attenuation(detection, x: 60, y: 50)
        let rim = attenuation(detection, x: 60 + 3, y: 50)
        XCTAssertGreaterThan(center, 0.05, "결함 중심은 실질적으로 보정돼야 한다.")
        XCTAssertLessThan(rim, center, "감쇠는 중심에서 멀어질수록 줄어야 한다.")
        XCTAssertEqual(attenuation(detection, x: 60 + 14, y: 50), 0,
                       "결함에서 먼 픽셀은 손대지 않아야 한다.")
        for cluster in detection.clusters {
            XCTAssertEqual(cluster.maskRGBA8.count, cluster.width * cluster.height * 4)
            XCTAssertEqual(cluster.attenuationR16?.count, cluster.width * cluster.height * 2)
            XCTAssertGreaterThanOrEqual(Int(cluster.roiYup.minY), 0)
            XCTAssertLessThanOrEqual(Int(cluster.roiYup.maxY), detection.height)
        }
    }

    /// 새 계약의 핵심: IR 에만 있고 사진에는 없는 어두움은 **결함이 아니다**.
    ///
    /// 먼지는 파장에 관계없이 빛을 막으므로 IR 에서만 어두운 결함은 물리적으로 존재할 수 없다.
    /// 실제로 그렇게 보이는 원인은 장면 고스트(시안 염료의 근적외 흡수)와 IR 패스의 정합/초점
    /// 어긋남이고, 실측에서 한 컷은 가장 진한 IR 결함 20개 중 사진에 대응물이 있는 것이
    /// 1개뿐이었다. 그런 후보를 지우면 멀쩡한 필름을 밝게 망친다.
    func testRejectsInfraredOnlyDarkeningThatHasNoCounterpartInThePhotograph() {
        var (red, ir) = makeScene()
        let ghosts = [(70, 60), (150, 120), (200, 170)]
        for (cx, cy) in ghosts {
            for y in (cy - 3)...(cy + 3) {
                for x in (cx - 3)...(cx + 3)
                where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= 9 {
                    ir[y * width + x] = max(0, ir[y * width + x] - 0.35)   // red 는 건드리지 않는다
                }
            }
        }
        var params = fastParameters
        params.alignmentSearchRadius = 6
        let outcome = InfraredDefectRemoval.detect(infrared: ir, red: red,
                                                   width: width, height: height,
                                                   parameters: params)
        if case .success(let detection) = outcome {
            for (cx, cy) in ghosts {
                XCTAssertFalse(corrects(detection, x: cx, y: cy),
                               "사진에 없는 IR 어두움(\(cx),\(cy))을 보정하면 안 된다.")
            }
        }
    }

    // MARK: 뚱뚱한 먼지 — 구조요소보다 큰 결함, 그리고 옅고 넓은 결함

    /// 넓은 프레임에 구조요소만 한 먼지를 찍고 **중심**이 실제로 되돌려지는지 본다.
    ///
    /// 기준선(closing)이 결함보다 좁으면 결함 한가운데가 자기 자신을 기준선으로 삼아 밀도가
    /// 줄고, 중심만 덜 지워져 "뚱뚱하고 흐릿한 자국"이 남는다. 실측(GT-X900 2400dpi)에서
    /// 좁은쪽 반지름 12px 이상 먼지의 밀도가 진짜의 43~65% 로 축소됐고 18px 이상은 보정량이
    /// 0 이었다. 그래서 구조요소는 관측이 아니라 해상도에서 정한다 — 이 픽스처가 그 회귀 가드다.
    func testDustWiderThanASmallStructuringElementIsRestoredAtItsCentre() throws {
        let side = 1200
        var red = [Float](repeating: 0, count: side * side)
        var ir = [Float](repeating: 0, count: side * side)
        var noise = SeededNoise(seed: 11)
        for y in 0..<side {
            for x in 0..<side {
                let i = y * side + x
                red[i] = 0.45 + 0.12 * Float((x / 40 + y / 40) % 2) + 0.01 * noise.next()
                ir[i] = 0.82 + 0.004 * noise.next()
            }
        }
        // 속이 고르게 막힌 반지름 10 의 먼지(가장자리 3px 만 옅어진다). 구조요소가 이보다
        // 좁으면 창이 통째로 먼지 안에 들어가 기준선이 먼지 자신이 되고 밀도가 0 이 된다.
        let cx = 600, cy = 600
        for y in (cy - 13)...(cy + 13) {
            for x in (cx - 13)...(cx + 13) {
                let dx = Float(x - cx), dy = Float(y - cy)
                let distance = (dx * dx + dy * dy).squareRoot()
                guard distance <= 13 else { continue }
                let transmittance = distance <= 10 ? 0.4 : 0.4 + 0.6 * (distance - 10) / 3
                let i = y * side + x
                ir[i] *= transmittance
                red[i] *= transmittance
            }
        }
        let detection = try InfraredDefectRemoval.detect(
            infrared: ir, red: red, width: side, height: side,
            parameters: InfraredDefectRemoval.Parameters(alignmentSearchRadius: 0)
        ).get()
        // 투과율 0.4 → 진짜 감쇠 0.6. 절반도 못 되돌리면 자국이 그대로 보인다.
        let core = attenuation(detection, x: cx, y: cy)
        XCTAssertGreaterThan(core, 0.45,
                             "먼지 한가운데가 되돌려져야 한다(실제 감쇠 0.60, 잰 값 \(core)).")
        XCTAssertLessThan(core, 0.80, "실제보다 더 지우면 없던 밝은 얼룩이 생긴다.")
    }

    /// 픽셀 하나로는 문턱을 못 넘지만 면적으로는 압도적으로 유의한 결함.
    ///
    /// 문턱은 픽셀 하나의 유의성이라, 옅은 먼지는 한 픽셀도 문턱을 못 넘어 **보정량이 정확히
    /// 0** 이 된다(실측: 컷마다 그런 먼지가 있었다). 같은 유의수준을 면적에 맞게 적용하면
    /// (Σ(밀도−바닥) ≥ mσ√면적) 잡힌다. 깨끗한 필름이 같이 번지지 않는지도 함께 본다.
    func testFaintDustBelowThePerPixelThresholdIsFoundByItsArea() throws {
        var (red, ir) = makeScene(leak: 0.05, noiseSigma: 0.004)
        let cx = 150, cy = 110, radius = 3
        stampSpot(&ir, &red, cx: cx, cy: cy, radius: radius, depth: 0.82 * 0.025)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                                         width: width, height: height,
                                                         parameters: fastParameters).get()
        XCTAssertTrue(corrects(detection, x: cx, y: cy),
                      "옅어도 면적이 있으면 합친 증거가 압도적이다 — 보정돼야 한다.")
        XCTAssertLessThan(detection.coverage, 0.01,
                          "면적 가중을 넣었다고 깨끗한 필름까지 결함이 되면 안 된다.")
    }

    /// 부분 폐색은 도려내는 게 아니라 가려진 만큼 되돌린다.
    func testPartialOcclusionIsRestoredByDivisionRatherThanMasking() throws {
        var (red, ir) = makeScene()
        // 가시광의 약 30% 를 가리는 먼지: 빛이 대부분 남아 있으므로 나눗셈으로 되돌린다.
        let cx = 128, cy = 112, radius = 3
        var expected = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) { expected[i] = red[i] }
        stampSpot(&ir, &red, cx: cx, cy: cy, radius: radius, depth: 0.25)

        let detection = try InfraredDefectRemoval.detect(infrared: ir, red: red,
                                               width: width, height: height,
                                               parameters: fastParameters).get()
        let index = cy * width + cx
        let occluded = red[index]
        XCTAssertLessThan(occluded, expected[index] * 0.85, "픽스처가 실제로 가려야 한다.")

        let a = attenuation(detection, x: cx, y: cy)
        XCTAssertGreaterThan(a, 0.1, "부분 폐색은 감쇠 창에 실려야 한다.")
        let restored = occluded / max(1 - a, 0.5)
        XCTAssertEqual(Double(restored), Double(expected[index]),
                       accuracy: Double(expected[index]) * 0.25,
                       "나눗셈 보정이 결함 이전 값 근처로 되돌려야 한다.")
        // 코어 마스크는 되돌릴 수 없는 완전 폐색 전용 — 부분 폐색은 들어가지 않는다.
        var corePixels = 0
        for cluster in detection.clusters {
            cluster.maskRGBA8.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i] > 8 { corePixels += 1 }
            }
        }
        XCTAssertEqual(corePixels, 0, "부분 폐색은 나눗셈으로 되돌려야 하고 도려내면 안 된다.")
    }

    // MARK: 복원 통합(클러스터 마스크 → SoftwareDefectRemoval.repair)

    func testClusterMaskDrivesRepairThatRemovesSpotAndPreservesRest() throws {
        var (red, ir) = makeScene()
        stampSpot(&ir, &red, cx: 128, cy: 112, radius: 3, depth: 0.4)
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
