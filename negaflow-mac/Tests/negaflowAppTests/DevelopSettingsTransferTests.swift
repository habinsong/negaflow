import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class DevelopSettingsTransferTests: XCTestCase {
    func testInputPasteAndUserPresetAreDistinctUndoStepsAcrossSelection() throws {
        let model = AppModel()
        let source = makeFrame(index: 1, filmType: .colorNegative)
        let first = makeFrame(index: 2, filmType: .colorNegative)
        let second = makeFrame(index: 3, filmType: .colorNegative)
        source.params.inputGamma = try .power(1.8)
        source.params.baseScale = try FilmBaseScale(0.75)
        first.params.inputGamma = try .power(2.4)
        first.params.baseScale = try FilmBaseScale(1.25)
        let beforeFirst = first.params, beforeSecond = second.params
        model.frames = [source, first, second]
        defer { model.frames = [] }
        model.selectedFrameID = first.id; model.selectedFrameIDs = [first.id, second.id]
        model.copyDevelopSettings(from: source)
        let scope = DevelopSettingsPasteScope(base: false, tone: false, color: false, detail: false,
            geometry: false, inputGamma: true, baseScale: true)
        model.pasteDevelopSettings(to: first, scope: scope)
        for frame in [first, second] {
            XCTAssertEqual(frame.params.inputGamma.value, 1.8)
            XCTAssertEqual(frame.params.baseScale.value, 0.75)
        }
        model.performUndo()
        XCTAssertEqual(first.params, beforeFirst); XCTAssertEqual(second.params, beforeSecond)
        model.performRedo()
        XCTAssertEqual(first.params.inputGamma.value, 1.8); XCTAssertEqual(second.params.baseScale.value, 0.75)
        source.params.inputGamma = try .power(1.6)
        source.params.baseScale = try FilmBaseScale(1.1)
        let preset = source.makeUserDevelopPreset(name: "입력 프리셋")
        let restored = try JSONDecoder().decode(DevelopUserPreset.self, from: JSONEncoder().encode(preset))
        model.applyUserDevelopPreset(restored, to: first)
        XCTAssertEqual(first.params.inputGamma.value, 1.6); XCTAssertEqual(second.params.baseScale.value, 1.1)
        model.performUndo()
        XCTAssertEqual(first.params.inputGamma.value, 1.8); XCTAssertEqual(second.params.baseScale.value, 0.75)
        model.performRedo()
        XCTAssertEqual(first.params.inputGamma.value, 1.6); XCTAssertEqual(second.params.baseScale.value, 1.1)
    }

    func testFullDevelopPasteWithInputFlagsOffKeepsDestinationInput() throws {
        let source = makeFrame(index: 1, filmType: .colorNegative)
        let target = makeFrame(index: 2, filmType: .colorNegative)
        source.params.inputGamma = try .power(1.8); source.params.baseScale = try FilmBaseScale(0.75)
        source.params.exposure = 0.4
        target.params.inputGamma = try .power(2.4); target.params.baseScale = try FilmBaseScale(1.25)
        var scope = DevelopSettingsPasteScope.all
        scope.inputGamma = false; scope.baseScale = false
        target.applyDevelopSettingsSnapshot(source.developSettingsSnapshot, scope: scope)
        XCTAssertEqual(target.params.inputGamma.value, 2.4)
        XCTAssertEqual(target.params.baseScale.value, 1.25)
        XCTAssertEqual(target.params.exposure, 0.4)
    }

    func testFullCopyPasteAppliesProcessTargetAndGeometryToSelectedFrames() {
        let model = AppModel()
        let source = makeFrame(index: 1, filmType: .colorPositive)
        let first = makeFrame(index: 2, filmType: .colorNegative)
        let second = makeFrame(index: 3, filmType: .bwNegative)
        let transform = ImageTransform(
            rotation: .deg90,
            flipHorizontal: true,
            flipVertical: true,
            cropRect: SIMD4(0.12, 0.18, 0.64, 0.72),
            straightenAngle: 2.4,
            cropAspect: 4.0 / 5.0
        )
        source.updateParams {
            $0.filmType = .colorPositive
            $0.isDigitalSource = true
            $0.developTarget = .sp3000
            $0.exposure = 0.42
            $0.imageTransform = transform
        }
        source.imageTransform = transform
        model.frames = [source, first, second]
        model.copyDevelopSettings(from: source)
        model.selectedFrameID = first.id
        model.selectedFrameIDs = [first.id, second.id]

        model.pasteDevelopSettings(to: first)

        for frame in [first, second] {
            XCTAssertEqual(frame.filmType, .colorPositive)
            XCTAssertEqual(frame.params.isDigitalSource, true)
            XCTAssertEqual(frame.params.developTarget, .sp3000)
            XCTAssertEqual(frame.params.exposure, 0.42, accuracy: 1e-9)
            XCTAssertEqual(frame.imageTransform, transform)
            XCTAssertEqual(frame.params.imageTransform, transform)
        }
    }

    func testGeometryOnlyPasteKeepsDevelopSettingsAndCopiesCompleteTransform() {
        let source = makeFrame(index: 1, filmType: .colorNegative)
        let destination = makeFrame(index: 2, filmType: .bwNegative)
        let transform = ImageTransform(
            rotation: .deg270,
            flipVertical: true,
            cropRect: SIMD4(0.08, 0.14, 0.75, 0.68),
            straightenAngle: -1.75,
            cropAspect: 3.0 / 2.0
        )
        source.imageTransform = transform
        source.updateParams {
            $0.filmType = .colorNegative
            $0.developTarget = .noritsu
            $0.exposure = 0.5
            $0.imageTransform = transform
        }
        destination.updateParams {
            $0.filmType = .bwNegative
            $0.developTarget = .main
            $0.exposure = -0.25
        }

        destination.applyDevelopSettingsSnapshot(
            source.developSettingsSnapshot,
            scope: DevelopSettingsPasteScope(
                base: false,
                tone: false,
                color: false,
                detail: false,
                geometry: true
            )
        )

        XCTAssertEqual(destination.filmType, .bwNegative)
        XCTAssertEqual(destination.params.developTarget, .main)
        XCTAssertEqual(destination.params.exposure, -0.25, accuracy: 1e-9)
        XCTAssertEqual(destination.imageTransform, transform)
        XCTAssertEqual(destination.params.imageTransform, transform)
    }

    func testUserPresetAppliesCompleteEditStateToSelectedFrames() {
        let model = AppModel()
        let source = makeFrame(index: 1, filmType: .bwPositive)
        let first = makeFrame(index: 2, filmType: .colorNegative)
        let second = makeFrame(index: 3, filmType: .colorPositive)
        let transform = ImageTransform(
            rotation: .deg180,
            flipHorizontal: true,
            cropRect: SIMD4(0.2, 0.1, 0.6, 0.8),
            straightenAngle: 3.25,
            cropAspect: 1
        )
        source.updateParams {
            $0.filmType = .bwPositive
            $0.isDigitalSource = nil
            $0.developTarget = .hr
            $0.contrast = 0.31
            $0.imageTransform = transform
        }
        source.imageTransform = transform
        let preset = source.makeUserDevelopPreset(name: "Full edit")
        model.frames = [source, first, second]
        model.selectedFrameID = first.id
        model.selectedFrameIDs = [first.id, second.id]

        model.applyUserDevelopPreset(preset, to: first)

        for frame in [first, second] {
            XCTAssertEqual(frame.filmType, .bwPositive)
            XCTAssertEqual(frame.params.developTarget, .hr)
            XCTAssertEqual(frame.params.contrast, 0.31, accuracy: 1e-9)
            XCTAssertEqual(frame.imageTransform, transform)
            XCTAssertEqual(frame.params.imageTransform, transform)
        }
    }

    func testLegacyPasteScopeDefaultsGeometryToIncluded() throws {
        let data = Data(#"{"base":true,"tone":true,"color":true,"detail":true}"#.utf8)
        let scope = try JSONDecoder().decode(DevelopSettingsPasteScope.self, from: data)

        XCTAssertTrue(scope.geometry)
        XCTAssertTrue(scope.isFullDevelopScope)
    }

    private func makeFrame(index: Int, filmType: FilmType) -> ScanFrame {
        ScanFrame(
            scanIndex: index,
            rawScanURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("develop-transfer-\(UUID().uuidString).tif"),
            filmType: filmType
        )
    }
}
