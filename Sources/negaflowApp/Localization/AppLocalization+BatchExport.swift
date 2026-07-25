import Foundation

enum BatchExportLocalizedText {
    case pause
    case resume
    case cancel
    case retryFailed

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .pause: "Pause"
            case .resume: "Resume"
            case .cancel: "Cancel"
            case .retryFailed: "Retry Failed"
            }
        case .korean:
            switch self {
            case .pause: "일시 정지"
            case .resume: "재개"
            case .cancel: "취소"
            case .retryFailed: "실패 항목 재시도"
            }
        case .japanese:
            switch self {
            case .pause: "一時停止"
            case .resume: "再開"
            case .cancel: "キャンセル"
            case .retryFailed: "失敗項目を再試行"
            }
        case .simplifiedChinese:
            switch self {
            case .pause: "暂停"
            case .resume: "继续"
            case .cancel: "取消"
            case .retryFailed: "重试失败项目"
            }
        case .french:
            switch self {
            case .pause: "Suspendre"
            case .resume: "Reprendre"
            case .cancel: "Annuler"
            case .retryFailed: "Réessayer les échecs"
            }
        case .german:
            switch self {
            case .pause: "Pausieren"
            case .resume: "Fortsetzen"
            case .cancel: "Abbrechen"
            case .retryFailed: "Fehler erneut versuchen"
            }
        }
    }
}
