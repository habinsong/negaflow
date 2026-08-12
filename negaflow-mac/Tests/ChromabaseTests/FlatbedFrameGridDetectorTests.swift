import CoreGraphics
import XCTest
@testable import Chromabase

/// 합성 홀더로 검출기를 검증한다. 실제 스캔을 쓰지 않는 이유는 기대값을 픽셀 단위로 알 수 없기
/// 때문이다 — 여기서는 프레임 위치를 우리가 정해 놓고 그대로 되찾는지 본다.
///
/// **컷 안에는 그림이 있어야 한다.** 예전 픽스처는 컷을 단색으로 채웠는데, 그러면 컷과 여백을
/// 가르는 유일한 단서인 "그림이 있느냐"가 사라져 실제 필름과 전혀 다른 입력이 된다. 실측
/// 프리뷰에서 무너졌던 경우들(빈 창, 한 슬롯만 채운 홀더, 여백을 가리는 홀더)도 여기서 함께
/// 검증한다.
final class FlatbedFrameGridDetectorTests: XCTestCase {

    private let physical = CGSize(width: 149.86, height: 246.38)
    private let pixelsPerMM = 8.0

    /// 스캐너 잡음. 홀더든 필름이든 어디에나 있다 — 필름만 잡음을 갖게 만들면 질감 판정이
    /// 공짜로 통과해 시험이 되지 않는다.
    private func noise(_ x: Int, _ y: Int) -> Double {
        let hashed = (x &* 73_856_093) ^ (y &* 19_349_663)
        return Double(hashed & 0xFF) / 255 * 0.002 - 0.001
    }

    /// 컷 안의 그림. 가로·세로 양쪽으로 결이 있어야 실제 사진과 같은 신호가 된다.
    ///
    /// 좌표를 **mm 로** 받는 것이 중요하다. 프레임 안의 비율(0...1)로 무늬를 그리면 6×6 처럼
    /// 큰 규격에서 무늬가 늘어나 결이 사라진다 — 실제 필름의 그레인과 디테일은 규격이 커져도
    /// 같은 크기다.
    private func picture(slot: Int, frame: Int, xMM: Double, yMM: Double) -> Double {
        let coarse = sin(xMM * 0.35 + Double(frame)) * cos(yMM * 0.22 + Double(slot))
        let fine = sin(xMM * 2.2 + Double(slot)) * sin(yMM * 1.9 + Double(frame))
        let wash = 0.35 + 0.14 * sin(yMM * 0.08 + Double(frame) * 0.7)
        return min(max(wash + 0.16 * coarse + 0.07 * fine, 0.02), 0.98)
    }

    private struct Holder {
        let preview: FlatbedFrameGridDetector.Preview
        /// 우리가 그려 넣은 컷의 시작 위치(mm). 검출 결과와 대조한다.
        let expectedTopsMM: [[Double]]
        let slotCentersMM: [Double]
    }

    private func makeHolder(
        slotCount: Int,
        framesPerSlot: Int,
        frameLengthMM: Double = 36,
        frameWidthMM: Double = 24,
        gapMM: Double = 2,
        slotPitchMM: Double = 52,
        leadingMM: Double = 18,
        stripTopMM: Double = 18,
        holderFill: Double = 0.02,
        gapFill: Double = 0.92,
        filledSlots: Set<Int>? = nil,
        emptySlotFill: Double = 1.0,
        content: ((Int, Int, Double, Double) -> Double)? = nil
    ) -> Holder {
        let width = Int(physical.width * pixelsPerMM)
        let height = Int(physical.height * pixelsPerMM)
        var luminance = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { luminance[y * width + x] = holderFill + noise(x, y) }
        }

        var expected: [[Double]] = []
        var centers: [Double] = []
        for slot in 0..<slotCount {
            let rawX0 = Int((leadingMM + Double(slot) * slotPitchMM) * pixelsPerMM)
            let x0 = max(0, rawX0)
            let x1 = min(width, rawX0 + Int(frameWidthMM * pixelsPerMM))
            guard x0 < x1 else { continue }
            centers.append(Double(rawX0) / pixelsPerMM + frameWidthMM / 2)

            let isFilled = filledSlots?.contains(slot) ?? true
            let stripTop = max(0, Int(stripTopMM * pixelsPerMM))
            let stripBottom = min(
                height,
                stripTop + Int(Double(framesPerSlot) * (frameLengthMM + gapMM) * pixelsPerMM)
            )
            guard isFilled else {
                // 필름을 끼우지 않은 창 — 광원이 그대로 지나가 균일하게 밝다.
                for y in 0..<height {
                    for x in x0..<x1 {
                        luminance[y * width + x] = emptySlotFill + noise(x, y)
                    }
                }
                expected.append([])
                continue
            }

            for y in stripTop..<stripBottom {
                for x in x0..<x1 { luminance[y * width + x] = gapFill + noise(x, y) }
            }
            var tops: [Double] = []
            for frame in 0..<framesPerSlot {
                let top = stripTop + Int(Double(frame) * (frameLengthMM + gapMM) * pixelsPerMM)
                let bottom = min(height, top + Int(frameLengthMM * pixelsPerMM))
                guard top < bottom else { continue }
                tops.append(Double(top) / pixelsPerMM)
                for y in top..<bottom {
                    let yMM = Double(y - top) / pixelsPerMM
                    for x in x0..<x1 {
                        let xMM = Double(x - x0) / pixelsPerMM
                        let value = content?(slot, frame, xMM, yMM)
                            ?? picture(slot: slot, frame: frame, xMM: xMM, yMM: yMM)
                        luminance[y * width + x] = value + noise(x, y)
                    }
                }
            }
            expected.append(tops)
        }
        return Holder(
            preview: FlatbedFrameGridDetector.Preview(
                luminance: luminance,
                width: width,
                height: height,
                physicalSize: physical
            ),
            expectedTopsMM: expected,
            slotCentersMM: centers
        )
    }

    private func topsMM(
        _ detections: [FlatbedFrameDetection]
    ) -> [Int: [Double]] {
        Dictionary(grouping: detections, by: \.row).mapValues {
            $0.map { $0.normalizedRect.minY * physical.height }.sorted()
        }
    }

    // MARK: - 기본

    func testFindsEveryFrameAtTheRightPlace() {
        let holder = makeHolder(slotCount: 2, framesPerSlot: 6)
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
        let tops = topsMM(found)
        for (row, expected) in holder.expectedTopsMM.enumerated() {
            guard let actual = tops[row] else {
                XCTFail("슬롯 \(row) 를 찾지 못했습니다")
                continue
            }
            XCTAssertEqual(actual.count, expected.count, "슬롯 \(row) 컷 수")
            for (index, value) in zip(actual, expected).enumerated() {
                XCTAssertEqual(
                    value.0,
                    value.1,
                    accuracy: 1.5,
                    "슬롯 \(row) 컷 \(index) 위치"
                )
            }
        }
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.width * physical.width,
                24,
                accuracy: 1.5
            )
            XCTAssertEqual(
                detection.normalizedRect.height * physical.height,
                36,
                accuracy: 1.5
            )
        }
    }

    /// **필름이 없는 홀더에는 아무것도 찾지 않아야 한다.**
    ///
    /// 예전 검출기는 여기서 격자 16개를 신뢰도 1.00 으로 만들어 냈다. 빈 창은 규격에 딱 맞는
    /// 밝은 사각형이라 기하학적으로는 완벽한 프레임처럼 보이기 때문이다.
    func testFindsNothingInAnEmptyHolder() {
        let holder = makeHolder(
            slotCount: 3,
            framesPerSlot: 6,
            filledSlots: []
        )
        XCTAssertTrue(
            FlatbedFrameGridDetector.detect(
                preview: holder.preview,
                frameFormat: .fullFrame35mm
            ).isEmpty
        )
    }

    /// **한 슬롯만 채운 홀더.** 빈 창(밝다)이 필름(어둡다)보다 밝아서, 밝기로 필름을 고르면
    /// 빈 창 두 개를 집고 진짜 필름을 버린다 — 실측에서 실제로 그랬다.
    func testFindsOnlyTheSlotThatHoldsFilm() {
        let holder = makeHolder(
            slotCount: 3,
            framesPerSlot: 6,
            filledSlots: [1]
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 6)
        let center = holder.slotCentersMM[1]
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.midX * physical.width,
                center,
                accuracy: 2
            )
        }
    }

    /// 홀더가 스캔 영역보다 넓으면 양끝 슬롯이 잘린다. 잘린 조각을 프레임으로 내보내면 본
    /// 스캔이 엉뚱한 데를 찍으므로 버려야 한다.
    func testDropsSlotsClippedByTheScanArea() {
        let holder = makeHolder(
            slotCount: 3,
            framesPerSlot: 3,
            leadingMM: -14
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(Set(found.map(\.row)).count, 2, "잘린 슬롯이 결과에 남았습니다")
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.width * physical.width,
                24,
                accuracy: 1.5
            )
        }
    }

    // MARK: - 필름·홀더 변형

    /// 과노광된 컷은 홀더만큼 어둡다. 그 컷에서 스트립이 끊어진 것으로 보면 격자가 조각마다
    /// 따로 서서 컷이 통째로 누락된다.
    func testKeepsStripIntactAcrossAnOpaqueFrame() {
        let holder = makeHolder(slotCount: 2, framesPerSlot: 6) { slot, frame, xMM, yMM in
            frame == 2 ? 0.02 : self.picture(slot: slot, frame: frame, xMM: xMM, yMM: yMM)
        }
        XCTAssertEqual(
            FlatbedFrameGridDetector.detect(
                preview: holder.preview,
                frameFormat: .fullFrame35mm
            ).count,
            12
        )
    }

    /// 미노광 컷은 여백과 밝기가 같다. 경계를 하나씩 믿으면 이 컷을 여백으로 먹어버린다.
    func testKeepsUnexposedFrameThatLooksLikeGap() {
        let holder = makeHolder(slotCount: 2, framesPerSlot: 6) { slot, frame, xMM, yMM in
            frame == 3 ? 0.92 : self.picture(slot: slot, frame: frame, xMM: xMM, yMM: yMM)
        }
        XCTAssertEqual(
            FlatbedFrameGridDetector.detect(
                preview: holder.preview,
                frameFormat: .fullFrame35mm
            ).count,
            12
        )
    }

    /// 슬라이드는 프레임 사이가 최대 밀도라 검게 나온다. 네거티브와 부호가 반대다.
    func testHandlesSlideFilmWhereGapsAreDark() {
        let holder = makeHolder(slotCount: 2, framesPerSlot: 6, gapFill: 0.03)
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
        let tops = topsMM(found)
        for (row, expected) in holder.expectedTopsMM.enumerated() {
            for (actual, target) in zip(tops[row] ?? [], expected) {
                XCTAssertEqual(actual, target, accuracy: 1.5)
            }
        }
    }

    /// 스트립을 끼우면 컷 사이를 마스크가 덮는 홀더가 있다. 여백이 밝은 베이스가 아니라 홀더와
    /// 같은 검은 리브로 보인다.
    func testHandlesHolderThatMasksTheGaps() {
        let holder = makeHolder(slotCount: 2, framesPerSlot: 6, gapFill: 0.02)
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
        let tops = topsMM(found)
        for (row, expected) in holder.expectedTopsMM.enumerated() {
            for (actual, target) in zip(tops[row] ?? [], expected) {
                XCTAssertEqual(actual, target, accuracy: 1.5)
            }
        }
    }

    /// 한 컷의 매끈한 암부가 여백처럼 보여도 그 오차가 회귀선을 끌어 다른 컷까지 함께
    /// 움직이면 안 된다. 실제 바다·하늘 프레임에서 한 경계 오차가 스트립 전체로 번졌다.
    func testOneMisleadingFrameDoesNotShiftTheWholeStrip() {
        let holder = makeHolder(
            slotCount: 1,
            framesPerSlot: 6,
            gapFill: 0.28
        ) { slot, frame, xMM, yMM in
            if frame == 4, yMM < 7 {
                return 0.045
            }
            return self.picture(slot: slot, frame: frame, xMM: xMM, yMM: yMM)
        }
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 6)
        let actual = topsMM(found)[0] ?? []
        XCTAssertEqual(actual.count, holder.expectedTopsMM[0].count)
        for (index, pair) in zip(actual, holder.expectedTopsMM[0]).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: 0.25, "컷 \(index) 위치")
        }
    }

    // MARK: - 규격

    /// 검출기에 컷 수를 넘기지 않고, 실제 물리 길이에 들어간 만큼을 모든 지원 규격에서 찾는다.
    /// 6×17처럼 이 평판 길이에 한 컷만 들어가는 경우는 주기 격자가 없으므로 기존 외곽선 검출
    /// fallback이 담당하며, 앱 통합 포맷 행렬에서 별도로 검증한다.
    func testFindsEverySupportedMultiFrameFormatWithoutAFrameCount() {
        for (caseIndex, format) in FilmFrameFormat.allCases.enumerated() {
            let gapMM = format.is35mm ? 2.0 : 4.0
            let marginMM = 8.0
            let availableMM = physical.height - marginMM * 2
            let frameCount = Int(
                ((availableMM + gapMM) / (format.stripWidthMM + gapMM)).rounded(.down)
            )
            guard frameCount >= 2 else { continue }

            let holder = makeHolder(
                slotCount: 1,
                framesPerSlot: frameCount,
                frameLengthMM: format.stripWidthMM,
                frameWidthMM: format.stripHeightMM,
                gapMM: gapMM,
                slotPitchMM: format.stripHeightMM + 12,
                leadingMM: marginMM,
                stripTopMM: marginMM,
                gapFill: caseIndex.isMultiple(of: 2) ? 0.92 : 0.02
            )
            let found = FlatbedFrameGridDetector.detect(
                preview: holder.preview,
                frameFormat: format
            )
            XCTAssertEqual(found.count, frameCount, format.displayName)
            let actual = topsMM(found)[0] ?? []
            XCTAssertEqual(actual.count, holder.expectedTopsMM[0].count, format.displayName)
            for (position, expected) in zip(actual, holder.expectedTopsMM[0]) {
                XCTAssertEqual(position, expected, accuracy: 2.5, format.displayName)
            }
        }
    }

    func testFindsMediumFormatFrames() {
        let holder = makeHolder(
            slotCount: 1,
            framesPerSlot: 4,
            frameLengthMM: 56,
            frameWidthMM: 56,
            gapMM: 4,
            slotPitchMM: 70,
            leadingMM: 4,
            stripTopMM: 4
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .medium66
        )
        XCTAssertEqual(found.count, 4)
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.width * physical.width,
                56,
                accuracy: 2.5
            )
            XCTAssertEqual(
                detection.normalizedRect.height * physical.height,
                56,
                accuracy: 2.5
            )
        }
    }

    /// 하프프레임은 스트립을 따라가는 길이(18mm)와 폭 방향(24mm)이 뒤집혀 있다. 예전 코드는
    /// 두 축을 min/max 로 골라 슬롯을 18mm 로 찾으려 했다.
    func testFindsHalfFrames() {
        let holder = makeHolder(
            slotCount: 2,
            framesPerSlot: 8,
            frameLengthMM: 18,
            frameWidthMM: 24,
            gapMM: 1.5,
            leadingMM: 20,
            stripTopMM: 20
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .halfFrame35mm
        )
        XCTAssertEqual(found.count, 16)
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.width * physical.width,
                24,
                accuracy: 1.5
            )
            XCTAssertEqual(
                detection.normalizedRect.height * physical.height,
                18,
                accuracy: 1.5
            )
        }
    }

    /// 645 도 두 축이 뒤집힌 규격이다(진행 41.5mm × 폭 56mm).
    func testFindsMedium645Frames() {
        let holder = makeHolder(
            slotCount: 1,
            framesPerSlot: 5,
            frameLengthMM: 41.5,
            frameWidthMM: 56,
            gapMM: 4,
            slotPitchMM: 70,
            leadingMM: 6,
            stripTopMM: 6
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: holder.preview,
            frameFormat: .medium645
        )
        XCTAssertEqual(found.count, 5)
        for detection in found {
            XCTAssertEqual(
                detection.normalizedRect.width * physical.width,
                56,
                accuracy: 2.5
            )
            XCTAssertEqual(
                detection.normalizedRect.height * physical.height,
                41.5,
                accuracy: 2.5
            )
        }
    }

    func testRejectsEmptyOrDegenerateInput() {
        let empty = FlatbedFrameGridDetector.Preview(
            luminance: [],
            width: 0,
            height: 0,
            physicalSize: CGSize(width: 100, height: 100)
        )
        XCTAssertTrue(
            FlatbedFrameGridDetector.detect(preview: empty, frameFormat: .fullFrame35mm).isEmpty
        )

        // 물리 크기를 모르면 규격을 px로 옮길 수 없다.
        let noScale = FlatbedFrameGridDetector.Preview(
            luminance: [Double](repeating: 0.5, count: 64),
            width: 8,
            height: 8,
            physicalSize: .zero
        )
        XCTAssertTrue(
            FlatbedFrameGridDetector.detect(preview: noScale, frameFormat: .fullFrame35mm).isEmpty
        )
    }
}
