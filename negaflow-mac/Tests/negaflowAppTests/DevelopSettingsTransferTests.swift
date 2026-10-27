import XCTest
@testable import Chromabase
import ScannerKit
import CoreGraphics
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

    func testScopedPasteReplacesEffectiveLookGroupsWithoutAccumulating() throws {
        let source = makeFrame(index: 1, filmType: .colorNegative)
        source.preset = try XCTUnwrap(PresetRegistry.load(named: "warm-lab"))
        source.params.exposure = 0.4
        source.params.warmth = 0.2
        source.params.sharpness = 0.3
        let copied = source.developSettingsSnapshot
        let sourceEffective = DevelopParameters(preset: copied.preset!, overrides: copied.params)
        for mask in 1...7 {
            let target = makeFrame(index: 2, filmType: .colorNegative)
            target.preset = try XCTUnwrap(PresetRegistry.load(named: "deep-slide"))
            target.params.exposure = -0.2
            target.params.warmth = -0.3
            target.params.grain = 0.5
            let before = DevelopParameters(preset: target.preset!, overrides: target.params)
            let scope = DevelopSettingsPasteScope(base: false, tone: mask & 1 != 0,
                color: mask & 2 != 0, detail: mask & 4 != 0, geometry: false)
            let expected = scope.applying(source: sourceEffective, to: before)
            for _ in 0..<3 {
                target.applyDevelopSettingsSnapshot(copied, scope: scope)
                let actual = target.preset.map { DevelopParameters(preset: $0, overrides: target.params) } ?? target.params
                XCTAssertEqual(actual, expected, "mask=\(mask)")
            }
        }
    }

    func testBasePasteClearsThePreviousChannelCalibrationWhenSourceHasNone() {
        let source = makeFrame(index: 1, filmType: .colorNegative)
        let target = makeFrame(index: 2, filmType: .colorNegative)
        target.params.channelRange = SIMD3(0.8, 1, 1.25)
        target.applyDevelopSettingsSnapshot(source.developSettingsSnapshot,
            scope: DevelopSettingsPasteScope(base: true, tone: false, color: false,
                detail: false, geometry: false, inputGamma: false, baseScale: false))
        XCTAssertNil(target.params.channelRange)
    }

    func testDefaultPasteUsesThePanelScopeAndEndsSnapshotComparison() {
        let model = AppModel()
        let source = makeFrame(index: 1, filmType: .colorNegative)
        let target = makeFrame(index: 2, filmType: .colorNegative)
        model.frames = [source, target]
        defer { model.frames = [] }
        model.selectedFrameID = target.id
        source.params.exposure = 0.7
        source.params.warmth = 0.4
        target.params.exposure = -0.2
        target.params.warmth = -0.3
        let snapshot = target.makeDevelopSnapshot(name: "Before")
        model.copyDevelopSettings(from: source)
        model.toggleSnapshotCompare(snapshot, for: target)
        model.developSettingsPasteScope = DevelopSettingsPasteScope(base: false, tone: true,
            color: false, detail: false, geometry: false)
        model.pasteDevelopSettings(to: target)
        XCTAssertNil(model.snapshotCompareState)
        XCTAssertEqual(target.params.exposure, 0.7)
        XCTAssertEqual(target.params.warmth, -0.3)
        XCTAssertNil(model.restoreSnapshotCompareState())
        XCTAssertEqual(target.params.exposure, 0.7)
    }

    func testBulkPasteRefreshesTheRenderedPreviewAndThumbnail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("preset-pixels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("negative.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 480, height: 320, to: sourceURL)
        let model = AppModel(libraryCatalogURL: root.appendingPathComponent("library.json"),
            libraryDefectDirectoryURL: root.appendingPathComponent("defects"),
            libraryBackupDirectoryURL: root.appendingPathComponent("backups"))
        await model.restoreLibraryOnLaunch()
        let frames = (1...3).map { ScanFrame(scanIndex: $0, rawScanURL: sourceURL,
            filmType: .colorNegative, sourceKind: .scannerTIFF) }
        model.frames = frames
        defer { model.frames = [] }
        XCTAssertTrue(model.assignNewPersistentFrames(frames))
        model.activeWorkspaceModule = .develop
        model.updateInteractionScope(frames.map(\.id))
        model.selectedFrameID = frames[1].id
        model.selectedFrameIDs = [frames[1].id, frames[2].id]
        for frame in frames { frame.rangeShapeAttempted = true }
        frames[0].params.exposure = 0.8
        frames[0].params.warmth = 0.25
        for frame in frames.dropFirst() {
            frame.params.exposure = -0.5
            frame.params.warmth = -0.4
            frame.imageTransform = ImageTransform(rotation: .deg90)
            frame.params.imageTransform = frame.imageTransform
            await model.developFrame(frame)
        }
        let before = frames.dropFirst().map { $0.cachedDevelopedBase?.dataProvider?.data as Data? }
        model.copyDevelopSettings(from: frames[0])
        model.pasteDevelopSettings(to: frames[1])
        await model.sequentialLibraryDevelopmentTask?.value
        for (index, frame) in frames.dropFirst().enumerated() {
            XCTAssertEqual(frame.params, frames[0].params)
            let image = try XCTUnwrap(frame.cachedDevelopedBase)
            XCTAssertNotEqual(image.dataProvider?.data as Data?, before[index])
            XCTAssertNotNil(frame.thumbnailImage)
            let key = FilmBaseCacheKey(filmType: frame.filmType, mode: .auto,
                manualBaseRGB: nil, filmStockDminID: nil)
            var fresh = model.makeSnapshot(for: frame, baseKey: key, needsRawPreview: false,
                needsNeutralPreview: false, needsDebugPreviews: false, needsThumbnail: true,
                proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension)
            fresh.cachedSceneMeasurements = DevelopSceneMeasurements()
            let expected = try DevelopFrameRenderer.render(fresh)
            XCTAssertEqual(image.dataProvider?.data as Data?, expected.developedBase.dataProvider?.data as Data?)
        }
        model.performUndo()
        await model.sequentialLibraryDevelopmentTask?.value
        for (index, frame) in frames.dropFirst().enumerated() {
            XCTAssertEqual(frame.params.exposure, -0.5)
            XCTAssertEqual(frame.imageTransform.rotation, .deg90)
            XCTAssertEqual(frame.cachedDevelopedBase?.dataProvider?.data as Data?, before[index])
        }
        model.performRedo()
        await model.sequentialLibraryDevelopmentTask?.value
        for frame in frames.dropFirst() { XCTAssertEqual(frame.params, frames[0].params) }
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
