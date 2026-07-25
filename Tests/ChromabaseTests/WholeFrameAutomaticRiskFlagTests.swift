import XCTest
@testable import Chromabase

/// 자동(전체 프레임) 모드의 후보 밀도 판정은 **경고 전용**이다. 예전에는 밀도가 높으면 검출 결과를
/// 통째로 버렸지만(자동을 사실상 쓸 수 없게 만들었다), 이제는 컴포넌트를 하나도 버리지 않고
/// automaticFalsePositiveRisk 플래그만 세운다 — 제외 판단은 사용자가 한다.
final class WholeFrameAutomaticRiskFlagTests: XCTestCase {
    func testKeepsEveryComponentEvenWhenOneTileIsLocallyDense() {
        let width = 1_024
        let height = 1_024
        let densePixels = (0..<400).map { pixel in
            (pixel / 20) * width + pixel % 20
        }
        let isolatedPixels = [200 * width + 200, 200 * width + 201]
        let field = makeField(
            width: width,
            height: height,
            pixelGroups: [densePixels, isolatedPixels]
        )

        let flagged = SoftwareDefectRemoval.applyingWholeFrameAutomaticRiskFlag(to: field)

        XCTAssertTrue(flagged.automaticFalsePositiveRisk)
        XCTAssertEqual(flagged.components.map(\.id), [0, 1])
        XCTAssertEqual(flagged.componentID(atX: 0, y: 0), 0)
        XCTAssertEqual(flagged.componentID(atX: 200, y: 200), 1)
    }

    func testFlagsDiffuseCandidatesAboveWholeFrameLimitWithoutDropping() {
        let width = 1_200
        let height = 1_200
        let pixels = stride(from: 0, to: width * height, by: 1_400).map { $0 }
        let field = makeField(width: width, height: height, pixelGroups: [pixels])

        let flagged = SoftwareDefectRemoval.applyingWholeFrameAutomaticRiskFlag(to: field)

        XCTAssertTrue(flagged.automaticFalsePositiveRisk)
        XCTAssertEqual(flagged.components.count, 1)
        XCTAssertEqual(flagged.components[0].pixelCount, pixels.count)
        XCTAssertEqual(
            flagged.automaticCandidatePixelFraction ?? 0,
            Double(pixels.count) / Double(width * height),
            accuracy: 0.000_000_1
        )
    }

    func testKeepsSparseCandidatesWithoutRaisingRisk() {
        let width = 1_200
        let height = 1_200
        let pixels = stride(from: 0, to: width * height, by: 4_000).map { $0 }
        let field = makeField(width: width, height: height, pixelGroups: [pixels])

        let flagged = SoftwareDefectRemoval.applyingWholeFrameAutomaticRiskFlag(to: field)

        XCTAssertFalse(flagged.automaticFalsePositiveRisk)
        XCTAssertEqual(flagged.components.count, 1)
        XCTAssertEqual(flagged.automaticCandidatePixelFraction ?? 0, 0.00025, accuracy: 0.000_000_1)
    }

    private func makeField(width: Int, height: Int, pixelGroups: [[Int]]) -> DefectLabelField {
        var labels = [Int32](repeating: -1, count: width * height)
        let components = pixelGroups.enumerated().map { index, pixels in
            let id = Int32(index)
            for pixel in pixels where labels.indices.contains(pixel) {
                labels[pixel] = id
            }
            let xs = pixels.map { $0 % width }
            let ys = pixels.map { $0 / width }
            return DefectComponent(
                id: id,
                kind: .dust,
                pixels: pixels,
                minX: xs.min() ?? 0,
                minY: ys.min() ?? 0,
                maxX: xs.max() ?? 0,
                maxY: ys.max() ?? 0,
                confidence: 0.9
            )
        }
        return DefectLabelField(
            width: width,
            height: height,
            labels: labels,
            components: components
        )
    }
}
