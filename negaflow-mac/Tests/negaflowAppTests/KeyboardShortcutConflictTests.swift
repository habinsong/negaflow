import XCTest
@testable import negaflowApp

/// 단축키 충돌 전수 검사.
///
/// 실측으로 확인한 고장: 인스펙터의 자동 톤/자동 화이트 밸런스 알약과 캔버스의 이전/이후
/// 토글이 메뉴와 **같은 단축키를 뷰 계층에 한 번 더** 등록하고 있었다. AppKit 은 메뉴보다
/// 뷰의 `performKeyEquivalent` 를 먼저 태우므로 뷰 쪽이 키를 가져가고, 그 뷰가 자기만의
/// 조건(`canAutoAdjust = displayedImage != nil`)으로 비활성이면 키는 그대로 삼켜진다.
/// 메뉴 항목은 활성인데도 아무 일이 없었던 이유다.
///
/// 규칙: 단축키는 **메뉴가 한 번만** 등록한다.
@MainActor
final class KeyboardShortcutConflictTests: XCTestCase {

    private static let menuFiles: Set<String> = [
        "App/AppWorkflowMenuCommands.swift",
        "App/AppStandardMenuCommands.swift",
        "Shortcuts/Workflow/View+WorkflowShortcut.swift",
    ]

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/negaflowApp", isDirectory: true)
    }

    /// 기본 단축키는 액션끼리 겹치면 안 된다.
    func testDefaultShortcutsAreUnique() {
        var owners: [String: [WorkflowShortcutAction]] = [:]
        for action in WorkflowShortcutAction.allCases {
            owners[action.defaultShortcut.signature, default: []].append(action)
        }
        let clashes = owners.filter { $0.value.count > 1 }
        XCTAssertTrue(
            clashes.isEmpty,
            "기본 단축키가 겹친다: " + clashes.map { "\($0.key) → \($0.value.map(\.rawValue))" }
                .joined(separator: ", ")
        )
    }

    /// 사용자 설정(override)을 얹어도 겹치면 안 된다 — 스토어가 충돌을 거부하는지 확인.
    func testStoreRejectsAConflictingOverride() {
        let name = "workflow-shortcut-conflict-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = WorkflowShortcutStore(defaults: defaults)

        // 자동 화이트 밸런스가 이미 쓰는 조합(⇧⌘U)을 자동 톤에 주면 거부돼야 한다.
        let taken = WorkflowShortcutAction.autoWhiteBalance.defaultShortcut
        XCTAssertFalse(store.setShortcut(taken, for: .autoTone))
        XCTAssertEqual(store.shortcut(for: .autoTone), WorkflowShortcutAction.autoTone.defaultShortcut)
    }

    /// 뷰 계층은 워크플로 단축키를 등록하지 않는다 — 메뉴 것을 가로채기 때문.
    func testNoViewRegistersAWorkflowShortcut() throws {
        var offenders: [String] = []
        for file in try swiftFiles() {
            let relative = file.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            guard !Self.menuFiles.contains(relative) else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
            where line.contains(".workflowKeyboardShortcut(") {
                offenders.append("\(relative):\(index + 1)")
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            """
            뷰가 워크플로 단축키를 중복 등록하고 있다(메뉴 단축키를 삼킨다): \
            \(offenders.joined(separator: ", "))
            """
        )
    }

    /// 뷰의 직접 `keyboardShortcut("x", modifiers:)` 도 워크플로 기본과 겹치면 안 된다.
    func testRawViewShortcutsDoNotCollideWithWorkflowDefaults() throws {
        var taken: [String: WorkflowShortcutAction] = [:]
        for action in WorkflowShortcutAction.allCases {
            taken[action.defaultShortcut.signature] = action
        }

        var offenders: [String] = []
        let pattern = try NSRegularExpression(
            pattern: #"\.keyboardShortcut\("(.)",\s*modifiers:\s*(\[[^\]]*\]|\.[a-zA-Z]+)\)"#
        )
        for file in try swiftFiles() {
            let relative = file.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                guard let match = pattern.firstMatch(in: line, range: range),
                      let keyRange = Range(match.range(at: 1), in: line),
                      let modRange = Range(match.range(at: 2), in: line) else { continue }
                let shortcut = WorkflowShortcut(
                    key: String(line[keyRange]),
                    modifiers: Self.modifiers(from: String(line[modRange]))
                )
                if let owner = taken[shortcut.signature] {
                    offenders.append("\(relative):\(index + 1) \(shortcut.displayString) = \(owner.rawValue)")
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "뷰 단축키가 워크플로 액션과 겹친다: \(offenders.joined(separator: ", "))"
        )
    }

    // MARK: 도구

    private func swiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot, includingPropertiesForKeys: nil
        )
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    private static func modifiers(from text: String) -> WorkflowShortcutModifiers {
        var result: WorkflowShortcutModifiers = []
        if text.contains("command") { result.insert(.command) }
        if text.contains("shift") { result.insert(.shift) }
        if text.contains("option") { result.insert(.option) }
        if text.contains("control") { result.insert(.control) }
        return result
    }
}
