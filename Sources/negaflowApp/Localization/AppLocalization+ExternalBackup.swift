import Foundation

enum ExternalBackupLocalizedText {
    case title, choose, change, remove, refresh, notConfigured, disconnected, sameVolume
    case readOnly, insufficient, ready, capacity, lastSuccess, never

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
        case .title: 0; case .choose: 1; case .change: 2; case .remove: 3; case .refresh: 4
        case .notConfigured: 5; case .disconnected: 6; case .sameVolume: 7; case .readOnly: 8
        case .insufficient: 9; case .ready: 10; case .capacity: 11; case .lastSuccess: 12; case .never: 13
        }
    }

    private var english: [String] { ["External Backup", "Choose", "Change", "Remove", "Refresh", "Not configured", "Disconnected", "Same volume as catalog", "Read-only destination", "Not enough space", "Connected", "Available", "Last successful backup", "Never"] }
    private var korean: [String] { ["외부 백업", "선택", "변경", "제거", "새로고침", "설정 안 됨", "연결 끊김", "카탈로그와 같은 볼륨", "읽기 전용 대상", "공간 부족", "연결됨", "사용 가능", "마지막 성공 백업", "없음"] }
    private var japanese: [String] { ["外部バックアップ", "選択", "変更", "削除", "更新", "未設定", "未接続", "カタログと同じボリューム", "読み取り専用", "空き容量不足", "接続済み", "利用可能", "最終成功バックアップ", "なし"] }
    private var chinese: [String] { ["外部备份", "选择", "更改", "移除", "刷新", "未配置", "已断开", "与目录位于同一卷", "只读目标", "空间不足", "已连接", "可用", "上次成功备份", "从未"] }
    private var french: [String] { ["Sauvegarde externe", "Choisir", "Modifier", "Supprimer", "Actualiser", "Non configurée", "Déconnectée", "Même volume que le catalogue", "Destination en lecture seule", "Espace insuffisant", "Connectée", "Disponible", "Dernière sauvegarde réussie", "Jamais"] }
    private var german: [String] { ["Externes Backup", "Auswählen", "Ändern", "Entfernen", "Aktualisieren", "Nicht eingerichtet", "Nicht verbunden", "Gleiches Volume wie Katalog", "Schreibgeschütztes Ziel", "Nicht genügend Speicher", "Verbunden", "Verfügbar", "Letztes erfolgreiches Backup", "Nie"] }
}
