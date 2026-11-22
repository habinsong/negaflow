import XCTest
@testable import Chromabase

/// 포지티브 스캐너 타깃의 실측 상대 시그니처와 기본 그레이드.
///
/// 맥은 포지티브 + 스캐너 타깃 + 사용자가 고른 스캐너 프로파일이면 같은 스캐너의 컬러 슬라이드 프로파일
/// 쌍(롤 라벨 출처가 맞는 것만)에서 상대 시그니처를 만들고, 그것이 있을 때만 `PositiveDevelop.applyBaseGrade`
/// 를 건다. 번들 슬라이드 프로파일은 어느 쌍도 롤 라벨 출처가 맞지 않아 시그니처가 만들어지지 않는다
/// (2026-11-22 확인: NORITSU Ektachrome 100·100D 대 SP-3000 Ektachrome 100D 모두
/// `hasMatchedRollLabelProvenance` false). 그래서 맥도 이 조합에서 상대 차분과 기본 그레이드를 걸지 않고,
/// 상대 차분이 네거티브 전용인 윈도우(`apply_scanner_target_grade`)와 그림이 같다.
///
/// 번들에 짝이 생기면 이 시험이 실패한다. 그때 윈도우에 포지티브 상대 표(`scanner_target_profile.cpp`)와
/// 기본 그레이드를 이식해야 두 앱이 같은 그림을 낸다.
final class ScannerTargetPositiveSignatureTests: XCTestCase {
    func testBundledCorpusHasNoPositiveRelativeSignature() {
        let profiles = ScannerProfileRegistry.loadAll()
        XCTAssertFalse(profiles.isEmpty, "the bundled scanner profiles load")
        for scanner in ["NORITSU", "SP-3000"] {
            XCTAssertTrue(
                ScannerTargetGrade.matchedProfilePairs(scanner: scanner, kind: "color slide", profiles: profiles).isEmpty,
                "\(scanner) has no roll-label matched color-slide pair")
        }
        for target in [DevelopTarget.noritsu, .sp3000] {
            for film in [FilmType.colorPositive, .bwPositive] {
                var params = DevelopParameters()
                params.filmType = film
                params.developTarget = target
                params.scannerProfileID = "noritsu__color-slide__kodak-ektachrome-100d"
                XCTAssertNil(
                    ScannerTargetGrade.resolveSignature(target: target, params: params),
                    "\(target) \(film): no positive relative signature, so no base grade either")
            }
        }
    }
}
