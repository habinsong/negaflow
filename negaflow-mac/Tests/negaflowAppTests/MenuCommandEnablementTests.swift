import XCTest
@testable import negaflowApp

/// 메뉴 커맨드는 `.disabled(!canPerformWorkflowShortcutAction(...))` 로 잠그면 안 된다.
///
/// Commands 트리가 다시 평가되지 않아 앱 시작 시점의 값이 굳고, 그러면 macOS 가 키
/// 이퀴벌런트를 배달하지 않는다(실측: 사진을 골라 `actionableFrame=true` 인데도 ⌘U 가
/// 액션에 도달하지 못했다). 활성 판정은 실행 시점의 `performWorkflowShortcutAction` 이
/// 담당한다.
@MainActor
final class MenuCommandEnablementTests: XCTestCase {

    func testMenuCommandsDoNotGateOnStaleEnablement() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // negaflowAppTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // negaflow-mac
            .appendingPathComponent("Sources/negaflowApp/App", isDirectory: true)

        for name in ["AppWorkflowMenuCommands.swift", "AppStandardMenuCommands.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(
                source.contains(".disabled(!model.canPerformWorkflowShortcutAction"),
                """
                \(name) 이 메뉴 항목을 stale 한 활성 판정으로 잠그고 있다. \
                Commands 트리는 다시 평가되지 않으므로 키보드 단축키가 통째로 죽는다.
                """
            )
        }
    }

    /// 실행 시점 게이트는 반드시 남아 있어야 한다 — 메뉴가 항상 활성인 대신 여기서 막는다.
    func testActionIsGatedAtInvocationInstead() {
        let model = AppModel()
        // 선택된 사진이 없다 → 자동 톤은 조건 불충족.
        XCTAssertNil(model.actionableFrame)
        XCTAssertFalse(model.canPerformWorkflowShortcutAction(.autoTone))
        // 눌러도 안전해야 한다(크래시·상태 변화 없음).
        model.performWorkflowShortcutAction(.autoTone)
        XCTAssertNil(model.actionableFrame)
    }
}
