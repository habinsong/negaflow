import XCTest
@testable import Chromabase

final class WholeFrameAutomaticSafetyTests: XCTestCase {
    func testDropsOnlyComponentsTouchingLocallyDenseTile() {
        let width = 1_024
        let height = 1_024
        let densePixels = (0..<100).map { pixel in
            (pixel / 20) * width + pixel % 20
        }
        let isolatedPixels = [200 * width + 200, 200 * width + 201]
        let field = makeField(
            width: width,
            height: height,
            pixelGroups: [densePixels, isolatedPixels]
        )

        let safe = SoftwareDefectRemoval.applyingWholeFrameAutomaticSafety(to: field)

        XCTAssertFalse(safe.automaticSafetySuppressed)
        XCTAssertEqual(safe.components.map(\.id), [1])
        XCTAssertEqual(safe.componentID(atX: 200, y: 200), 1)
        XCTAssertNil(safe.componentID(atX: 0, y: 0))
    }

    func testSuppressesFrameWhenOneTileHasSevereCandidateDensity() {
        let width = 1_024
        let height = 1_024
        let densePixels = (0..<400).map { pixel in
            (pixel / 20) * width + pixel % 20
        }
        let field = makeField(width: width, height: height, pixelGroups: [densePixels])

        let safe = SoftwareDefectRemoval.applyingWholeFrameAutomaticSafety(to: field)

        XCTAssertTrue(safe.automaticSafetySuppressed)
        XCTAssertTrue(safe.components.isEmpty)
    }

    func testSuppressesDiffuseCandidatesAboveWholeFrameLimit() {
        let width = 1_200
        let height = 1_200
        let pixels = stride(from: 0, to: width * height, by: 1_400).map { $0 }
        let field = makeField(width: width, height: height, pixelGroups: [pixels])

        let safe = SoftwareDefectRemoval.applyingWholeFrameAutomaticSafety(to: field)

        XCTAssertTrue(safe.automaticSafetySuppressed)
        XCTAssertTrue(safe.components.isEmpty)
        XCTAssertEqual(
            safe.automaticCandidatePixelFraction ?? 0,
            Double(pixels.count) / Double(width * height),
            accuracy: 0.000_000_1
        )
    }

    func testKeepsSparseCandidatesAndRecordsDensity() {
        let width = 1_200
        let height = 1_200
        let pixels = stride(from: 0, to: width * height, by: 4_000).map { $0 }
        let field = makeField(width: width, height: height, pixelGroups: [pixels])

        let safe = SoftwareDefectRemoval.applyingWholeFrameAutomaticSafety(to: field)

        XCTAssertFalse(safe.automaticSafetySuppressed)
        XCTAssertEqual(safe.components.count, 1)
        XCTAssertEqual(safe.automaticCandidatePixelFraction ?? 0, 0.00025, accuracy: 0.000_000_1)
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
