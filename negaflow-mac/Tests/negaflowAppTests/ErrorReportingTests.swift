import XCTest
import Chromabase
@testable import negaflowApp

@MainActor
final class ErrorReportingTests: XCTestCase {

    func testErrorLogRecordsBoundsAndClears() {
        let log = AppErrorLog()
        XCTAssertFalse(log.hasEntries)
        XCTAssertNil(log.latest)

        for index in 0..<40 {
            log.record("문제 \(index)")
        }
        // capacity 30: 오래된 것부터 밀려 최신 30개만 남는다.
        XCTAssertEqual(log.entries.count, 30)
        XCTAssertEqual(log.latest?.message, "문제 39")
        XCTAssertEqual(log.entries.first?.message, "문제 10")

        // 공백만 있는 메시지는 무시한다.
        let before = log.entries.count
        log.record("   \n ")
        XCTAssertEqual(log.entries.count, before)

        log.clear()
        XCTAssertFalse(log.hasEntries)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testReportErrorSetsStatusPhaseAndRecordsToLog() {
        let model = AppModel()
        XCTAssertFalse(model.errorLog.hasEntries)

        model.reportError("이미지 로드 실패: test.svg")

        XCTAssertEqual(model.statusMessage, "이미지 로드 실패: test.svg")
        XCTAssertEqual(model.scanPhase, .error)
        XCTAssertEqual(model.errorLog.latest?.message, "이미지 로드 실패: test.svg")
    }

    /// statusMessage 토스트는 사라져도(facade 갱신) errorLog 는 오류를 유지한다.
    func testErrorLogSurvivesStatusMessageChange() {
        let model = AppModel()
        model.reportError("첫 오류")
        model.statusMessage = "다른 상태 메시지"   // 토스트 갱신/사라짐 시나리오

        XCTAssertEqual(model.statusMessage, "다른 상태 메시지")
        XCTAssertEqual(model.errorLog.latest?.message, "첫 오류")
        XCTAssertTrue(model.errorLog.hasEntries)
    }

    /// 진단 리포트는 스캐너가 없어도 최근 문제와 라이브러리 상태를 종류별로 담는다.
    func testDiagnosticsReportIncludesRecentProblemsWithoutScanner() async {
        let model = AppModel()
        model.reportError("이미지 로드 실패: android-studio-logo.svg")

        await model.runDiagnostics()

        let report = try? XCTUnwrap(model.diagnosticsCenter.report)
        XCTAssertEqual(
            report?.problems.first?.message,
            "이미지 로드 실패: android-studio-logo.svg",
            "진단 리포트 '최근 문제' 섹션에 오류 메시지가 담겨야 한다."
        )
        XCTAssertFalse(
            report?.libraryStats.isEmpty ?? true,
            "진단 리포트에 라이브러리 상태 섹션이 있어야 한다."
        )
        XCTAssertFalse(model.diagnosticsCenter.isGenerating)
        // 스캐너가 없으면 scannerAvailable = false.
        XCTAssertFalse(report?.scannerAvailable ?? true)
    }

    /// 오류 기록이 AppModel 전역 무효화로 새지 않는다(관찰 경계 보존).
    func testErrorLogRecordingDoesNotInvalidateAppModel() {
        let model = AppModel()
        var appModelEmissions = 0
        let subscription = model.errorLog.objectWillChange.sink { _ in }
        let modelSubscription = model.objectWillChange.sink { _ in appModelEmissions += 1 }
        defer {
            subscription.cancel()
            modelSubscription.cancel()
        }

        for index in 0..<20 {
            model.errorLog.record("문제 \(index)")
        }

        XCTAssertEqual(model.errorLog.entries.count, 20)
        XCTAssertEqual(appModelEmissions, 0,
                       "errorLog 기록은 전용 스토어라 AppModel 을 무효화하면 안 된다.")
    }
}
