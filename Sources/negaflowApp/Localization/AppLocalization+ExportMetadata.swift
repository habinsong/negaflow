import Foundation

enum ExportMetadataLocalizedText {
    case label
    case all
    case copyrightOnly
    case removeLocation
    case minimal

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .label: "Metadata"
            case .all: "All"
            case .copyrightOnly: "Copyright Only"
            case .removeLocation: "Remove Location"
            case .minimal: "Minimal"
            }
        case .korean:
            switch self {
            case .label: "메타데이터"
            case .all: "전체"
            case .copyrightOnly: "저작권만"
            case .removeLocation: "위치 제거"
            case .minimal: "최소"
            }
        case .japanese:
            switch self {
            case .label: "メタデータ"
            case .all: "すべて"
            case .copyrightOnly: "著作権のみ"
            case .removeLocation: "位置情報を削除"
            case .minimal: "最小"
            }
        case .simplifiedChinese:
            switch self {
            case .label: "元数据"
            case .all: "全部"
            case .copyrightOnly: "仅版权"
            case .removeLocation: "移除位置"
            case .minimal: "最少"
            }
        case .french:
            switch self {
            case .label: "Métadonnées"
            case .all: "Toutes"
            case .copyrightOnly: "Droits uniquement"
            case .removeLocation: "Supprimer la position"
            case .minimal: "Minimales"
            }
        case .german:
            switch self {
            case .label: "Metadaten"
            case .all: "Alle"
            case .copyrightOnly: "Nur Urheberrecht"
            case .removeLocation: "Standort entfernen"
            case .minimal: "Minimal"
            }
        }
    }
}
