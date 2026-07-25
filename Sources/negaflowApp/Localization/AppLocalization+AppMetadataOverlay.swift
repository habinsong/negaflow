import Foundation

enum AppMetadataOverlayLocalizedText {
    case title, fieldTitle, caption, keywords, copyright, save, applySelection, conflict, resolve

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            ["App Metadata", "Title", "Caption", "Keywords", "Copyright", "Save", "Apply to Selection", "Source Changed", "Use Current Source"][index]
        case .korean:
            ["앱 메타데이터", "제목", "설명", "키워드", "저작권", "저장", "선택 항목에 적용", "원본 메타데이터 변경", "현재 원본 기준으로 갱신"][index]
        case .japanese:
            ["アプリメタデータ", "タイトル", "説明", "キーワード", "著作権", "保存", "選択項目に適用", "ソースが変更されました", "現在のソースを使用"][index]
        case .simplifiedChinese:
            ["应用元数据", "标题", "说明", "关键词", "版权", "存储", "应用到所选项目", "来源已更改", "使用当前来源"][index]
        case .french:
            ["Métadonnées de l’app", "Titre", "Légende", "Mots-clés", "Droits", "Enregistrer", "Appliquer à la sélection", "Source modifiée", "Utiliser la source actuelle"][index]
        case .german:
            ["App-Metadaten", "Titel", "Beschreibung", "Stichwörter", "Urheberrecht", "Sichern", "Auf Auswahl anwenden", "Quelle geändert", "Aktuelle Quelle verwenden"][index]
        }
    }

    private var index: Int {
        switch self {
        case .title: 0; case .fieldTitle: 1; case .caption: 2; case .keywords: 3
        case .copyright: 4; case .save: 5; case .applySelection: 6; case .conflict: 7; case .resolve: 8
        }
    }
}
