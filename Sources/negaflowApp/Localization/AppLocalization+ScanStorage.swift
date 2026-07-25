import Foundation

enum ScanStorageLocalizedText {
    case originals, change, estimatedAvailable, storage, local, cloudManaged, unavailable

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
        case .originals: 0; case .change: 1; case .estimatedAvailable: 2
        case .storage: 3; case .local: 4; case .cloudManaged: 5; case .unavailable: 6
        }
    }

    private var english: [String] { ["Scan Originals", "Change", "Estimated available", "Storage", "Local", "Cloud-managed", "Unavailable"] }
    private var korean: [String] { ["스캔 원본", "변경", "예상 사용 가능 공간", "저장소", "로컬", "클라우드 관리", "확인 불가"] }
    private var japanese: [String] { ["スキャン原本", "変更", "推定空き容量", "ストレージ", "ローカル", "クラウド管理", "確認不可"] }
    private var chinese: [String] { ["扫描原件", "更改", "预计可用空间", "存储", "本地", "云管理", "不可用"] }
    private var french: [String] { ["Originaux numérisés", "Modifier", "Espace disponible estimé", "Stockage", "Local", "Géré dans le cloud", "Indisponible"] }
    private var german: [String] { ["Scan-Originale", "Ändern", "Geschätzt verfügbar", "Speicher", "Lokal", "Cloudverwaltet", "Nicht verfügbar"] }
}
