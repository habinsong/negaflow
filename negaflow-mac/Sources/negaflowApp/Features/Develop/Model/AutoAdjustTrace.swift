import Foundation
import OSLog

/// 자동 톤 / 자동 화이트 밸런스가 **어디서 호출됐고 어디서 멈췄는지** 남긴다.
///
/// 두 동작은 실패해도 조용하다 — 가드에서 `return` 만 하므로 화면에는 아무 일도 일어나지
/// 않은 것처럼 보인다. "버튼은 되는데 단축키는 안 된다" 같은 신고를 추측 없이 가르려면
/// 호출 경로와 중단 지점이 로그에 남아야 한다.
///
/// 읽는 법:
/// ```
/// log show --last 5m --predicate 'subsystem == "com.songhabin.negaflow" && category == "autoadjust"' --info
/// ```
enum AutoAdjustTrace {
    /// 호출 경로. 같은 함수를 인스펙터 버튼과 메뉴/단축키가 함께 부른다.
    enum Source: String {
        case inspectorButton
        case menuCommand
    }

    /// 중단 지점. 각 가드가 자기 이름으로 기록한다.
    enum Stop: String {
        case shortcutActionDisabled
        case noActionableFrame
        case cleanedRawUnavailable
        case frameNotOwned
        case paramsChangedBeforeRender
        case renderOrStatsFailed
        case paramsChangedAfterRender
        case cleanRawRevisionChanged
        case defectIdentityChanged
    }

    private static let logger = Logger(
        subsystem: AppDiagnostics.subsystem,
        category: "autoadjust"
    )

    static func began(_ operation: String, source: Source, frameID: UUID?) {
        logger.info(
            "\(operation, privacy: .public) begin source=\(source.rawValue, privacy: .public) frame=\(frameID?.uuidString ?? "nil", privacy: .public)"
        )
    }

    static func stopped(_ operation: String, source: Source, at stop: Stop) {
        logger.error(
            "\(operation, privacy: .public) stop source=\(source.rawValue, privacy: .public) reason=\(stop.rawValue, privacy: .public)"
        )
    }

    /// 선택 상태 — 메뉴 활성 계산(`canPerformWorkflowShortcutAction`)이 읽는 값 그대로.
    static func selection(selected: UUID?, scopeCount: Int, actionable: Bool) {
        logger.info(
            "selection selected=\(selected?.uuidString ?? "nil", privacy: .public) scope=\(scopeCount, privacy: .public) actionableFrame=\(actionable, privacy: .public)"
        )
    }

    static func applied(_ operation: String, source: Source, values: String) {
        logger.info(
            "\(operation, privacy: .public) applied source=\(source.rawValue, privacy: .public) \(values, privacy: .public)"
        )
    }
}
