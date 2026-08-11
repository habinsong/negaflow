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
            case .unverifiedFilm: return "IR clean skipped: B&W film carries a silver image that blocks infrared"
            case .alignmentUnreliable: return "IR clean aborted: RGB and infrared alignment could not be verified"
            case .unavailableForFilmHelp: return "Infrared correction works on colour film, negative and slide alike, because their dye image passes infrared. B&W film is a silver image that blocks it, so the correction is unavailable"
            }
        case .korean:
            switch key {
            case .unverifiedFilm: return "IR 결함 제거 건너뜀: 흑백 필름은 화상이 은입자라 적외선이 통과하지 않습니다"
            case .alignmentUnreliable: return "IR 결함 제거 중단: RGB와 적외선 채널 정렬을 확인할 수 없습니다"
            case .unavailableForFilmHelp: return "적외선 보정은 컬러 필름이면 네거티브·슬라이드 모두 됩니다. 화상이 색소라 적외선이 통과하기 때문입니다. 흑백 필름은 화상이 은입자라 적외선을 막으므로 쓸 수 없습니다"
            }
        case .japanese:
            switch key {
            case .unverifiedFilm: return "IR クリーニングをスキップ: 白黒フィルムは画像が銀粒子なので赤外線を通しません"
            case .alignmentUnreliable: return "IR クリーニングを中止: RGB と赤外線チャンネルの位置合わせを確認できません"
            case .unavailableForFilmHelp: return "赤外線補正はカラーフィルムならネガもスライドも使えます。画像が色素なので赤外線を通すためです。白黒フィルムは画像が銀粒子で赤外線を遮るため使えません"
            }
        case .simplifiedChinese:
            switch key {
            case .unverifiedFilm: return "已跳过 IR 除尘：黑白胶片的影像由银粒构成，会阻挡红外线"
            case .alignmentUnreliable: return "已中止 IR 除尘：无法验证 RGB 与红外通道的对齐"
            case .unavailableForFilmHelp: return "红外校正适用于所有彩色胶片，负片和反转片皆可，因为其影像由染料构成，可透过红外线。黑白胶片的影像为银粒，会阻挡红外线，因此无法使用"
            }
        case .french:
            switch key {
            case .unverifiedFilm: return "Nettoyage IR ignoré : le film N&B porte une image argentique qui bloque l’infrarouge"
            case .alignmentUnreliable: return "Nettoyage IR interrompu : impossible de vérifier l’alignement RVB et infrarouge"
            case .unavailableForFilmHelp: return "La correction infrarouge fonctionne sur tout film couleur, négatif comme diapositive, car leur image de colorants laisse passer l’infrarouge. Le film N&B porte une image argentique qui le bloque"
            }
        case .german:
            switch key {
            case .unverifiedFilm: return "IR-Reinigung übersprungen: S/W-Film trägt ein Silberbild, das Infrarot blockiert"
            case .alignmentUnreliable: return "IR-Reinigung abgebrochen: RGB- und Infrarotkanal konnten nicht verlässlich ausgerichtet werden"
            case .unavailableForFilmHelp: return "Die Infrarotkorrektur funktioniert bei jedem Farbfilm, Negativ wie Dia, denn ihr Farbstoffbild lässt Infrarot durch. S/W-Film trägt ein Silberbild, das es blockiert"
            }
        }
    }
}

extension AppModel {
    func infraredText(_ key: AppInfraredText) -> String {
        AppLocalization.infraredText(key, language: appLanguage)
    }
}
