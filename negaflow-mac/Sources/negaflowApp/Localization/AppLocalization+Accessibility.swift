import Foundation

enum AppAccessibilityPhrase {
    case input
    case output
    case curvePointValueFormat
    case previousPoint
    case nextPoint
    case addPoint
    case deletePoint
    case previousRegion
    case nextRegion
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case cropValueFormat
    case filmstripHeightValueFormat
    case selected
    case notSelected
    case on
    case off
    case active
    case inactive
    case blocked
    case select
    case activate
    case deactivate
    case turnOn
    case turnOff
}

extension AppLocalization {
    static func accessibilityText(
        _ key: AppAccessibilityPhrase,
        language: AppLanguage
    ) -> String {
        accessibilityTable[language.resolved]?[key]
            ?? accessibilityTable[.english]![key]!
    }

    private static let accessibilityTable: [AppLanguage: [AppAccessibilityPhrase: String]] = [
        .english: [
            .input: "Input", .output: "Output",
            .curvePointValueFormat: "Point %d of %d, input %d percent, output %d percent",
            .previousPoint: "Previous point", .nextPoint: "Next point",
            .addPoint: "Add point", .deletePoint: "Delete point",
            .previousRegion: "Previous tone region", .nextRegion: "Next tone region",
            .moveLeft: "Move left", .moveRight: "Move right",
            .moveUp: "Move up", .moveDown: "Move down",
            .cropValueFormat: "X %d percent, Y %d percent, width %d percent, height %d percent",
            .filmstripHeightValueFormat: "%d points high",
            .selected: "Selected", .notSelected: "Not selected",
            .on: "On", .off: "Off", .active: "Active", .inactive: "Inactive", .blocked: "Blocked",
            .select: "Select", .activate: "Activate", .deactivate: "Deactivate",
            .turnOn: "Turn on", .turnOff: "Turn off"
        ],
        .korean: [
            .input: "입력", .output: "출력",
            .curvePointValueFormat: "%d/%d 포인트, 입력 %d퍼센트, 출력 %d퍼센트",
            .previousPoint: "이전 포인트", .nextPoint: "다음 포인트",
            .addPoint: "포인트 추가", .deletePoint: "포인트 삭제",
            .previousRegion: "이전 톤 영역", .nextRegion: "다음 톤 영역",
            .moveLeft: "왼쪽으로 이동", .moveRight: "오른쪽으로 이동",
            .moveUp: "위로 이동", .moveDown: "아래로 이동",
            .cropValueFormat: "X %d퍼센트, Y %d퍼센트, 너비 %d퍼센트, 높이 %d퍼센트",
            .filmstripHeightValueFormat: "높이 %d포인트",
            .selected: "선택됨", .notSelected: "선택되지 않음",
            .on: "켬", .off: "끔", .active: "활성", .inactive: "비활성", .blocked: "차단됨",
            .select: "선택", .activate: "활성화", .deactivate: "비활성화",
            .turnOn: "켜기", .turnOff: "끄기"
        ],
        .japanese: [
            .input: "入力", .output: "出力",
            .curvePointValueFormat: "%d/%dポイント、入力%dパーセント、出力%dパーセント",
            .previousPoint: "前のポイント", .nextPoint: "次のポイント",
            .addPoint: "ポイントを追加", .deletePoint: "ポイントを削除",
            .previousRegion: "前のトーン領域", .nextRegion: "次のトーン領域",
            .moveLeft: "左へ移動", .moveRight: "右へ移動",
            .moveUp: "上へ移動", .moveDown: "下へ移動",
            .cropValueFormat: "X %dパーセント、Y %dパーセント、幅%dパーセント、高さ%dパーセント",
            .filmstripHeightValueFormat: "高さ%dポイント",
            .selected: "選択済み", .notSelected: "未選択",
            .on: "オン", .off: "オフ", .active: "有効", .inactive: "無効", .blocked: "ブロック済み",
            .select: "選択", .activate: "有効にする", .deactivate: "無効にする",
            .turnOn: "オンにする", .turnOff: "オフにする"
        ],
        .simplifiedChinese: [
            .input: "输入", .output: "输出",
            .curvePointValueFormat: "第%d个点，共%d个，输入%d百分比，输出%d百分比",
            .previousPoint: "上一个点", .nextPoint: "下一个点",
            .addPoint: "添加点", .deletePoint: "删除点",
            .previousRegion: "上一个色调区域", .nextRegion: "下一个色调区域",
            .moveLeft: "向左移动", .moveRight: "向右移动",
            .moveUp: "向上移动", .moveDown: "向下移动",
            .cropValueFormat: "X %d百分比，Y %d百分比，宽度%d百分比，高度%d百分比",
            .filmstripHeightValueFormat: "高度%d点",
            .selected: "已选择", .notSelected: "未选择",
            .on: "开", .off: "关", .active: "已启用", .inactive: "未启用", .blocked: "已阻止",
            .select: "选择", .activate: "启用", .deactivate: "停用",
            .turnOn: "打开", .turnOff: "关闭"
        ],
        .french: [
            .input: "Entrée", .output: "Sortie",
            .curvePointValueFormat: "Point %d sur %d, entrée %d pour cent, sortie %d pour cent",
            .previousPoint: "Point précédent", .nextPoint: "Point suivant",
            .addPoint: "Ajouter un point", .deletePoint: "Supprimer le point",
            .previousRegion: "Zone tonale précédente", .nextRegion: "Zone tonale suivante",
            .moveLeft: "Déplacer à gauche", .moveRight: "Déplacer à droite",
            .moveUp: "Déplacer vers le haut", .moveDown: "Déplacer vers le bas",
            .cropValueFormat: "X %d pour cent, Y %d pour cent, largeur %d pour cent, hauteur %d pour cent",
            .filmstripHeightValueFormat: "Hauteur de %d points",
            .selected: "Sélectionné", .notSelected: "Non sélectionné",
            .on: "Activé", .off: "Désactivé", .active: "Actif", .inactive: "Inactif", .blocked: "Bloqué",
            .select: "Sélectionner", .activate: "Activer", .deactivate: "Désactiver",
            .turnOn: "Activer", .turnOff: "Désactiver"
        ],
        .german: [
            .input: "Eingabe", .output: "Ausgabe",
            .curvePointValueFormat: "Punkt %d von %d, Eingabe %d Prozent, Ausgabe %d Prozent",
            .previousPoint: "Vorheriger Punkt", .nextPoint: "Nächster Punkt",
            .addPoint: "Punkt hinzufügen", .deletePoint: "Punkt löschen",
            .previousRegion: "Vorheriger Tonwertbereich", .nextRegion: "Nächster Tonwertbereich",
            .moveLeft: "Nach links bewegen", .moveRight: "Nach rechts bewegen",
            .moveUp: "Nach oben bewegen", .moveDown: "Nach unten bewegen",
            .cropValueFormat: "X %d Prozent, Y %d Prozent, Breite %d Prozent, Höhe %d Prozent",
            .filmstripHeightValueFormat: "%d Punkte hoch",
            .selected: "Ausgewählt", .notSelected: "Nicht ausgewählt",
            .on: "Ein", .off: "Aus", .active: "Aktiv", .inactive: "Inaktiv", .blocked: "Blockiert",
            .select: "Auswählen", .activate: "Aktivieren", .deactivate: "Deaktivieren",
            .turnOn: "Einschalten", .turnOff: "Ausschalten"
        ]
    ]
}

extension AppModel {
    func accessibilityText(_ key: AppAccessibilityPhrase, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.accessibilityText(key, language: appLanguage),
            arguments: arguments
        )
    }
}
