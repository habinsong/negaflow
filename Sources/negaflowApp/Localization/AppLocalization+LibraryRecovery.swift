import Foundation

enum LibraryRecoveryLocalizedText {
    case title
    case retry
    case revealInFinder
    case copyDiagnostics
}

extension AppLocalization {
    static func libraryRecoveryText(
        _ key: LibraryRecoveryLocalizedText,
        language: AppLanguage
    ) -> String {
        switch language.resolved {
        case .english:
            switch key {
            case .title: "Library Recovery"
            case .retry: "Retry"
            case .revealInFinder: "Show in Finder"
            case .copyDiagnostics: "Copy Diagnostics"
            }
        case .korean:
            switch key {
            case .title: "라이브러리 복구"
            case .retry: "재시도"
            case .revealInFinder: "Finder에서 보기"
            case .copyDiagnostics: "진단 복사"
            }
        case .japanese:
            switch key {
            case .title: "ライブラリの復旧"
            case .retry: "再試行"
            case .revealInFinder: "Finderで表示"
            case .copyDiagnostics: "診断情報をコピー"
            }
        case .simplifiedChinese:
            switch key {
            case .title: "图库恢复"
            case .retry: "重试"
            case .revealInFinder: "在 Finder 中显示"
            case .copyDiagnostics: "拷贝诊断信息"
            }
        case .french:
            switch key {
            case .title: "Récupération de la bibliothèque"
            case .retry: "Réessayer"
            case .revealInFinder: "Afficher dans le Finder"
            case .copyDiagnostics: "Copier le diagnostic"
            }
        case .german:
            switch key {
            case .title: "Mediathek wiederherstellen"
            case .retry: "Erneut versuchen"
            case .revealInFinder: "Im Finder anzeigen"
            case .copyDiagnostics: "Diagnose kopieren"
            }
        case .system:
            preconditionFailure("resolved language must not be system")
        }
    }
}
