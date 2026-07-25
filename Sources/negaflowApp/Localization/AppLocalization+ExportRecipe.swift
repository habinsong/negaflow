import Foundation

enum ExportRecipeLocalizedText {
    case title
    case empty
    case name
    case saveCurrent
    case defaultName(Int)
    case applied(String)
    case saved(String)
    case deleted(String)

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english: english
        case .korean: korean
        case .japanese: japanese
        case .simplifiedChinese: simplifiedChinese
        case .french: french
        case .german: german
        }
    }

    private var english: String {
        switch self {
        case .title: "Export Settings"
        case .empty: "No Saved Settings"
        case .name: "Settings Name"
        case .saveCurrent: "Save Current Settings"
        case .defaultName(let index): "Export Settings \(index)"
        case .applied(let name): "Applied export settings: \(name)"
        case .saved(let name): "Saved export settings: \(name)"
        case .deleted(let name): "Deleted export settings: \(name)"
        }
    }

    private var korean: String {
        switch self {
        case .title: "내보내기 설정"
        case .empty: "저장된 설정 없음"
        case .name: "설정 이름"
        case .saveCurrent: "현재 설정 저장"
        case .defaultName(let index): "내보내기 설정 \(index)"
        case .applied(let name): "내보내기 설정 적용: \(name)"
        case .saved(let name): "내보내기 설정 저장: \(name)"
        case .deleted(let name): "내보내기 설정 삭제: \(name)"
        }
    }

    private var japanese: String {
        switch self {
        case .title: "書き出し設定"
        case .empty: "保存済み設定なし"
        case .name: "設定名"
        case .saveCurrent: "現在の設定を保存"
        case .defaultName(let index): "書き出し設定 \(index)"
        case .applied(let name): "書き出し設定を適用: \(name)"
        case .saved(let name): "書き出し設定を保存: \(name)"
        case .deleted(let name): "書き出し設定を削除: \(name)"
        }
    }

    private var simplifiedChinese: String {
        switch self {
        case .title: "导出设置"
        case .empty: "无已存设置"
        case .name: "设置名称"
        case .saveCurrent: "存储当前设置"
        case .defaultName(let index): "导出设置 \(index)"
        case .applied(let name): "已应用导出设置：\(name)"
        case .saved(let name): "已存储导出设置：\(name)"
        case .deleted(let name): "已删除导出设置：\(name)"
        }
    }

    private var french: String {
        switch self {
        case .title: "Réglages d’exportation"
        case .empty: "Aucun réglage enregistré"
        case .name: "Nom des réglages"
        case .saveCurrent: "Enregistrer les réglages"
        case .defaultName(let index): "Réglages d’exportation \(index)"
        case .applied(let name): "Réglages d’exportation appliqués : \(name)"
        case .saved(let name): "Réglages d’exportation enregistrés : \(name)"
        case .deleted(let name): "Réglages d’exportation supprimés : \(name)"
        }
    }

    private var german: String {
        switch self {
        case .title: "Exporteinstellungen"
        case .empty: "Keine gespeicherten Einstellungen"
        case .name: "Einstellungsname"
        case .saveCurrent: "Aktuelle Einstellungen sichern"
        case .defaultName(let index): "Exporteinstellungen \(index)"
        case .applied(let name): "Exporteinstellungen angewendet: \(name)"
        case .saved(let name): "Exporteinstellungen gesichert: \(name)"
        case .deleted(let name): "Exporteinstellungen gelöscht: \(name)"
        }
    }
}
