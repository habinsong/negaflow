import Foundation
import SwiftUI

/// 키 없이 조합키만으로 거는 동작. 키 단축키와 달리 마우스 드래그와 함께 누르거나(기준선)
/// 누르고 있는 동안만 켜진다(격자).
enum WorkflowGestureModifierAction: String, CaseIterable, Codable, Identifiable {
    /// 크롭 중 이 키를 누른 채 사진 위를 끌면 기준선이 그려지고, 놓으면 그 선이 수평(또는 수직)이
    /// 되도록 각도를 맞춘다.
    case straightenWithLine
    /// 크롭 중 이 키를 누르고 있는 동안 촘촘한 격자를 보여 준다.
    case straightenGrid

    var id: Self { self }

    var defaultModifier: WorkflowShortcutModifiers {
        switch self {
        case .straightenWithLine: return .command
        case .straightenGrid: return .option
        }
    }

    /// 고를 수 있는 키. ⌃ 클릭은 macOS 에서 오른쪽 클릭(문맥 메뉴)이라 드래그에는 쓰지 않는다.
    var allowedModifiers: [WorkflowShortcutModifiers] {
        switch self {
        case .straightenWithLine: return [.command, .option, .shift]
        case .straightenGrid: return [.command, .option, .control, .shift]
        }
    }
}

extension WorkflowGestureModifierAction {
    @MainActor
    func title(in model: AppModel) -> String {
        switch self {
        case .straightenWithLine: return model.text(AppLocalizedPhrase.straightenWithLine)
        case .straightenGrid: return model.text(AppLocalizedPhrase.straightenGrid)
        }
    }
}
