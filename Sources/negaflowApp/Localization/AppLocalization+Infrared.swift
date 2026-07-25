import Foundation

enum AppInfraredText {
    case unverifiedFilm
    case alignmentUnreliable
    case unavailableForFilmHelp
}

extension AppLocalization {
    static func infraredText(_ key: AppInfraredText, language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch key {
            case .unverifiedFilm: return "IR clean skipped: the film material is not verified for infrared correction"
            case .alignmentUnreliable: return "IR clean aborted: RGB and infrared alignment could not be verified"
            case .unavailableForFilmHelp: return "Automatic IR correction is enabled only for color negatives; B&W material and unidentified slides require a verified film process"
            }
        case .korean:
            switch key {
            case .unverifiedFilm: return "IR 결함 제거 건너뜀: 적외선 보정에 적합한 필름 재질인지 확인되지 않았습니다"
            case .alignmentUnreliable: return "IR 결함 제거 중단: RGB와 적외선 채널 정렬을 확인할 수 없습니다"
            case .unavailableForFilmHelp: return "자동 IR 보정은 컬러 네거티브만 허용합니다. 흑백 필름과 종류가 확인되지 않은 슬라이드는 필름 공정 확인이 필요합니다"
            }
        case .japanese:
            switch key {
            case .unverifiedFilm: return "IR クリーニングをスキップ: 赤外線補正に適したフィルム素材か確認できません"
            case .alignmentUnreliable: return "IR クリーニングを中止: RGB と赤外線チャンネルの位置合わせを確認できません"
            case .unavailableForFilmHelp: return "自動 IR 補正はカラーネガのみ有効です。白黒フィルムと種類未確認のスライドには現像方式の確認が必要です"
            }
        case .simplifiedChinese:
            switch key {
            case .unverifiedFilm: return "已跳过 IR 除尘：无法确认胶片材料是否适合红外校正"
            case .alignmentUnreliable: return "已中止 IR 除尘：无法验证 RGB 与红外通道的对齐"
            case .unavailableForFilmHelp: return "自动 IR 校正仅适用于彩色负片；黑白胶片和类型未确认的幻灯片需要先确认胶片工艺"
            }
        case .french:
            switch key {
            case .unverifiedFilm: return "Nettoyage IR ignoré : le matériau du film n’est pas validé pour la correction infrarouge"
            case .alignmentUnreliable: return "Nettoyage IR interrompu : impossible de vérifier l’alignement RVB et infrarouge"
            case .unavailableForFilmHelp: return "La correction IR automatique est réservée aux négatifs couleur ; les films N&B et diapositives non identifiées exigent un procédé vérifié"
            }
        case .german:
            switch key {
            case .unverifiedFilm: return "IR-Reinigung übersprungen: Das Filmmaterial ist nicht für die Infrarotkorrektur bestätigt"
            case .alignmentUnreliable: return "IR-Reinigung abgebrochen: RGB- und Infrarotkanal konnten nicht verlässlich ausgerichtet werden"
            case .unavailableForFilmHelp: return "Automatische IR-Korrektur ist nur für Farbnegative aktiv; S/W-Material und unbekannte Dias benötigen einen bestätigten Filmprozess"
            }
        }
    }
}

extension AppModel {
    func infraredText(_ key: AppInfraredText) -> String {
        AppLocalization.infraredText(key, language: appLanguage)
    }
}
