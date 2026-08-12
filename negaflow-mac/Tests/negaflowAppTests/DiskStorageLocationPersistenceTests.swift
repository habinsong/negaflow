import XCTest
@testable import negaflowApp

/// 저장 위치(iCloud / 데스크탑 / 특정 폴더 / 커스텀)는 앱을 껐다 켜도 고른 그대로여야 한다.
@MainActor
final class DiskStorageLocationPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "negaflow.disk-location.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testChosenLocationSurvivesRelaunch() {
        for mode in [DiskStorageLocationMode.iCloud, .desktop, .custom] {
            let store = DiskStorageStore(defaults: defaults)
            store.selectLocationMode(mode)
            let relaunched = DiskStorageStore(defaults: defaults)
            XCTAssertEqual(relaunched.locationMode, mode, "\(mode.rawValue) 선택이 유지돼야 한다.")
        }
    }

    /// 예전에 폴더를 직접 지정한 적이 있으면 그 경로가 그대로 남는다. 그 값이 남아 있다는
    /// 이유만으로 다음 실행에서 "커스텀"으로 되돌아가면 안 된다.
    func testStoredFolderPathsDoNotOverrideTheChosenLocation() {
        defaults.set("/tmp/negaflow-old-root", forKey: "disk.rootFolder")
        defaults.set("/tmp/negaflow-old-quick", forKey: "export.quick.folder")

        let store = DiskStorageStore(defaults: defaults)
        store.selectLocationMode(.iCloud)
        XCTAssertEqual(store.locationMode, .iCloud)

        let relaunched = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(relaunched.locationMode, .iCloud,
                       "남아 있는 경로 때문에 커스텀으로 되돌아가면 안 된다.")
    }

    /// 특정 폴더도 마찬가지다 — 부모 폴더와 모드를 함께 기억한다.
    func testSpecificFolderSelectionSurvivesRelaunch() {
        let store = DiskStorageStore(defaults: defaults)
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-specific-\(UUID().uuidString)", isDirectory: true)
        store.selectSpecificFolder(parent)

        let relaunched = DiskStorageStore(defaults: defaults)
        XCTAssertEqual(relaunched.locationMode, .specificFolder)
        XCTAssertEqual(relaunched.specificFolderPath, parent.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: parent)
    }
}
