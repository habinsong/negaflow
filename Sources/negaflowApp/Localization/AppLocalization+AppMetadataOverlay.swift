import Foundation

enum AppMetadataOverlayLocalizedText {
    case title, fieldTitle, caption, keywords, copyright, saved, applySelection, conflict, resolve
    case filmShot, cameraMake, cameraModel, lensModel, filmStock, isoSpeed, shutterSpeed
    case aperture, focalLength, pendingSave, notEditable
    case rollRecord, rollCode, rollNotes, rollFillHint, rollFilled
    case rollMissing, rollCreateFromSelection

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            ["App Metadata", "Title", "Caption", "Keywords", "Copyright", "Saved", "Apply to Selection", "Source Changed", "Use Current Source",
             "Shot Details", "Camera Make", "Camera", "Lens", "Film", "ISO", "Shutter (1/125)", "Aperture (f/2.8)", "Focal Length (mm)",
             "Saving…", "Read-only frame",
             "Roll Record", "Roll Code", "Notes", "Fills empty fields on this roll", "Filled frames:",
             "This frame is not in a roll yet.", "Create a roll from the selection"][index]
        case .korean:
            ["앱 메타데이터", "제목", "설명", "키워드", "저작권", "저장됨", "선택 항목에 적용", "원본 메타데이터 변경", "현재 원본 기준으로 갱신",
             "촬영 기록", "카메라 제조사", "카메라", "렌즈", "필름", "ISO", "셔터 (1/125)", "조리개 (f/2.8)", "초점 거리 (mm)",
             "저장 중…", "저장할 수 없는 프레임",
             "롤 기록", "롤 코드", "메모", "이 롤의 빈 칸을 채웁니다", "채운 프레임:",
             "이 프레임은 아직 롤에 속해 있지 않습니다.", "선택 항목으로 롤 만들기"][index]
        case .japanese:
            ["アプリメタデータ", "タイトル", "説明", "キーワード", "著作権", "保存済み", "選択項目に適用", "ソースが変更されました", "現在のソースを使用",
             "撮影記録", "カメラメーカー", "カメラ", "レンズ", "フィルム", "ISO", "シャッター (1/125)", "絞り (f/2.8)", "焦点距離 (mm)",
             "保存中…", "保存できないコマ",
             "ロール記録", "ロールコード", "メモ", "このロールの空欄を埋めます", "埋めたコマ:",
             "このコマはまだロールに属していません。", "選択項目でロールを作成"][index]
        case .simplifiedChinese:
            ["应用元数据", "标题", "说明", "关键词", "版权", "已存储", "应用到所选项目", "来源已更改", "使用当前来源",
             "拍摄记录", "相机厂商", "相机", "镜头", "胶片", "ISO", "快门 (1/125)", "光圈 (f/2.8)", "焦距 (mm)",
             "正在存储…", "无法存储的画幅",
             "胶卷记录", "胶卷编号", "备注", "填充该胶卷的空白项", "已填充画幅：",
             "该画幅尚未归入任何胶卷。", "用所选项目创建胶卷"][index]
        case .french:
            ["Métadonnées de l’app", "Titre", "Légende", "Mots-clés", "Droits", "Enregistré", "Appliquer à la sélection", "Source modifiée", "Utiliser la source actuelle",
             "Prise de vue", "Fabricant", "Appareil", "Objectif", "Film", "ISO", "Vitesse (1/125)", "Ouverture (f/2,8)", "Focale (mm)",
             "Enregistrement…", "Vue non modifiable",
             "Fiche de pellicule", "Code de pellicule", "Notes", "Remplit les champs vides de cette pellicule", "Vues remplies :",
             "Cette vue n’appartient encore à aucune pellicule.", "Créer une pellicule avec la sélection"][index]
        case .german:
            ["App-Metadaten", "Titel", "Beschreibung", "Stichwörter", "Urheberrecht", "Gesichert", "Auf Auswahl anwenden", "Quelle geändert", "Aktuelle Quelle verwenden",
             "Aufnahmedaten", "Hersteller", "Kamera", "Objektiv", "Film", "ISO", "Verschluss (1/125)", "Blende (f/2,8)", "Brennweite (mm)",
             "Wird gesichert…", "Nicht änderbares Bild",
             "Filmnotiz", "Filmcode", "Notizen", "Füllt leere Felder dieses Films", "Gefüllte Bilder:",
             "Dieses Bild gehört noch zu keinem Film.", "Film aus der Auswahl erstellen"][index]
        }
    }

    private var index: Int {
        switch self {
        case .title: 0; case .fieldTitle: 1; case .caption: 2; case .keywords: 3
        case .copyright: 4; case .saved: 5; case .applySelection: 6; case .conflict: 7; case .resolve: 8
        case .filmShot: 9; case .cameraMake: 10; case .cameraModel: 11; case .lensModel: 12
        case .filmStock: 13; case .isoSpeed: 14; case .shutterSpeed: 15; case .aperture: 16
        case .focalLength: 17; case .pendingSave: 18; case .notEditable: 19
        case .rollRecord: 20; case .rollCode: 21; case .rollNotes: 22
        case .rollFillHint: 23; case .rollFilled: 24
        case .rollMissing: 25; case .rollCreateFromSelection: 26
        }
    }
}
