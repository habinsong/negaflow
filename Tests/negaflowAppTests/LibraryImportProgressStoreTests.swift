import XCTest
@testable import negaflowApp

@MainActor
final class LibraryImportProgressStoreTests: XCTestCase {
    func testReportsReadingProgressWithoutGoingBackwards() {
        let store = LibraryImportProgressStore()
        let id = store.begin(totalCount: 10)

        store.update(id: id, completedCount: 4)
        store.update(id: id, completedCount: 2)

        XCTAssertEqual(store.phase, .reading)
        XCTAssertEqual(store.progress?.completedCount, 4)
        XCTAssertEqual(store.progress?.totalCount, 10)
        XCTAssertEqual(store.progress?.percent, 40)
    }

    /// iCloud 원본 내려받기는 대상 수가 가져오기 전체 수와 다르다. 단계가 바뀌면 모수와
    /// 카운트를 새로 세야 진행률이 100%에 붙어 버리지 않는다.
    func testDownloadPhaseTracksItsOwnTotalAndHandsBackToReading() {
        let store = LibraryImportProgressStore()
        let id = store.begin(totalCount: 20)

        store.update(id: id, completedCount: 0, totalCount: 3, phase: .downloading)
        store.update(id: id, completedCount: 2, totalCount: 3, phase: .downloading)

        XCTAssertEqual(store.phase, .downloading)
        XCTAssertEqual(store.progress?.completedCount, 2)
        XCTAssertEqual(store.progress?.totalCount, 3)

        store.update(id: id, completedCount: 0, totalCount: 20, phase: .reading)

        XCTAssertEqual(store.phase, .reading)
        XCTAssertEqual(store.progress?.completedCount, 0)
        XCTAssertEqual(store.progress?.totalCount, 20)
    }

    func testStaleIdentifierNeverMovesProgress() {
        let store = LibraryImportProgressStore()
        let stale = store.begin(totalCount: 5)
        let current = store.begin(totalCount: 8)

        store.update(id: stale, completedCount: 5)

        XCTAssertEqual(store.progress?.completedCount, 0)
        XCTAssertEqual(store.progress?.totalCount, 8)

        store.finish(id: current)

        XCTAssertEqual(store.progress?.completedCount, 8)
    }
}
