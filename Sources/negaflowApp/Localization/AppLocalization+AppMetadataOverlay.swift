import Foundation

enum AppMetadataOverlayLocalizedText {
    case title, fieldTitle, caption, keywords, copyright, save, applySelection, conflict, resolve
    case filmShot, cameraMake, cameraModel, lensModel, filmStock, isoSpeed, shutterSpeed
    case aperture, focalLength

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            ["App Metadata", "Title", "Caption", "Keywords", "Copyright", "Save", "Apply to Selection", "Source Changed", "Use Current Source",
             "Shot Details", "Camera Make", "Camera", "Lens", "Film", "ISO", "Shutter (1/125)", "Aperture (f/2.8)", "Focal Length (mm)"][index]
        case .korean:
            ["앱 메타데이터", "제목", "설명", "키워드", "저작권", "저장", "선택 항목에 적용", "원본 메타데이터 변경", "현재 원본 기준으로 갱신",
             "촬영 기록", "카메라 제조사", "카메라", "렌즈", "필름", "ISO", "셔터 (1/125)", "조리개 (f/2.8)", "초점 거리 (mm)"][index]
        case .japanese:
            ["アプリメタデータ", "タイトル", "説明", "キーワード", "著作権", "保存", "選択項目に適用", "ソースが変更されました", "現在のソースを使用",
             "撮影記録", "カメラメーカー", "カメラ", "レンズ", "フィルム", "ISO", "シャッター (1/125)", "絞り (f/2.8)", "焦点距離 (mm)"][index]
        case .simplifiedChinese:
            ["应用元数据", "标题", "说明", "关键词", "版权", "存储", "应用到所选项目", "来源已更改", "使用当前来源",
             "拍摄记录", "相机厂商", "相机", "镜头", "胶片", "ISO", "快门 (1/125)", "光圈 (f/2.8)", "焦距 (mm)"][index]
        case .french:
            ["Métadonnées de l’app", "Titre", "Légende", "Mots-clés", "Droits", "Enregistrer", "Appliquer à la sélection", "Source modifiée", "Utiliser la source actuelle",
             "Prise de vue", "Fabricant", "Appareil", "Objectif", "Film", "ISO", "Vitesse (1/125)", "Ouverture (f/2,8)", "Focale (mm)"][index]
        case .german:
            ["App-Metadaten", "Titel", "Beschreibung", "Stichwörter", "Urheberrecht", "Sichern", "Auf Auswahl anwenden", "Quelle geändert", "Aktuelle Quelle verwenden",
             "Aufnahmedaten", "Hersteller", "Kamera", "Objektiv", "Film", "ISO", "Verschluss (1/125)", "Blende (f/2,8)", "Brennweite (mm)"][index]
        }
    }

    private var index: Int {
        switch self {
        case .title: 0; case .fieldTitle: 1; case .caption: 2; case .keywords: 3
        case .copyright: 4; case .save: 5; case .applySelection: 6; case .conflict: 7; case .resolve: 8
        case .filmShot: 9; case .cameraMake: 10; case .cameraModel: 11; case .lensModel: 12
        case .filmStock: 13; case .isoSpeed: 14; case .shutterSpeed: 15; case .aperture: 16
        case .focalLength: 17
        }
    }
}
