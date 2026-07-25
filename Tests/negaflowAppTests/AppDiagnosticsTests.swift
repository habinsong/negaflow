import Foundation
import XCTest
@testable import negaflowApp

final class AppDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AppDiagnostics.clearForTesting()
    }

    func testTraceCorrelatesBeginErrorAndEndWithoutPrivateErrorText() throws {
        let trace = AppDiagnostics.start(.exportFrame, category: .export)
        let secret = "/Users/private/Family Roll 01.tiff"
        trace.recordError(NSError(
            domain: secret,
            code: 28,
            userInfo: [NSLocalizedDescriptionKey: secret]
        ))
        trace.finish()

        let events = AppDiagnostics.recentEvents
        XCTAssertEqual(events.map(\.phase), [.begin, .error, .end])
        XCTAssertEqual(Set(events.map(\.operationID)), [trace.operationID])
        XCTAssertEqual(Set(events.map(\.category)), [.export])
        XCTAssertEqual(Set(events.map(\.operation)), [.exportFrame])
        let encoded = String(data: try JSONEncoder().encode(events), encoding: .utf8)
        XCTAssertFalse(try XCTUnwrap(encoded).contains(secret))
        XCTAssertFalse(try XCTUnwrap(encoded).contains("Family_Roll"))
    }

    func testFailureEndsIntervalOnceAndSanitizesMachineCode() {
        let trace = AppDiagnostics.start(.catalogSave, category: .catalog)
        trace.fail(code: "write failed / user/path")
        trace.finish()

        let events = AppDiagnostics.recentEvents
        XCTAssertEqual(events.map(\.phase), [.begin, .error])
        XCTAssertEqual(events.last?.code, "write_failed___user_path")
    }

    func testBoundedEventStoreRetainsNewestEvents() {
        let store = AppDiagnosticEventStore(capacity: 2)
        for index in 0..<3 {
            store.append(AppDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                operationID: UUID(),
                category: .develop,
                operation: .developFrame,
                phase: .event,
                severity: .info,
                code: "event_\(index)"
            ))
        }

        XCTAssertEqual(store.snapshot().map(\.code), ["event_1", "event_2"])
    }

    @MainActor
    func testImportEntryPointEmitsCorrelatedOperationWithoutFileName() throws {
        let model = AppModel()
        let privateName = "private-family-roll.never-supported"
        model.importImages(urls: [URL(fileURLWithPath: "/Users/me/\(privateName)")])

        let events = AppDiagnostics.recentEvents
        XCTAssertEqual(events.map(\.phase), [.begin, .end])
        XCTAssertEqual(Set(events.map(\.category)), [.import])
        let encoded = try XCTUnwrap(String(
            data: JSONEncoder().encode(events),
            encoding: .utf8
        ))
        XCTAssertFalse(encoded.contains(privateName))
    }

    func testRequiredDiagnosticCategoriesRemainStable() {
        XCTAssertEqual(
            Set(AppDiagnosticCategory.allCases),
            [.import, .develop, .defects, .export, .catalog]
        )
    }
}
