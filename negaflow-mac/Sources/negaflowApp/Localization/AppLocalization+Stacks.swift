import Foundation

enum AppStackText {
    case group
    case ungroup
    case expand
    case collapse
    case count
}

extension AppLocalization {
    static func stackText(_ key: AppStackText, language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch key {
            case .group: return "Group into Stack"
            case .ungroup: return "Ungroup Stack"
            case .expand: return "Expand Stack"
            case .collapse: return "Collapse Stack"
            case .count: return "%d photos in stack"
            }
        case .korean:
            switch key {
            case .group: return "스택으로 묶기"
            case .ungroup: return "스택 해제"
            case .expand: return "스택 펼치기"
            case .collapse: return "스택 접기"
            case .count: return "스택에 사진 %d장"
            }
        case .japanese:
            switch key {
            case .group: return "スタックにまとめる"
            case .ungroup: return "スタックを解除"
            case .expand: return "スタックを展開"
            case .collapse: return "スタックを折りたたむ"
            case .count: return "スタック内の写真 %d 枚"
            }
        case .simplifiedChinese:
            switch key {
            case .group: return "组合为堆栈"
            case .ungroup: return "取消堆栈"
            case .expand: return "展开堆栈"
            case .collapse: return "折叠堆栈"
            case .count: return "堆栈中有 %d 张照片"
            }
        case .french:
            switch key {
            case .group: return "Grouper en pile"
            case .ungroup: return "Dissocier la pile"
            case .expand: return "Développer la pile"
            case .collapse: return "Réduire la pile"
            case .count: return "%d photos dans la pile"
            }
        case .german:
            switch key {
            case .group: return "Zu Stapel gruppieren"
            case .ungroup: return "Stapel auflösen"
            case .expand: return "Stapel erweitern"
            case .collapse: return "Stapel reduzieren"
            case .count: return "%d Fotos im Stapel"
            }
        }
    }
}

extension AppModel {
    func stackText(_ key: AppStackText, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.stackText(key, language: appLanguage),
            arguments: arguments
        )
    }
}
