import Foundation

enum AppCullingText: CaseIterable {
    case grid
    case compare
    case survey
    case reference
    case candidate
    case compareNeedsTwoTitle
    case compareNeedsTwoDescription
    case surveyNeedsSelectionTitle
    case surveyNeedsSelectionDescription
}

extension AppLocalization {
    static func cullingText(_ key: AppCullingText, language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            return englishCullingText(key)
        case .korean:
            switch key {
            case .grid: return "격자"
            case .compare: return "비교"
            case .survey: return "살펴보기"
            case .reference: return "기준"
            case .candidate: return "후보"
            case .compareNeedsTwoTitle: return "사진 두 장을 선택하세요"
            case .compareNeedsTwoDescription: return "격자에서 Command 또는 Shift를 눌러 비교할 사진을 선택합니다."
            case .surveyNeedsSelectionTitle: return "사진을 선택하세요"
            case .surveyNeedsSelectionDescription: return "격자에서 여러 사진을 선택하면 한 화면에서 함께 살펴볼 수 있습니다."
            }
        case .japanese:
            switch key {
            case .grid: return "グリッド"
            case .compare: return "比較"
            case .survey: return "一覧比較"
            case .reference: return "基準"
            case .candidate: return "候補"
            case .compareNeedsTwoTitle: return "写真を2枚選択してください"
            case .compareNeedsTwoDescription: return "グリッドで Command または Shift を押しながら比較する写真を選択します。"
            case .surveyNeedsSelectionTitle: return "写真を選択してください"
            case .surveyNeedsSelectionDescription: return "グリッドで複数の写真を選ぶと、同じ画面で一覧比較できます。"
            }
        case .simplifiedChinese:
            switch key {
            case .grid: return "网格"
            case .compare: return "比较"
            case .survey: return "多图比较"
            case .reference: return "参照"
            case .candidate: return "候选"
            case .compareNeedsTwoTitle: return "请选择两张照片"
            case .compareNeedsTwoDescription: return "在网格中按住 Command 或 Shift 选择要比较的照片。"
            case .surveyNeedsSelectionTitle: return "请选择照片"
            case .surveyNeedsSelectionDescription: return "在网格中选择多张照片即可在同一画面中查看。"
            }
        case .french:
            switch key {
            case .grid: return "Grille"
            case .compare: return "Comparer"
            case .survey: return "Ensemble"
            case .reference: return "Référence"
            case .candidate: return "Candidate"
            case .compareNeedsTwoTitle: return "Sélectionnez deux photos"
            case .compareNeedsTwoDescription: return "Dans la grille, utilisez Command ou Maj pour choisir les photos à comparer."
            case .surveyNeedsSelectionTitle: return "Sélectionnez des photos"
            case .surveyNeedsSelectionDescription: return "Sélectionnez plusieurs photos dans la grille pour les examiner ensemble."
            }
        case .german:
            switch key {
            case .grid: return "Raster"
            case .compare: return "Vergleichen"
            case .survey: return "Übersicht"
            case .reference: return "Referenz"
            case .candidate: return "Kandidat"
            case .compareNeedsTwoTitle: return "Zwei Fotos auswählen"
            case .compareNeedsTwoDescription: return "Im Raster mit Command oder Umschalt die zu vergleichenden Fotos auswählen."
            case .surveyNeedsSelectionTitle: return "Fotos auswählen"
            case .surveyNeedsSelectionDescription: return "Mehrere Fotos im Raster auswählen, um sie gemeinsam zu betrachten."
            }
        }
    }

    private static func englishCullingText(_ key: AppCullingText) -> String {
        switch key {
        case .grid: return "Grid"
        case .compare: return "Compare"
        case .survey: return "Survey"
        case .reference: return "Select"
        case .candidate: return "Candidate"
        case .compareNeedsTwoTitle: return "Select two photos"
        case .compareNeedsTwoDescription: return "In Grid, Command-click or Shift-click the photos to compare."
        case .surveyNeedsSelectionTitle: return "Select photos"
        case .surveyNeedsSelectionDescription: return "Select multiple photos in Grid to review them together."
        }
    }
}

extension AppModel {
    func cullingText(_ key: AppCullingText) -> String {
        AppLocalization.cullingText(key, language: appLanguage)
    }
}
