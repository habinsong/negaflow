import Foundation

/// 진단 팝오버가 렌더하는 구조화 리포트. 텍스트 덤프 대신 종류별 섹션으로 나눠 담는다.
struct DiagnosticsReport {
    struct Problem: Identifiable {
        let id = UUID()
        let message: String
        let date: Date
    }

    struct FailureEvent: Identifiable {
        let id = UUID()
        let title: String
        let code: String
        let date: Date
    }

    struct Stat: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        var isWarning = false
    }

    var problems: [Problem] = []
    var failureEvents: [FailureEvent] = []
    var libraryStats: [Stat] = []
    var scannerStats: [Stat] = []
    var scannerAvailable = false
    var scannerError: String?
    var generatedAt = Date()
}

/// 진단 리포트 전용 발행 경계. runDiagnostics 는 비동기(스캐너 capability)라, 팝오버가 완성 시점에
/// 갱신되도록 관찰 가능해야 한다. 전용 스토어라 AppModel 전역 무효화를 일으키지 않는다.
@MainActor
final class DiagnosticsCenter: ObservableObject {
    @Published var report: DiagnosticsReport?
    @Published var isGenerating = false
}
