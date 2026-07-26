import XCTest
@testable import negaflowApp

// GrainMend 미세 입자 기본값 — 설정에서 정하고 앱을 다시 켜도 유지되어야 한다.
// 어디까지나 새 프레임의 시작값이라, 프레임별 체크박스를 대신하거나 강제하지 않는다.
final class DefectDetectionDefaultsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "negaflow.defect-defaults.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsToEnabledWhenNeverSet() {
        XCTAssertTrue(DefectDetectionDefaults.microSpecks(defaults: defaults),
                      "설정한 적이 없으면 기존 동작대로 켜져 있어야 한다")
    }

    func testStoredFalseIsHonoured() {
        defaults.set(false, forKey: DefectDetectionDefaults.microSpecksKey)
        XCTAssertFalse(DefectDetectionDefaults.microSpecks(defaults: defaults))
    }

    func testStoredTrueIsHonoured() {
        defaults.set(true, forKey: DefectDetectionDefaults.microSpecksKey)
        XCTAssertTrue(DefectDetectionDefaults.microSpecks(defaults: defaults))
    }

    // MARK: 저장소 왕복 — 앱을 다시 켠 상황

    @MainActor
    func testStoreWritesAndReloadsAcrossLaunches() throws {
        let store = PresentationPreferencesStore(defaults: defaults)
        XCTAssertTrue(store.defaultDefectMicroSpecks)

        store.defaultDefectMicroSpecks = false

        // 새 인스턴스 = 앱 재시작.
        let reloaded = PresentationPreferencesStore(defaults: defaults)
        XCTAssertFalse(reloaded.defaultDefectMicroSpecks,
                       "설정한 기본값은 앱을 다시 켜도 남아 있어야 한다")
    }
}
