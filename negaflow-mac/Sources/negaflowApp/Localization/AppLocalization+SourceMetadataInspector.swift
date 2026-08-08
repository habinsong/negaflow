import Foundation

enum SourceMetadataInspectorLocalizedText {
    case info, source, sidecar, camera, date, title, keywords
    case embedded, sidecarOrigin, mixed, unknown, notAvailable
    case loaded, notFound, invalid, tooLarge, ambiguous, readProblem

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english: english
        case .korean: korean
        case .japanese: japanese
        case .simplifiedChinese: chinese
        case .french: french
        case .german: german
        }
    }

    private var english: String {
        switch self {
        case .info: "Info"; case .source: "Source"; case .sidecar: "Sidecar"
        case .camera: "Camera"; case .date: "Date"; case .title: "Title"; case .keywords: "Keywords"
        case .embedded: "Embedded"; case .sidecarOrigin: "Sidecar"; case .mixed: "Embedded + Sidecar"
        case .unknown: "Unknown"; case .notAvailable: "—"; case .loaded: "Loaded"; case .notFound: "Not Found"
        case .invalid: "Invalid"; case .tooLarge: "Too Large"; case .ambiguous: "Ambiguous"
        case .readProblem: "Some metadata could not be read."
        }
    }

    private var korean: String {
        switch self {
        case .info: "정보"; case .source: "원본"; case .sidecar: "Sidecar"
        case .camera: "카메라"; case .date: "날짜"; case .title: "제목"; case .keywords: "키워드"
        case .embedded: "파일 내장"; case .sidecarOrigin: "Sidecar"; case .mixed: "내장 + Sidecar"
        case .unknown: "미확인"; case .notAvailable: "—"; case .loaded: "읽음"; case .notFound: "없음"
        case .invalid: "손상"; case .tooLarge: "크기 초과"; case .ambiguous: "여러 파일"
        case .readProblem: "일부 메타데이터를 읽지 못했습니다."
        }
    }

    private var japanese: String {
        switch self {
        case .info: "情報"; case .source: "ソース"; case .sidecar: "サイドカー"
        case .camera: "カメラ"; case .date: "日付"; case .title: "タイトル"; case .keywords: "キーワード"
        case .embedded: "埋め込み"; case .sidecarOrigin: "サイドカー"; case .mixed: "埋め込み + サイドカー"
        case .unknown: "不明"; case .notAvailable: "—"; case .loaded: "読み込み済み"; case .notFound: "なし"
        case .invalid: "無効"; case .tooLarge: "大きすぎます"; case .ambiguous: "複数候補"
        case .readProblem: "一部のメタデータを読み込めませんでした。"
        }
    }

    private var chinese: String {
        switch self {
        case .info: "信息"; case .source: "来源"; case .sidecar: "Sidecar"
        case .camera: "相机"; case .date: "日期"; case .title: "标题"; case .keywords: "关键词"
        case .embedded: "嵌入"; case .sidecarOrigin: "Sidecar"; case .mixed: "嵌入 + Sidecar"
        case .unknown: "未知"; case .notAvailable: "—"; case .loaded: "已读取"; case .notFound: "未找到"
        case .invalid: "无效"; case .tooLarge: "过大"; case .ambiguous: "多个候选"
        case .readProblem: "部分元数据无法读取。"
        }
    }

    private var french: String {
        switch self {
        case .info: "Infos"; case .source: "Source"; case .sidecar: "Annexe"
        case .camera: "Appareil"; case .date: "Date"; case .title: "Titre"; case .keywords: "Mots-clés"
        case .embedded: "Intégré"; case .sidecarOrigin: "Annexe"; case .mixed: "Intégré + annexe"
        case .unknown: "Inconnu"; case .notAvailable: "—"; case .loaded: "Chargé"; case .notFound: "Absent"
        case .invalid: "Invalide"; case .tooLarge: "Trop volumineux"; case .ambiguous: "Ambigu"
        case .readProblem: "Certaines métadonnées sont illisibles."
        }
    }

    private var german: String {
        switch self {
        case .info: "Info"; case .source: "Quelle"; case .sidecar: "Sidecar"
        case .camera: "Kamera"; case .date: "Datum"; case .title: "Titel"; case .keywords: "Stichwörter"
        case .embedded: "Eingebettet"; case .sidecarOrigin: "Sidecar"; case .mixed: "Eingebettet + Sidecar"
        case .unknown: "Unbekannt"; case .notAvailable: "—"; case .loaded: "Geladen"; case .notFound: "Fehlt"
        case .invalid: "Ungültig"; case .tooLarge: "Zu groß"; case .ambiguous: "Mehrdeutig"
        case .readProblem: "Einige Metadaten konnten nicht gelesen werden."
        }
    }
}
