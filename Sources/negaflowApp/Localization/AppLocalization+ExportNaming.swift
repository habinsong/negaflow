import Foundation

enum ExportNamingLocalizedText {
    case pattern
    case preview
    case tokens
    case namingOptions
    case photoName
    case photoNameSequence
    case sequenceOnly
    case sequenceStart
    case filename

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .pattern: "Filename Pattern"
            case .preview: "Preview"
            case .tokens: "Tokens"
            case .namingOptions: "Naming Options"
            case .photoName: "Photo Name"
            case .photoNameSequence: "Photo Name + Sequence"
            case .sequenceOnly: "Sequence Only"
            case .sequenceStart: "Start Number"
            case .filename: "Filename"
            }
        case .korean:
            switch self {
            case .pattern: "파일명 패턴"
            case .preview: "미리보기"
            case .tokens: "토큰"
            case .namingOptions: "파일명 옵션"
            case .photoName: "사진명 유지"
            case .photoNameSequence: "사진명 + 시퀀스"
            case .sequenceOnly: "시퀀스만"
            case .sequenceStart: "시작 번호"
            case .filename: "파일명"
            }
        case .japanese:
            switch self {
            case .pattern: "ファイル名パターン"
            case .preview: "プレビュー"
            case .tokens: "トークン"
            case .namingOptions: "ファイル名オプション"
            case .photoName: "写真名"
            case .photoNameSequence: "写真名 + 連番"
            case .sequenceOnly: "連番のみ"
            case .sequenceStart: "開始番号"
            case .filename: "ファイル名"
            }
        case .simplifiedChinese:
            switch self {
            case .pattern: "文件名模式"
            case .preview: "预览"
            case .tokens: "令牌"
            case .namingOptions: "文件名选项"
            case .photoName: "照片名称"
            case .photoNameSequence: "照片名称 + 序号"
            case .sequenceOnly: "仅序号"
            case .sequenceStart: "起始编号"
            case .filename: "文件名"
            }
        case .french:
            switch self {
            case .pattern: "Modèle de nom"
            case .preview: "Aperçu"
            case .tokens: "Jetons"
            case .namingOptions: "Options de nommage"
            case .photoName: "Nom de la photo"
            case .photoNameSequence: "Nom de la photo + séquence"
            case .sequenceOnly: "Séquence uniquement"
            case .sequenceStart: "Numéro de départ"
            case .filename: "Nom du fichier"
            }
        case .german:
            switch self {
            case .pattern: "Dateinamensmuster"
            case .preview: "Vorschau"
            case .tokens: "Token"
            case .namingOptions: "Benennungsoptionen"
            case .photoName: "Fotoname"
            case .photoNameSequence: "Fotoname + Sequenz"
            case .sequenceOnly: "Nur Sequenz"
            case .sequenceStart: "Startnummer"
            case .filename: "Dateiname"
            }
        }
    }
}
