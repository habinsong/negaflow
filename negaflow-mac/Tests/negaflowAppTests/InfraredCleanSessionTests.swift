import XCTest
import Chromabase
@testable import negaflowApp

final class InfraredCleanSessionTests: XCTestCase {
    /// 판정 기준은 은의 유무다. 컬러는 색소로 화상을 만들어 적외선이 통과하고(네거티브·슬라이드
    /// 모두), 흑백은 은입자라 적외선을 막는다.
    func testInfraredIsAllowedForDyeFilmAndBlockedForSilverFilm() {
        XCTAssertTrue(
            InfraredFilmCompatibility(filmType: .colorNegative).allowsAutomaticCorrection
        )
        XCTAssertTrue(
            InfraredFilmCompatibility(filmType: .colorPositive).allowsAutomaticCorrection
        )
        XCTAssertFalse(
            InfraredFilmCompatibility(filmType: .bwNegative).allowsAutomaticCorrection
        )
        XCTAssertFalse(
            InfraredFilmCompatibility(filmType: .bwPositive).allowsAutomaticCorrection
        )
    }

    func testSilverImageFilmDoesNotStartInfraredCorrection() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame(filmType: .bwNegative)
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

    /// 실기 2400dpi 한 컷의 IR 검출은 26~52초가 걸린다(실측). 그 사이 사용자가 자동/가이드
    /// 검출을 시작하면 둘이 서로의 revision 을 밀어 **양쪽 다 조용히 사라졌다**. 지금은
    /// 사용자가 시작한 도구가 이기고, IR 은 다시 만들 수 있는 상태로 남는다.
    func testManualRegionDetectCancelsInfraredCleanAndLeavesItRetryable() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            _ = model.beginInfraredCleanSession(for: frame)
            frame.infraredAutoCleanAttempted = true

            model.runRegionDetect(frame, displayROI: CGRect(x: 0, y: 0, width: 1, height: 1))

            XCTAssertFalse(
                frame.infraredAutoCleanAttempted,
                "수동 도구에 길을 내준 IR 은 다시 시도할 수 있어야 한다."
            )
            model.cancelRegionDefect(frame)
        }
    }

    /// 경합으로 결과를 버렸으면 다음 방문에서 다시 만들 수 있어야 한다. 표시가 남아 있으면
    /// 그 세션 내내 IR 먼지 제거가 불능이 된다(앱을 다시 켜야만 복구).
    func testDiscardedInfraredResultBecomesRetryable() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let lifecycleRevision = frame.defectDetectRevision
            let session = model.beginInfraredCleanSession(for: frame)
            frame.infraredAutoCleanAttempted = true
            frame.defectDetectRevision += 1   // 그 사이 사용자가 수동 검출을 시작했다

            XCTAssertFalse(model.completeInfraredClean(
                Self.successfulDetection(),
                to: frame,
                session: session,
                frameLifecycleRevision: lifecycleRevision,
                taskWasCancelled: false
            ))
            XCTAssertFalse(frame.infraredAutoCleanAttempted)
        }
    }

    /// "결함 없음"은 확정된 결과다 — 표시를 유지해 그 사진을 볼 때마다 55MP 검출이 다시
    /// 돌지 않게 한다.
    func testStableOutcomeKeepsTheAttemptMarkSoItDoesNotRerunOnEveryVisit() async {
        await MainActor.run {
            let model = AppModel()
            let frame = Self.makeFrame()
            model.frames = [frame]
            let session = model.beginInfraredCleanSession(for: frame)
            frame.infraredAutoCleanAttempted = true

            XCTAssertTrue(model.completeInfraredClean(
                .failure(.noDefects),
                to: frame,
                session: session,
                frameLifecycleRevision: frame.defectDetectRevision,
                taskWasCancelled: false
            ))
            XCTAssertTrue(frame.infraredAutoCleanAttempted)
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
