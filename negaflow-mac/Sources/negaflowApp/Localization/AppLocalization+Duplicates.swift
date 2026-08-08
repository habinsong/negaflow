import Foundation

enum AppDuplicateText {
    case find
    case title
    case scanning
    case none
    case exactBytes
    case selectGroup
    case close
    case summary
    case unavailable
    case failed
}

extension AppLocalization {
    static func duplicateText(_ key: AppDuplicateText, language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch key {
            case .find: return "Find Duplicate Candidates"
            case .title: return "Duplicate Candidates"
            case .scanning: return "Verifying exact file matches"
            case .none: return "No byte-identical candidates found"
            case .exactBytes: return "Exact file · %d bytes"
            case .selectGroup: return "Select Group"
            case .close: return "Close"
            case .summary: return "%d groups · %d files inspected"
            case .unavailable: return "%d unavailable files skipped"
            case .failed: return "Duplicate verification could not be completed"
            }
        case .korean:
            switch key {
            case .find: return "중복 후보 찾기"
            case .title: return "중복 후보"
            case .scanning: return "파일 전체가 같은지 확인 중"
            case .none: return "바이트가 완전히 같은 후보가 없습니다"
            case .exactBytes: return "완전 동일 파일 · %d바이트"
            case .selectGroup: return "그룹 선택"
            case .close: return "닫기"
            case .summary: return "%d개 그룹 · 파일 %d개 확인"
            case .unavailable: return "오프라인 파일 %d개 제외"
            case .failed: return "중복 확인을 완료하지 못했습니다"
            }
        case .japanese:
            switch key {
            case .find: return "重複候補を検索"
            case .title: return "重複候補"
            case .scanning: return "ファイル全体の一致を確認中"
            case .none: return "バイト単位で同一の候補はありません"
            case .exactBytes: return "完全に同一のファイル · %d バイト"
            case .selectGroup: return "グループを選択"
            case .close: return "閉じる"
            case .summary: return "%d グループ · %d ファイルを確認"
            case .unavailable: return "オフラインの %d ファイルを除外"
            case .failed: return "重複の確認を完了できませんでした"
            }
        case .simplifiedChinese:
            switch key {
            case .find: return "查找重复候选"
            case .title: return "重复候选"
            case .scanning: return "正在验证完整文件是否一致"
            case .none: return "未找到字节完全相同的候选"
            case .exactBytes: return "完全相同的文件 · %d 字节"
            case .selectGroup: return "选择此组"
            case .close: return "关闭"
            case .summary: return "%d 组 · 已检查 %d 个文件"
            case .unavailable: return "已跳过 %d 个离线文件"
            case .failed: return "无法完成重复项验证"
            }
        case .french:
            switch key {
            case .find: return "Rechercher les doublons"
            case .title: return "Doublons potentiels"
            case .scanning: return "Vérification de l’identité complète des fichiers"
            case .none: return "Aucun fichier strictement identique trouvé"
            case .exactBytes: return "Fichier identique · %d octets"
            case .selectGroup: return "Sélectionner le groupe"
            case .close: return "Fermer"
            case .summary: return "%d groupes · %d fichiers vérifiés"
            case .unavailable: return "%d fichiers indisponibles ignorés"
            case .failed: return "La vérification des doublons n’a pas pu aboutir"
            }
        case .german:
            switch key {
            case .find: return "Duplikatkandidaten suchen"
            case .title: return "Duplikatkandidaten"
            case .scanning: return "Vollständige Dateiübereinstimmung wird geprüft"
            case .none: return "Keine bytegleichen Kandidaten gefunden"
            case .exactBytes: return "Exakte Datei · %d Byte"
            case .selectGroup: return "Gruppe auswählen"
            case .close: return "Schließen"
            case .summary: return "%d Gruppen · %d Dateien geprüft"
            case .unavailable: return "%d nicht verfügbare Dateien übersprungen"
            case .failed: return "Die Duplikatprüfung konnte nicht abgeschlossen werden"
            }
        }
    }
}

extension AppModel {
    func duplicateText(_ key: AppDuplicateText, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.duplicateText(key, language: appLanguage),
            arguments: arguments
        )
    }
}
