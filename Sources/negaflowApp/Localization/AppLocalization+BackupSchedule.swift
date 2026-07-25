import Foundation

enum BackupScheduleLocalizedText {
    case schedule, manual, termination, daily, weekly, lastAttempt, lastSuccess
    case verification, passed, failed, never, generation

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
        case .schedule: 0; case .manual: 1; case .termination: 2; case .daily: 3; case .weekly: 4
        case .lastAttempt: 5; case .lastSuccess: 6; case .verification: 7; case .passed: 8
        case .failed: 9; case .never: 10; case .generation: 11
        }
    }

    private var english: [String] { ["Backup Schedule", "Manual", "When Quitting", "Daily", "Weekly", "Last attempt", "Last success", "Restore verification", "Passed", "Failed", "Never", "Generation"] }
    private var korean: [String] { ["백업 일정", "수동", "앱 종료 시", "매일", "매주", "마지막 시도", "마지막 성공", "복원 검증", "통과", "실패", "없음", "세대"] }
    private var japanese: [String] { ["バックアップ予定", "手動", "終了時", "毎日", "毎週", "最終試行", "最終成功", "復元検証", "合格", "失敗", "なし", "世代"] }
    private var chinese: [String] { ["备份计划", "手动", "退出时", "每天", "每周", "上次尝试", "上次成功", "恢复验证", "通过", "失败", "从未", "代"] }
    private var french: [String] { ["Planification", "Manuelle", "À la fermeture", "Chaque jour", "Chaque semaine", "Dernière tentative", "Dernière réussite", "Vérification de restauration", "Réussie", "Échouée", "Jamais", "Génération"] }
    private var german: [String] { ["Backup-Zeitplan", "Manuell", "Beim Beenden", "Täglich", "Wöchentlich", "Letzter Versuch", "Letzter Erfolg", "Wiederherstellungsprüfung", "Bestanden", "Fehlgeschlagen", "Nie", "Generation"] }
}
