import Foundation

// 새 프레임이 시작할 GrainMend 기본값.
//
// 설정 > 일반에서 정하고 UserDefaults 에 남으므로 앱을 다시 켜도 유지된다. 어디까지나 **시작값**일
// 뿐이라 프레임별 체크박스가 그 위에서 자유롭게 켜고 끌 수 있다 — 설정이 개별 프레임의 선택을
// 덮어쓰거나 강제하지 않는다.
enum DefectDetectionDefaults {
    static let microSpecksKey = "defaultDefectMicroSpecks"

    /// 미세 입자 추가 검출 기본값. 미설정이면 true(기존 동작).
    static func microSpecks(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: microSpecksKey) as? Bool ?? true
    }
}
