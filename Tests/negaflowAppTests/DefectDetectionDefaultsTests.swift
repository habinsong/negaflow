import XCTest
@testable import negaflowApp

// GrainMend 미세 입자 기본값 — 설정에서 정하고 앱을 다시 켜도 유지되어야 한다.
// 자동과 가이드는 별개 도구라 값을 공유하지 않는다. 어디까지나 새 프레임의 시작값이라,
// 프레임별 체크박스를 대신하거나 강제하지 않는다.
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
        XCTAssertTrue(DefectDetectionDefaults.autoMicroSpecks(defaults: defaults))
        XCTAssertTrue(DefectDetectionDefaults.guidedMicroSpecks(defaults: defaults))
    }

    // MARK: 자동과 가이드는 서로 영향을 주지 않는다

    func testAutoAndGuidedAreIndependent() {
        defaults.set(false, forKey: DefectDetectionDefaults.autoMicroSpecksKey)

        XCTAssertFalse(DefectDetectionDefaults.autoMicroSpecks(defaults: defaults))
        XCTAssertTrue(DefectDetectionDefaults.guidedMicroSpecks(defaults: defaults),
                      "자동을 꺼도 가이드 기본값은 그대로여야 한다")

        defaults.set(false, forKey: DefectDetectionDefaults.guidedMicroSpecksKey)
        defaults.set(true, forKey: DefectDetectionDefaults.autoMicroSpecksKey)

        XCTAssertTrue(DefectDetectionDefaults.autoMicroSpecks(defaults: defaults))
        XCTAssertFalse(DefectDetectionDefaults.guidedMicroSpecks(defaults: defaults))
    }

    // MARK: 모드별로 나뉘기 전 설정을 이어받는다

    func testLegacySingleSettingSeedsBothModes() {
        defaults.set(false, forKey: DefectDetectionDefaults.legacyMicroSpecksKey)

        XCTAssertFalse(DefectDetectionDefaults.autoMicroSpecks(defaults: defaults))
        XCTAssertFalse(DefectDetectionDefaults.guidedMicroSpecks(defaults: defaults))
    }

    func testModeSpecificSettingWinsOverLegacy() {
        defaults.set(false, forKey: DefectDetectionDefaults.legacyMicroSpecksKey)
        defaults.set(true, forKey: DefectDetectionDefaults.guidedMicroSpecksKey)

        XCTAssertFalse(DefectDetectionDefaults.autoMicroSpecks(defaults: defaults))
        XCTAssertTrue(DefectDetectionDefaults.guidedMicroSpecks(defaults: defaults))
    }

    // MARK: 저장소 왕복 — 앱을 다시 켠 상황

    @MainActor
    func testStoreWritesAndReloadsAcrossLaunches() throws {
        let store = PresentationPreferencesStore(defaults: defaults)
        XCTAssertTrue(store.defaultAutoDefectMicroSpecks)
        XCTAssertTrue(store.defaultGuidedDefectMicroSpecks)

        store.defaultAutoDefectMicroSpecks = false

        // 새 인스턴스 = 앱 재시작.
        let reloaded = PresentationPreferencesStore(defaults: defaults)
        XCTAssertFalse(reloaded.defaultAutoDefectMicroSpecks,
                       "설정한 기본값은 앱을 다시 켜도 남아 있어야 한다")
        XCTAssertTrue(reloaded.defaultGuidedDefectMicroSpecks,
                      "가이드는 자동과 따로 저장되어야 한다")
    }
}
