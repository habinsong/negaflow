import XCTest
@testable import negaflowApp

// 내보내기 Finder 버튼이 여는 폴더 선택 검증.
//
// 사진은 루트가 아니라 `<루트>/<날짜>/<출처 폴더>` 에 저장된다. 루트만 열면 사용자가 두 단계를 더
// 들어가야 하므로, 실제로 존재하는 가장 구체적인 폴더를 고르되 폴더를 새로 만들지는 않는다.
final class ExportRevealLocatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow-reveal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ components: String...) throws -> URL {
        var url = root!
        for component in components { url = url.appendingPathComponent(component, isDirectory: true) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ yyyyMMdd: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.calendar = .current
        formatter.timeZone = .current
        return formatter.date(from: yyyyMMdd)!
    }

    // MARK: 오늘 폴더가 있으면 그곳

    func testPrefersTodayDestinationFolder() throws {
        let today = try makeFolder("20260726", "무제 필름")
        _ = try makeFolder("20260725", "무제 필름")

        let resolved = ExportRevealLocator.folder(
            root: root, group: "무제 필름", date: date("20260726")
        )
        XCTAssertEqual(resolved.standardizedFileURL, today.standardizedFileURL)
    }

    // MARK: 오늘 폴더가 없으면 같은 출처의 가장 최근 날짜

    func testFallsBackToMostRecentDateForSameGroup() throws {
        _ = try makeFolder("20260710", "무제 필름")
        let newer = try makeFolder("20260725", "무제 필름")

        let resolved = ExportRevealLocator.folder(
            root: root, group: "무제 필름", date: date("20260726")
        )
        XCTAssertEqual(resolved.standardizedFileURL, newer.standardizedFileURL,
                       "오늘 폴더가 없으면 같은 출처로 내보낸 가장 최근 날짜를 열어야 한다")
    }

    // MARK: 다른 출처 폴더만 있으면 그건 고르지 않는다

    func testIgnoresOtherGroups() throws {
        _ = try makeFolder("20260725", "다른 롤")

        let resolved = ExportRevealLocator.folder(
            root: root, group: "무제 필름", date: date("20260726")
        )
        XCTAssertEqual(resolved.standardizedFileURL, root.standardizedFileURL,
                       "출처가 다르면 그 폴더를 열지 않고 루트로 물러난다")
    }

    // MARK: 한 번도 내보내지 않았으면 루트 — 폴더를 만들지 않는다

    func testNeverExportedFallsBackToRootWithoutCreating() {
        let resolved = ExportRevealLocator.folder(
            root: root, group: "무제 필름", date: date("20260726")
        )
        XCTAssertEqual(resolved.standardizedFileURL, root.standardizedFileURL)
        let dateFolder = root.appendingPathComponent("20260726", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dateFolder.path),
                       "Finder 로 보여주는 동작이 빈 날짜 폴더를 만들어서는 안 된다")
    }

    // MARK: 루트조차 없으면 존재하는 가장 가까운 상위

    func testMissingRootWalksUpToExistingParent() {
        let missing = root.appendingPathComponent("없는폴더/더없는폴더", isDirectory: true)
        let resolved = ExportRevealLocator.folder(
            root: missing, group: nil, date: date("20260726")
        )
        XCTAssertEqual(resolved.standardizedFileURL, root.standardizedFileURL,
                       "루트가 없어도 Finder 창이 뜨도록 존재하는 상위로 내려가야 한다")
    }

    // MARK: 출처 이름이 없으면 기본 그룹

    func testNilGroupUsesDefaultImportGroup() throws {
        let fallback = try makeFolder("20260726", FrameStorageNaming.defaultImportGroup)

        let resolved = ExportRevealLocator.folder(root: root, group: nil, date: date("20260726"))
        XCTAssertEqual(resolved.standardizedFileURL, fallback.standardizedFileURL)
    }
}
