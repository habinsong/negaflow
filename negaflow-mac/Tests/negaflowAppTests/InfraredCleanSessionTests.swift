import XCTest
import Chromabase
@testable import negaflowApp

final class InfraredCleanSessionTests: XCTestCase {
    func testAutomaticFilmCompatibilityFailsClosedWithoutMaterialMetadata() {
        XCTAssertTrue(
            InfraredFilmCompatibility(filmType: .colorNegative).allowsAutomaticCorrection
        )
        XCTAssertFalse(
            InfraredFilmCompatibility(filmType: .colorPositive).allowsAutomaticCorrection
        )
        XCTAssertFalse(
            InfraredFilmCompatibility(filmType: .bwNegative).allowsAutomaticCorrection
        )
        XCTAssertFalse(
            InfraredFilmCompatibility(filmType: .bwPositive).allowsAutomaticCorrection
        )
    }

    func testUnverifiedPositiveFilmDoesNotStartInfraredCorrection() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame(filmType: .colorPositive)
            model.frames = [frame]

            model.runInfraredClean(frame)

            XCTAssertEqual(model.statusMessage, model.infraredText(.unverifiedFilm))
            XCTAssertTrue(frame.defectEdits.isEmpty)
        }
    }

    func testRemovedFrameRejectsLateSuccessfulDetection() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let lifecycleRevision = frame.defectDetectRevision
            let session = model.beginInfraredCleanSession(for: frame)
            let outcome = Self.successfulDetection()
            guard case .success = outcome else {
                return XCTFail("회귀 테스트용 IR 검출 결과가 성공이어야 합니다: \(outcome)")
            }

            model.frames = []
            model.statusMessage = "unchanged"

            XCTAssertFalse(model.completeInfraredClean(
                outcome,
                to: frame,
                session: session,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertTrue(frame.defectEdits.isEmpty)
            XCTAssertEqual(model.statusMessage, "unchanged")
        }
    }

    func testNewRunInvalidatesPreviousResultAndAcceptsOnlyLatestSession() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let lifecycleRevision = frame.defectDetectRevision
            let previous = model.beginInfraredCleanSession(for: frame)
            let latest = model.beginInfraredCleanSession(for: frame)
            model.statusMessage = "unchanged"

            XCTAssertFalse(model.completeInfraredClean(
                .failure(.noDefects),
                to: frame,
                session: previous,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertEqual(model.statusMessage, "unchanged")

            XCTAssertTrue(model.completeInfraredClean(
                .failure(.noDefects),
                to: frame,
                session: latest,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertEqual(model.statusMessage, model.text(AppLocalizedPhrase.infraredCleanNoDefectsStatus))
        }
    }

    func testExplicitCancellationRejectsLateSuccessfulDetection() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let lifecycleRevision = frame.defectDetectRevision
            let session = model.beginInfraredCleanSession(for: frame)
            let outcome = Self.successfulDetection()
            model.cancelInfraredClean(frame)
            model.statusMessage = "unchanged"

            XCTAssertFalse(model.completeInfraredClean(
                outcome,
                to: frame,
                session: session,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertTrue(frame.defectEdits.isEmpty)
            XCTAssertEqual(model.statusMessage, "unchanged")
        }
    }

    func testFrameLifecycleRevisionRejectsLateResult() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let lifecycleRevision = frame.defectDetectRevision
            let session = model.beginInfraredCleanSession(for: frame)
            frame.defectDetectRevision += 1
            model.statusMessage = "unchanged"

            XCTAssertFalse(model.completeInfraredClean(
                .failure(.noDefects),
                to: frame,
                session: session,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertEqual(model.statusMessage, "unchanged")
        }
    }

    @MainActor
    private static func makeFrame(filmType: FilmType = .colorNegative) -> ScanFrame {
        ScanFrame(
            scanIndex: 1,
            rawScanURL: URL(fileURLWithPath: "/tmp/negaflow-ir-session-\(UUID().uuidString).tiff"),
            filmType: filmType,
            infraredScanURL: URL(fileURLWithPath: "/tmp/negaflow-ir-session-\(UUID().uuidString)-ir.tiff")
        )
    }

    private static func successfulDetection() -> Result<InfraredDefectRemoval.Detection, InfraredDefectRemoval.Failure> {
        let width = 96
        let height = 96
        // 사진에 결이 있어야 "이 봉우리가 잡음보다 높은가"를 잴 표본이 생긴다 — 완전 균일한
        // 평면은 정합 판정 자체가 성립하지 않는다.
        var red = [Float](repeating: 0, count: width * height)
        var infrared = [Float](repeating: 0.82, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                red[y * width + x] = 0.5 + 0.1 * Float((x / 8 + y / 8) % 2)
            }
        }
        // 먼지는 파장에 무관하게 같은 비율로 빛을 막는다. IR 에만 찍은 결함은 물리적으로
        // 존재할 수 없고, 파이프라인이 사진에서 확인되지 않는 후보를 기각하므로 검출되지 않는다.
        let transmittance: Float = 0.05 / 0.82
        for y in 44...50 {
            for x in 44...50 {
                infrared[y * width + x] *= transmittance
                red[y * width + x] *= transmittance
            }
        }
        return InfraredDefectRemoval.detect(
            infrared: infrared,
            red: red,
            width: width,
            height: height,
            parameters: InfraredDefectRemoval.Parameters(
                sensitivity: 0.5,
                dilateRadius: 1,
                minArea: 2,
                maxCoverage: 0.1,
                alignmentSearchRadius: 0,
                clusterTile: 64,
                clusterPadding: 8
            )
        )
    }
}
