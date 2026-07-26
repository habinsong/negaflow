import Foundation

// 새 프레임이 시작할 GrainMend 기본값.
//
// 설정 > 일반에서 정하고 UserDefaults 에 남으므로 앱을 다시 켜도 유지된다. 자동과 가이드는 별개
// 도구라 기본값도 따로 기억한다(민감도를 따로 저장하는 것과 같은 계약). 어디까지나 **시작값**일
// 뿐이라 프레임별 체크박스가 그 위에서 자유롭게 켜고 끌 수 있다 — 설정이 개별 프레임의 선택을
// 덮어쓰거나 강제하지 않는다.
enum DefectDetectionDefaults {
    static let autoMicroSpecksKey = "defaultDefectMicroSpecks.auto"
    static let guidedMicroSpecksKey = "defaultDefectMicroSpecks.guided"
    /// 자동/가이드로 나뉘기 전의 단일 설정. 남아 있으면 두 모드의 시작값으로 이어받는다.
    static let legacyMicroSpecksKey = "defaultDefectMicroSpecks"

    /// 자동 모드의 미세 입자 추가 검출 기본값. 미설정이면 true(기존 동작).
    static func autoMicroSpecks(defaults: UserDefaults = .standard) -> Bool {
        microSpecks(forKey: autoMicroSpecksKey, defaults: defaults)
    }

    /// 가이드 모드의 미세 입자 추가 검출 기본값. 미설정이면 true(기존 동작).
    static func guidedMicroSpecks(defaults: UserDefaults = .standard) -> Bool {
        microSpecks(forKey: guidedMicroSpecksKey, defaults: defaults)
    }

    private static func microSpecks(forKey key: String, defaults: UserDefaults) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool { return stored }
        if let legacy = defaults.object(forKey: legacyMicroSpecksKey) as? Bool { return legacy }
        return true
    }
}
