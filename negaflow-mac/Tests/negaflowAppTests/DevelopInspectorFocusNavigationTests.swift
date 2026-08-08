import XCTest
@testable import negaflowApp

final class DevelopInspectorFocusNavigationTests: XCTestCase {
    func testVisibleSliderOrderForToneCurveAndColorPanels() {
        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: .tone,
                showNoiseReductionStrength: false
            ),
            [.exposure, .contrast, .highlight, .shadow, .whites, .blacks, .density]
        )
        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: .curve,
                showNoiseReductionStrength: false
            ),
            [.curveHighlights, .curveLights, .curveDarks, .curveShadows]
        )
        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: .color,
                showNoiseReductionStrength: false
            ),
            [.warmth, .tint, .vibrance, .saturation, .colorDepth]
        )
    }

    func testVisibleSliderOrderForDetailHidesNoiseReductionWhenStrengthIsHidden() {
        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: .detail,
                showNoiseReductionStrength: false
            ),
            [.grain, .sharpness, .clarity, .halation, .vignette]
        )
    }

    func testVisibleSliderOrderForDetailShowsNoiseReductionFirstWhenStrengthIsVisible() {
        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: .detail,
                showNoiseReductionStrength: true
            ),
            [
                .noiseReduction, .noiseReductionLuma, .noiseReductionChroma,
                .noiseReductionDarkTone, .noiseReductionDetail, .noiseReductionGrainProtect,
                .grain, .sharpness, .clarity, .halation, .vignette,
            ]
        )
    }

    func testVisibleSliderOrderForEmptyPanels() {
        for panel in [
            InspectorPanel.colorMixer,
            .colorGrading,
            .bwToning,
            .calibration,
            .debug
        ] {
            XCTAssertEqual(
                DevelopInspectorFocusNavigation.visibleSliderOrder(
                    expandedPanel: panel,
                    showNoiseReductionStrength: true
                ),
                []
            )
        }

        XCTAssertEqual(
            DevelopInspectorFocusNavigation.visibleSliderOrder(
                expandedPanel: nil,
                showNoiseReductionStrength: true
            ),
            []
        )
    }

    func testNextFocusedSliderWrapsForward() {
        let order: [InspectorSliderFocus] = [.exposure, .contrast, .density]

        XCTAssertEqual(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .density,
                order: order,
                reverse: false
            ),
            .exposure
        )
    }

    func testNextFocusedSliderMovesForwardWithoutWrapping() {
        let order: [InspectorSliderFocus] = [.exposure, .contrast, .density]

        XCTAssertEqual(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .exposure,
                order: order,
                reverse: false
            ),
            .contrast
        )
    }

    func testNextFocusedSliderWrapsReverse() {
        let order: [InspectorSliderFocus] = [.exposure, .contrast, .density]

        XCTAssertEqual(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .exposure,
                order: order,
                reverse: true
            ),
            .density
        )
    }

    func testNextFocusedSliderMovesReverseWithoutWrapping() {
        let order: [InspectorSliderFocus] = [.exposure, .contrast, .density]

        XCTAssertEqual(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .density,
                order: order,
                reverse: true
            ),
            .contrast
        )
    }

    func testNextFocusedSliderIgnoresNilCurrent() {
        XCTAssertNil(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: nil,
                order: [.exposure, .contrast],
                reverse: false
            )
        )
    }

    func testNextFocusedSliderIgnoresEmptyOrder() {
        XCTAssertNil(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .exposure,
                order: [],
                reverse: false
            )
        )
    }

    func testNextFocusedSliderIgnoresCurrentNotPresentInOrder() {
        XCTAssertNil(
            DevelopInspectorFocusNavigation.nextFocusedSlider(
                current: .density,
                order: [.exposure, .contrast],
                reverse: false
            )
        )
    }
}
