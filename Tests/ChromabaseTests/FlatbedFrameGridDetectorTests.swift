import CoreGraphics
import XCTest
@testable import Chromabase

/// 합성 홀더로 검출기를 검증한다. 실제 스캔을 쓰지 않는 이유는 기대값을 픽셀 단위로 알 수
/// 없기 때문이다 — 여기서는 프레임 위치를 우리가 정해 놓고 그대로 되찾는지 본다.
final class FlatbedFrameGridDetectorTests: XCTestCase {

    /// 홀더 한 장을 만든다. 홀더 마스크는 불투명(0), 프레임 사이 여백은 필름 베이스(밝음),
    /// 컷 안은 임의 밝기로 채운다.
    private func makeHolder(
        slotCount: Int,
        framesPerSlot: Int,
        frameLengthMM: Double = 36,
        frameWidthMM: Double = 24,
        gapMM: Double = 2,
        slotPitchMM: Double = 52,
        leadingMM: Double = 18,
        physical: CGSize = CGSize(width: 149.86, height: 246.38),
        pixelsPerMM: Double = 8,
        gapIsBright: Bool = true,
        frameFill: (Int, Int) -> Double = { _, _ in 0.45 }
    ) -> FlatbedFrameGridDetector.Preview {
        // 실제 스캔에는 늘 미세한 잡음이 있다. 완전히 균일한 합성은 행 표준편차가 부동소수
        // 오차만 남아 균일도 판정이 의미를 잃으므로, 결정적인 잡음을 얹어 현실에 맞춘다.
        func noise(_ x: Int, _ y: Int) -> Double {
            let hashed = (x &* 73_856_093) ^ (y &* 19_349_663)
            return Double(hashed & 0xFF) / 255 * 0.02 - 0.01
        }
        let width = Int(physical.width * pixelsPerMM)
        let height = Int(physical.height * pixelsPerMM)
        var luminance = [Double](repeating: 0.02, count: width * height)  // 홀더 마스크
        let gapValue = gapIsBright ? 0.92 : 0.03

        for slot in 0..<slotCount {
            let rawX0 = Int((leadingMM + Double(slot) * slotPitchMM) * pixelsPerMM)
            let x0 = max(0, rawX0)
            let x1 = min(width, rawX0 + Int(frameWidthMM * pixelsPerMM))
            guard x0 < x1 else { continue }
            // 스트립 전체를 필름 베이스로 깔고 그 위에 컷을 얹는다.
            let stripTop = max(0, Int(leadingMM * pixelsPerMM))
            let stripBottom = min(
                height,
                stripTop + Int(Double(framesPerSlot) * (frameLengthMM + gapMM) * pixelsPerMM)
            )
            for y in stripTop..<stripBottom {
                for x in x0..<x1 { luminance[y * width + x] = gapValue + noise(x, y) }
            }
            for frame in 0..<framesPerSlot {
                let top = stripTop + Int(Double(frame) * (frameLengthMM + gapMM) * pixelsPerMM)
                let bottom = min(height, top + Int(frameLengthMM * pixelsPerMM))
                guard top < bottom else { continue }
                let fill = frameFill(slot, frame)
                for y in top..<bottom {
                    for x in x0..<x1 { luminance[y * width + x] = fill + noise(x, y) }
                }
            }
        }
        return FlatbedFrameGridDetector.Preview(
            luminance: luminance,
            width: width,
            height: height,
            physicalSize: physical
        )
    }

    private func sizesMM(
        _ detections: [FlatbedFrameDetection],
        physical: CGSize
    ) -> [(width: Double, height: Double)] {
        detections.map {
            (
                $0.normalizedRect.width * physical.width,
                $0.normalizedRect.height * physical.height
            )
        }
    }

    func testFindsEveryFrameOnAFullHolder() {
        let preview = makeHolder(slotCount: 2, framesPerSlot: 6)
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
        for size in sizesMM(found, physical: preview.physicalSize) {
            XCTAssertEqual(size.width, 24, accuracy: 1.5)
            XCTAssertEqual(size.height, 36, accuracy: 1.5)
        }
    }

    /// 홀더가 스캔 영역보다 넓으면 양끝 슬롯이 잘린다. 잘린 조각을 프레임으로 내보내면 본
    /// 스캔이 엉뚱한 데를 찍으므로, 폭이 규격에 못 미치는 슬롯은 버려야 한다.
    func testDropsSlotsClippedByTheScanArea() {
        // 첫 슬롯이 왼쪽 경계에 걸치도록 앞쪽 여백을 음수로 민다.
        let preview = makeHolder(
            slotCount: 3,
            framesPerSlot: 3,
            leadingMM: -14
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .fullFrame35mm
        )
        let rows = Set(found.map(\.row))
        XCTAssertEqual(rows.count, 2, "잘린 슬롯이 결과에 남았습니다")
        for size in sizesMM(found, physical: preview.physicalSize) {
            XCTAssertEqual(size.width, 24, accuracy: 1.5)
        }
    }

    /// 과노광된 컷은 홀더만큼 어둡다. 그 컷에서 스트립이 끊어진 것으로 보면 격자가 조각마다
    /// 따로 서서 컷이 통째로 누락된다(실제 스캔에서 12개 중 6개까지 떨어졌다).
    func testKeepsStripIntactAcrossAnOpaqueFrame() {
        let preview = makeHolder(slotCount: 2, framesPerSlot: 6) { _, frame in
            frame == 2 ? 0.02 : 0.45
        }
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
    }

    /// 미노광 컷은 여백과 밝기가 같다. 경계를 하나씩 믿으면 이 컷을 여백으로 먹어버린다.
    func testKeepsUnexposedFrameThatLooksLikeGap() {
        let preview = makeHolder(slotCount: 2, framesPerSlot: 6) { _, frame in
            frame == 3 ? 0.92 : 0.45
        }
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
    }

    /// 슬라이드는 프레임 사이가 최대 밀도라 검게 나온다. 네거티브와 부호가 반대다.
    func testHandlesSlideFilmWhereGapsAreDark() {
        let preview = makeHolder(
            slotCount: 2,
            framesPerSlot: 6,
            gapIsBright: false,
            frameFill: { _, _ in 0.55 }
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .fullFrame35mm
        )
        XCTAssertEqual(found.count, 12)
    }

    func testFindsMediumFormatFrames() {
        let preview = makeHolder(
            slotCount: 1,
            framesPerSlot: 4,
            frameLengthMM: 56,
            frameWidthMM: 56,
            gapMM: 4,
            slotPitchMM: 70,
            leadingMM: 4
        )
        let found = FlatbedFrameGridDetector.detect(
            preview: preview,
            frameFormat: .medium66
        )
        XCTAssertEqual(found.count, 4)
        for size in sizesMM(found, physical: preview.physicalSize) {
            XCTAssertEqual(size.width, 56, accuracy: 2.5)
            XCTAssertEqual(size.height, 56, accuracy: 2.5)
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
