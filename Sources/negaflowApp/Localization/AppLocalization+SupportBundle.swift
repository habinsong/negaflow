import Foundation

enum SupportBundleLocalizedText {
    case title, export, creating, complete, failed

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english: english[index]
        case .korean: korean[index]
        case .japanese: japanese[index]
        case .simplifiedChinese: chinese[index]
        case .french: french[index]
        case .german: german[index]
        }
    }

    private var index: Int {
        switch self {
        case .title: 0; case .export: 1; case .creating: 2; case .complete: 3; case .failed: 4
        }
    }

    private var english: [String] { ["Support Bundle", "Export", "Creating", "Support bundle created", "Could not create support bundle"] }
    private var korean: [String] { ["지원 번들", "내보내기", "생성 중", "지원 번들을 생성했습니다", "지원 번들을 생성하지 못했습니다"] }
    private var japanese: [String] { ["サポートバンドル", "書き出す", "作成中", "サポートバンドルを作成しました", "サポートバンドルを作成できませんでした"] }
    private var chinese: [String] { ["支持包", "导出", "正在创建", "支持包已创建", "无法创建支持包"] }
    private var french: [String] { ["Bundle d’assistance", "Exporter", "Création", "Bundle d’assistance créé", "Impossible de créer le bundle d’assistance"] }
    private var german: [String] { ["Supportpaket", "Exportieren", "Wird erstellt", "Supportpaket erstellt", "Supportpaket konnte nicht erstellt werden"] }
}
