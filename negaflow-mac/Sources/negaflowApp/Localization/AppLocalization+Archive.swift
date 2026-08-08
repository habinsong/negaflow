import Foundation

enum AppArchiveText {
    case create
    case save
    case created
    case failed
}

extension AppLocalization {
    static func archiveText(_ key: AppArchiveText, language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch key {
            case .create: return "Create Preservation Archive"
            case .save: return "Create Archive"
            case .created: return "Preservation archive created"
            case .failed: return "Preservation archive failed"
            }
        case .korean:
            switch key {
            case .create: return "보존 아카이브 생성"
            case .save: return "아카이브 생성"
            case .created: return "보존 아카이브를 생성했습니다"
            case .failed: return "보존 아카이브 생성에 실패했습니다"
            }
        case .japanese:
            switch key {
            case .create: return "保存アーカイブを作成"
            case .save: return "アーカイブを作成"
            case .created: return "保存アーカイブを作成しました"
            case .failed: return "保存アーカイブの作成に失敗しました"
            }
        case .simplifiedChinese:
            switch key {
            case .create: return "创建保存归档"
            case .save: return "创建归档"
            case .created: return "保存归档已创建"
            case .failed: return "保存归档创建失败"
            }
        case .french:
            switch key {
            case .create: return "Créer une archive de conservation"
            case .save: return "Créer l’archive"
            case .created: return "Archive de conservation créée"
            case .failed: return "Échec de la création de l’archive"
            }
        case .german:
            switch key {
            case .create: return "Langzeitarchiv erstellen"
            case .save: return "Archiv erstellen"
            case .created: return "Langzeitarchiv erstellt"
            case .failed: return "Langzeitarchiv konnte nicht erstellt werden"
            }
        }
    }
}

extension AppModel {
    func archiveText(_ key: AppArchiveText) -> String {
        AppLocalization.archiveText(key, language: appLanguage)
    }
}
