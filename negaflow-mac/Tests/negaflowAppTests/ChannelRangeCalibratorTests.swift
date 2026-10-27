import Foundation
import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class ChannelRangeCalibratorTests: XCTestCase {
    private let shape = SIMD3(0.86, 0.97, 1.2)

    private func member(
        shape: SIMD3<Double>? = nil, stamped: SIMD3<Double>? = nil, contributes: Bool = true
    ) -> ChannelRangeCalibrator.Member {
        .init(shape: shape, stamped: stamped, contributesShape: contributes)
    }

    // MARK: 묶음 규칙

    func testGroupPrefersPhysicalRollOverFolderAndSeparatesCaptureSources() {
        let roll = UUID()
        let inRoll = ChannelRangeCalibrator.group(rollID: roll, sourceFolder: "/scans/a", source: .scannerTIFF)
        let sameRollOtherFolder = ChannelRangeCalibrator.group(
            rollID: roll, sourceFolder: "/scans/b", source: .scannerTIFF)
        XCTAssertEqual(inRoll, sameRollOtherFolder)
        let folderA = ChannelRangeCalibrator.group(rollID: nil, sourceFolder: "/scans/a", source: .scannerTIFF)
        let folderB = ChannelRangeCalibrator.group(rollID: nil, sourceFolder: "/scans/b", source: .scannerTIFF)
        XCTAssertNotEqual(folderA, folderB)
        XCTAssertNotEqual(folderA, inRoll)
        let imported = ChannelRangeCalibrator.group(rollID: nil, sourceFolder: "/scans/a", source: .importedFile)
        XCTAssertNotEqual(folderA, imported, "스캐너 TIFF 와 가져온 파일은 센서 경로가 달라 섞지 않는다")
    }

    // MARK: 교정값 결정

    func testResolveNeedsThreeMeasuredFramesAndIgnoresVirtualCopies() throws {
        XCTAssertNil(ChannelRangeCalibrator.resolve([member(shape: shape), member(shape: shape)]))
        XCTAssertNil(ChannelRangeCalibrator.resolve([
            member(shape: shape), member(shape: shape), member(shape: shape, contributes: false),
        ]), "가상 사본은 같은 사진을 두 번 세는 표본이라 세지 않는다")
        let resolved = try XCTUnwrap(ChannelRangeCalibrator.resolve([
            member(shape: shape), member(shape: shape), member(shape: shape), member(),
        ]))
        XCTAssertEqual(resolved.x * resolved.y * resolved.z, 1.0, accuracy: 1e-9)
    }

    func testResolveFollowsStampedValueSoLaterSamplesDoNotMoveThePicture() {
        let stamped = SIMD3(0.9, 1.0, 1.0 / 0.9)
        let resolved = ChannelRangeCalibrator.resolve([
            member(stamped: stamped), member(stamped: stamped),
            member(shape: SIMD3(0.7, 1.0, 1.43)), member(shape: SIMD3(0.7, 1.0, 1.43)),
            member(shape: SIMD3(0.7, 1.0, 1.43)), member(shape: SIMD3(0.7, 1.0, 1.43)),
        ])
        XCTAssertEqual(resolved, stamped)
    }

    func testResolveTieBetweenStampedValuesKeepsTheEarlierOne() {
        let first = SIMD3(0.9, 1.0, 1.0 / 0.9), second = SIMD3(0.8, 1.0, 1.25)
        XCTAssertEqual(ChannelRangeCalibrator.resolve([member(stamped: first), member(stamped: second)]), first)
        XCTAssertEqual(ChannelRangeCalibrator.resolve([
            member(stamped: second), member(stamped: first), member(stamped: first),
        ]), first)
    }

    // MARK: 묶음에 찍기(AppModel)

    private func colorFrame(_ index: Int, folder: String, shape: SIMD3<Double>?, autoBalance: Bool = false) -> ScanFrame {
        let frame = ScanFrame(scanIndex: index,
                              rawScanURL: URL(fileURLWithPath: "/tmp/\(folder)/frame_\(index).tif"),
                              filmType: .colorNegative)
        frame.rangeShape = shape.flatMap(ChannelRangeCalibration.sanitized)
        frame.updateParams { $0.autoBalance = autoBalance }
        frame.establishLibraryWorkflowBaselineIfNeeded()
        return frame
    }

    func testCalibrationStampsOnlyTheSameFolderAndOnlyOnceEnoughFramesAreMeasured() throws {
        let model = AppModel()
        let blue = SIMD3(0.80, 0.97, 1.29)
        let a = (1...3).map { colorFrame($0, folder: "rollA", shape: blue) }
        let unmeasuredSibling = colorFrame(4, folder: "rollA", shape: nil)
        let other = (5...7).map { colorFrame($0, folder: "rollB", shape: SIMD3(1.0, 1.0, 1.0)) }
        model.frames = a + [unmeasuredSibling] + other

        // 표본 둘일 때(셋째가 아직 안 잼) 찍지 않는다.
        a[2].rangeShape = nil
        model.calibrateChannelRange(around: a[0])
        XCTAssertTrue(model.frames.allSatisfy { $0.params.channelRange == nil })

        a[2].rangeShape = ChannelRangeCalibration.sanitized(blue)
        model.calibrateChannelRange(around: a[0])
        let expected = try XCTUnwrap(ChannelRangeCalibration.combine([blue, blue, blue]))
        for frame in a + [unmeasuredSibling] {
            XCTAssertEqual(frame.params.channelRange, expected, "같은 폴더 구성원은 측정 여부와 무관하게 같은 값을 받는다")
        }
        // 다른 폴더(스캔 묶음)는 건드리지 않는다.
        XCTAssertTrue(other.allSatisfy { $0.params.channelRange == nil })
        model.calibrateChannelRange(around: other[0])
        XCTAssertEqual(other.map(\.params.channelRange), Array(repeating: ChannelRangeCalibration.combine(
            Array(repeating: SIMD3(1.0, 1.0, 1.0), count: 3)), count: 3))
    }

    func testCalibrationIsFrozenAfterStampingAndRespectsPhysicalRolls() throws {
        let model = AppModel()
        let blue = SIMD3(0.80, 0.97, 1.29)
        let frames = (1...4).map { colorFrame($0, folder: "mixed\($0 % 2)", shape: blue) }
        model.frames = frames
        // 폴더가 둘로 갈려 각각 표본이 둘뿐이면 찍히지 않는다.
        model.calibrateChannelRange(around: frames[0])
        XCTAssertTrue(frames.allSatisfy { $0.params.channelRange == nil })

        // 같은 물리 롤에 묶으면 폴더와 무관하게 한 묶음이 된다.
        let roll = try XCTUnwrap(LibraryRoll.physical(
            name: "Roll", filmType: .colorNegative, frameIDs: frames.map(\.id)))
        model.rollStore.replace(with: RollStoreSnapshot(rolls: [roll], activeRollID: nil))
        frames[0].rangeCalibrationSettled = false
        model.calibrateChannelRange(around: frames[0])
        let stamped = try XCTUnwrap(frames[0].params.channelRange)
        XCTAssertTrue(frames.allSatisfy { $0.params.channelRange == stamped })

        // 찍힌 뒤 표본이 크게 달라져도 그림이 움직이지 않는다.
        for frame in frames { frame.rangeShape = ChannelRangeCalibration.sanitized(SIMD3(1.2, 1.0, 0.83)) }
        frames[1].rangeCalibrationSettled = false
        model.calibrateChannelRange(around: frames[1])
        XCTAssertTrue(frames.allSatisfy { $0.params.channelRange == stamped })
    }

    func testStampingOnlyMarksOffFramesForRedevelopment() throws {
        let model = AppModel()
        let blue = SIMD3(0.80, 0.97, 1.29)
        let off = colorFrame(1, folder: "redo", shape: blue, autoBalance: false)
        let on = colorFrame(2, folder: "redo", shape: blue, autoBalance: true)
        let third = colorFrame(3, folder: "redo", shape: blue, autoBalance: false)
        for frame in [off, on, third] {
            frame.hasDevelopedOnce = true
            frame.developedIsSettled = true
        }
        model.frames = [off, on, third]
        model.calibrateChannelRange(around: off)
        XCTAssertFalse(off.developedIsSettled, "OFF 프레임은 그림이 달라졌으므로 다음 선택에서 다시 현상한다")
        XCTAssertTrue(on.developedIsSettled, "ON 프레임은 그림이 같으므로 다시 현상할 이유가 없다")
        XCTAssertNotNil(on.params.channelRange, "ON 프레임에도 값은 찍어 둔다(나중에 OFF 로 바꿀 때 바로 쓴다)")
    }

    // MARK: 저장

    func testRangeShapeSurvivesCatalogRecordRoundTripAndBadValuesAreDropped() throws {
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/range-shape.tif"),
                              filmType: .colorNegative)
        frame.rangeShape = ChannelRangeCalibration.sanitized(shape)
        frame.updateParams { $0.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9) }
        let record = LibraryFrameRecord(frame: frame)
        let decoded = try JSONDecoder().decode(
            LibraryFrameRecord.self, from: JSONEncoder().encode(record))
        let restored = decoded.makeFrame(presets: [])
        XCTAssertEqual(restored.rangeShape, frame.rangeShape)
        XCTAssertEqual(restored.params.channelRange, frame.params.channelRange)

        var tampered = record
        tampered.rangeShapeRGB = [9.0, 1.0, 0.1]
        XCTAssertNil(tampered.makeFrame(presets: []).rangeShape, "허용 범위 밖 측정은 읽을 때 버린다")
        tampered.rangeShapeRGB = [1.0, 1.0]
        XCTAssertNil(tampered.makeFrame(presets: []).rangeShape)
    }

    // MARK: 편집 상태와 지문

    func testStampingOnAnUneditedFrameDoesNotMakeItEdited() throws {
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/stamp.tif"),
                              filmType: .colorNegative)
        frame.updateParams { $0.autoBalance = false }
        frame.establishLibraryWorkflowBaselineIfNeeded()
        let before = frame.currentLibraryDevelopRecipeSHA256()
        frame.updateParams { $0.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9) }

        // 기준점을 옮기지 않으면 찍기만 해도 "편집됨" 으로 분류된다 — 이 시험이 막는 오류다.
        let untouched = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        let reconciledWithout = try XCTUnwrap(
            untouched.reconciled(currentRecipeSHA256: try XCTUnwrap(frame.currentLibraryDevelopRecipeSHA256())))
        XCTAssertNotEqual(reconciledWithout.userEditTracking.ingestRecipeSHA256,
                          reconciledWithout.userEditTracking.currentRecipeSHA256)

        frame.rebaseUserEditTracking(afterNonUserChangeFrom: before)
        let state = try XCTUnwrap(frame.libraryWorkflowTrackingState)
        let sha = try XCTUnwrap(frame.currentLibraryDevelopRecipeSHA256())
        XCTAssertEqual(state.userEditTracking.ingestRecipeSHA256, sha)
        XCTAssertEqual(state.userEditTracking.currentRecipeSHA256, sha)
        XCTAssertEqual(state.reconciled(currentRecipeSHA256: sha), state)
    }

    func testStampingOnAnEditedFrameKeepsItEdited() throws {
        let frame = ScanFrame(scanIndex: 1, rawScanURL: URL(fileURLWithPath: "/tmp/stamp-edited.tif"),
                              filmType: .colorNegative)
        frame.updateParams { $0.autoBalance = false }
        frame.establishLibraryWorkflowBaselineIfNeeded()
        let ingest = try XCTUnwrap(frame.libraryWorkflowTrackingState?.userEditTracking.ingestRecipeSHA256)
        frame.updateParams { $0.exposure = 0.5 }
        let editedSHA = try XCTUnwrap(frame.currentLibraryDevelopRecipeSHA256())
        frame.libraryWorkflowTrackingState = try XCTUnwrap(
            frame.libraryWorkflowTrackingState?.reconciled(currentRecipeSHA256: editedSHA))

        frame.updateParams { $0.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9) }
        frame.rebaseUserEditTracking(afterNonUserChangeFrom: editedSHA)
        let tracking = try XCTUnwrap(frame.libraryWorkflowTrackingState?.userEditTracking)
        XCTAssertEqual(tracking.ingestRecipeSHA256, ingest, "손댄 프레임의 가져온 때 기준점은 그대로다")
        XCTAssertEqual(tracking.currentRecipeSHA256, frame.currentLibraryDevelopRecipeSHA256())
        XCTAssertNotEqual(tracking.ingestRecipeSHA256, tracking.currentRecipeSHA256)
    }

    func testRecipeFingerprintIgnoresChannelRangeOnlyWhileAutoBalanceIsOn() throws {
        var params = DevelopParameters()
        params.filmType = .colorNegative
        func sha(_ params: DevelopParameters) throws -> String {
            try LibraryDevelopRecipeFingerprint.sha256(
                filmType: .colorNegative, presetID: nil, params: params, imageTransform: .identity)
        }
        params.autoBalance = true
        let onWithout = try sha(params)
        params.channelRange = SIMD3(0.9, 1.0, 1.0 / 0.9)
        XCTAssertEqual(try sha(params), onWithout, "ON 에서는 교정이 그림을 바꾸지 않으므로 레시피가 같다")
        params.autoBalance = false
        let offWith = try sha(params)
        params.channelRange = nil
        XCTAssertNotEqual(try sha(params), offWith, "OFF 에서는 교정이 그림을 바꾸므로 레시피가 다르다")
    }

    /// 장면이 상한에 닿는 프레임처럼 모양을 못 재는 입력은 다시 재도 같은 답이다. 시도한 사실은 남기고
    /// 렌더마다 같은 측정을 되풀이하지 않는다.
    func testAttemptedMeasurementWithoutShapeIsRememberedAndRetriedOnlyAfterInterpretationChanges() throws {
        let model = AppModel()
        let frame = colorFrame(1, folder: "attempt", shape: nil)
        model.frames = [frame]
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        func result(attempted: Bool) -> DevelopFrameRenderResult {
            DevelopFrameRenderResult(
                base: nil, rawPreview: nil, rawBase: nil, neutralPreview: nil, neutralBase: nil,
                mainPreview: nil, mainBase: nil, developed: image, developedBase: image,
                workingBase: nil, clippingOverlay: nil, clippingOverlayBase: nil,
                destinationGamutOverlay: nil, destinationGamutOverlayBase: nil,
                thumbnailBase: nil, thumbnail: nil, debugPreviews: [], previewRaw: nil,
                sceneMeasurements: DevelopSceneMeasurements(),
                rangeShape: nil, rangeShapeAttempted: attempted)
        }

        model.applyRangeCalibration(result(attempted: false), to: frame)
        XCTAssertFalse(frame.rangeShapeAttempted, "측정을 요청하지 않은 렌더는 시도로 세지 않는다")
        model.applyRangeCalibration(result(attempted: true), to: frame)
        XCTAssertTrue(frame.rangeShapeAttempted)
        XCTAssertNil(frame.rangeShape)

        frame.invalidateInputInterpretation()
        XCTAssertFalse(frame.rangeShapeAttempted, "입력 해석이 바뀌면 모양과 함께 시도 기록도 버린다")
    }
}
