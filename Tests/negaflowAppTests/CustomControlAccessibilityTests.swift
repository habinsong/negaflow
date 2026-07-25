import XCTest
import Chromabase
@testable import negaflowApp

final class CustomControlAccessibilityTests: XCTestCase {
    func testToneCurveKeyboardEditingKeepsPointOrderAndBounds() {
        var points: [CurvePoint] = []
        var selectedIndex: Int?

        ToneCurvePointEditing.ensureSelection(points: &points, selectedIndex: &selectedIndex)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(selectedIndex, 1)

        ToneCurvePointEditing.nudge(
            points: &points,
            selectedIndex: &selectedIndex,
            direction: .left,
            step: 1
        )
        XCTAssertEqual(points[1].x, 0.01, accuracy: 0.0001)
        ToneCurvePointEditing.nudge(
            points: &points,
            selectedIndex: &selectedIndex,
            direction: .up,
            step: 1
        )
        XCTAssertEqual(points[1].y, 1, accuracy: 0.0001)
    }

    func testToneCurveAddAndDeleteOperateOnInternalPoint() {
        var points = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
        var selectedIndex: Int?

        ToneCurvePointEditing.addPoint(points: &points, selectedIndex: &selectedIndex)
        XCTAssertEqual(points.map(\.x), [0, 0.5, 1])
        XCTAssertEqual(selectedIndex, 1)

        ToneCurvePointEditing.deleteSelected(points: &points, selectedIndex: &selectedIndex)
        XCTAssertEqual(points.map(\.x), [0, 1])
    }

    func testCropKeyboardEditingClampsAndPreservesAspectRatio() {
        let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        let moved = CropAccessibilityEditing.move(rect, dx: -1, dy: 1)
        XCTAssertEqual(moved.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(moved.maxY, 1, accuracy: 0.0001)

        let resized = CropAccessibilityEditing.resize(rect, scaleDelta: 0.5)
        XCTAssertEqual(resized.width / resized.height, 2, accuracy: 0.0001)
        XCTAssertEqual(resized.midX, rect.midX, accuracy: 0.0001)
        XCTAssertEqual(resized.midY, rect.midY, accuracy: 0.0001)
    }

    func testFilmstripHeightKeyboardAdjustmentUsesProductBounds() {
        XCTAssertEqual(FilmstripSizing.clampedHeight(80, minimum: 112, maximum: 340), 112)
        XCTAssertEqual(FilmstripSizing.clampedHeight(400, minimum: 112, maximum: 340), 340)
        XCTAssertEqual(FilmstripSizing.clampedHeight(200, minimum: 112, maximum: 340), 200)
    }

    @MainActor
    func testHistogramAccessibilityAdjustmentUsesRegionLimits() {
        let frame = ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/a.tiff"),
            filmType: .colorNegative
        )
        HistogramToneRegion.exposure.apply(to: frame, value: 99)
        HistogramToneRegion.shadow.apply(to: frame, value: -99)

        XCTAssertEqual(frame.params.exposure, 2)
        XCTAssertEqual(frame.params.shadow, -1)
    }

    func testAccessibilityStringsExistForEverySupportedLanguage() {
        let keys: [AppAccessibilityPhrase] = [
            .input, .output, .curvePointValueFormat, .previousPoint, .nextPoint,
            .addPoint, .deletePoint, .previousRegion, .nextRegion, .moveLeft,
            .moveRight, .moveUp, .moveDown, .cropValueFormat, .filmstripHeightValueFormat,
            .selected, .notSelected, .on, .off, .active, .inactive, .select,
            .activate, .deactivate, .turnOn, .turnOff
        ]
        for language in AppLanguage.allCases where language != .system {
            for key in keys {
                XCTAssertFalse(AppLocalization.accessibilityText(key, language: language).isEmpty)
            }
        }
    }
}
