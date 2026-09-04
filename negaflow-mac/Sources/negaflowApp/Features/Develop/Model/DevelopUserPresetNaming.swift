import Foundation

/// 사용자 프리셋 이름 규칙입니다. 어느 말로 낼지는 화면이 정하고, 겹치지 않게 하는 규칙만
/// 여기 둡니다.
enum DevelopUserPresetNaming {
    /// 저장할 이름입니다. 비워 두면 `autoName` 이 짓는 번호 이름 중 **비어 있는 첫 번호**를 쓰고,
    /// 적어 준 이름이 이미 있으면 `nil` — 겹치는 이름은 저장하지 않습니다.
    ///
    /// 겹침은 대소문자를 가리지 않습니다. 목록에서 사람이 읽고 고르는 이름이라 "Portra" 와
    /// "portra" 가 나란히 있으면 어느 쪽인지 알 수 없습니다.
    static func resolve(
        requested: String,
        existing: [String],
        autoName: (Int) -> String
    ) -> String? {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            return contains(existing, trimmed) ? nil : trimmed
        }
        // 자동 이름은 1 부터 세어 비어 있는 첫 번호를 씁니다. 개수+1 로 하면 가운데를 지웠을 때
        // 이미 있는 번호와 부딪힙니다.
        var index = 1
        while contains(existing, autoName(index)) {
            index += 1
        }
        return autoName(index)
    }

    private static func contains(_ existing: [String], _ candidate: String) -> Bool {
        existing.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
    }
}
