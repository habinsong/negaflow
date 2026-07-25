import Combine
import Foundation

/// 최근 사용자 표시 오류의 전용 기록소.
///
/// statusMessage 토스트는 3초 뒤 사라지지만, 상태바 빨간 점과 진단 리포트는 "무엇이 왜
/// 실패했는지"를 나중에도 보여줘야 한다. 그 지속 상태를 여기에 담는다. 전용 ObservableObject 라
/// 오류 기록이 AppModel 전역 무효화를 일으키지 않는다(관찰 경계 원칙 [[appmodel-observation-boundary]]).
@MainActor
final class AppErrorLog: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let date: Date
    }

    /// 오래된 것부터 최신 순. 상한을 두어 무한 성장하지 않는다.
    @Published private(set) var entries: [Entry] = []
    private let capacity = 30

    var latest: Entry? { entries.last }
    var hasEntries: Bool { !entries.isEmpty }

    func record(_ message: String, at date: Date = Date()) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.append(Entry(message: trimmed, date: date))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func clear() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
    }
}
