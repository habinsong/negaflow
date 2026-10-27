import Foundation

enum PrintWatermarkLocalizedText {
    case section
    case enabled
    case background
    case white
    case black
    case blur
    case textColor
    case histogramColor
    case topBand
    case bandHeight
    case camera
    case lens
    case logo
    case logoFile
    case chooseLogo
    case removeLogo
    case logoUnreadable
    case logoMissing
    case focalLength
    case aperture
    case shutter
    case iso
    case captureDate
    case histogram
    case userName
    case placement
    case bottomCenter
    case topLeading
    case topCenter
    case topTrailing
    case singleImageOnly

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .section: "Watermark"
            case .enabled: "Watermark"
            case .background: "Background"
            case .white: "White"
            case .black: "Black"
            case .blur: "Blur"
            case .textColor: "Text Color"
            case .histogramColor: "Histogram Color"
            case .topBand: "Top Border"
            case .bandHeight: "Border Height"
            case .camera: "Camera"
            case .lens: "Lens"
            case .logo: "Logo"
            case .logoFile: "Logo File"
            case .chooseLogo: "Choose Image"
            case .removeLogo: "Use negaflow Logo"
            case .logoUnreadable: "This image can't be used as a logo."
            case .logoMissing: "Logo file not found:"
            case .focalLength: "Focal Length"
            case .aperture: "Aperture"
            case .shutter: "Shutter"
            case .iso: "ISO"
            case .captureDate: "Date"
            case .histogram: "Histogram"
            case .userName: "Name"
            case .placement: "Position"
            case .bottomCenter: "Bottom Center"
            case .topLeading: "Top Left"
            case .topCenter: "Top Center"
            case .topTrailing: "Top Right"
            case .singleImageOnly: "Watermarks apply to layouts with one photo per page."
            }
        case .korean:
            switch self {
            case .section: "워터마크"
            case .enabled: "워터마크"
            case .background: "배경"
            case .white: "흰색"
            case .black: "검정"
            case .blur: "블러"
            case .textColor: "글자색"
            case .histogramColor: "히스토그램 색"
            case .topBand: "위쪽 여백"
            case .bandHeight: "여백 높이"
            case .camera: "카메라"
            case .lens: "렌즈"
            case .logo: "로고"
            case .logoFile: "로고 파일"
            case .chooseLogo: "이미지 선택"
            case .removeLogo: "negaflow 로고로 되돌리기"
            case .logoUnreadable: "이 이미지는 로고로 쓸 수 없습니다."
            case .logoMissing: "로고 파일을 찾을 수 없습니다:"
            case .focalLength: "초점거리"
            case .aperture: "조리개"
            case .shutter: "셔터"
            case .iso: "ISO"
            case .captureDate: "날짜"
            case .histogram: "히스토그램"
            case .userName: "이름"
            case .placement: "위치"
            case .bottomCenter: "하단 중앙"
            case .topLeading: "상단 좌측"
            case .topCenter: "상단 중앙"
            case .topTrailing: "상단 우측"
            case .singleImageOnly: "워터마크는 한 장에 사진 한 장을 놓는 레이아웃에만 들어갑니다."
            }
        case .japanese:
            switch self {
            case .section: "ウォーターマーク"
            case .enabled: "ウォーターマーク"
            case .background: "背景"
            case .white: "白"
            case .black: "黒"
            case .blur: "ぼかし"
            case .textColor: "文字色"
            case .histogramColor: "ヒストグラムの色"
            case .topBand: "上の余白"
            case .bandHeight: "余白の高さ"
            case .camera: "カメラ"
            case .lens: "レンズ"
            case .logo: "ロゴ"
            case .logoFile: "ロゴファイル"
            case .chooseLogo: "画像を選択"
            case .removeLogo: "negaflow のロゴに戻す"
            case .logoUnreadable: "この画像はロゴに使えません。"
            case .logoMissing: "ロゴのファイルが見つかりません:"
            case .focalLength: "焦点距離"
            case .aperture: "絞り"
            case .shutter: "シャッター"
            case .iso: "ISO"
            case .captureDate: "日付"
            case .histogram: "ヒストグラム"
            case .userName: "名前"
            case .placement: "位置"
            case .bottomCenter: "下中央"
            case .topLeading: "上左"
            case .topCenter: "上中央"
            case .topTrailing: "上右"
            case .singleImageOnly: "ウォーターマークは 1 枚に写真 1 枚のレイアウトだけに入ります。"
            }
        case .simplifiedChinese:
            switch self {
            case .section: "水印"
            case .enabled: "水印"
            case .background: "背景"
            case .white: "白色"
            case .black: "黑色"
            case .blur: "模糊"
            case .textColor: "文字颜色"
            case .histogramColor: "直方图颜色"
            case .topBand: "顶部留白"
            case .bandHeight: "留白高度"
            case .camera: "相机"
            case .lens: "镜头"
            case .logo: "标志"
            case .logoFile: "标志文件"
            case .chooseLogo: "选择图像"
            case .removeLogo: "改用 negaflow 标志"
            case .logoUnreadable: "此图像无法用作标志。"
            case .logoMissing: "找不到标志文件："
            case .focalLength: "焦距"
            case .aperture: "光圈"
            case .shutter: "快门"
            case .iso: "ISO"
            case .captureDate: "日期"
            case .histogram: "直方图"
            case .userName: "名字"
            case .placement: "位置"
            case .bottomCenter: "底部居中"
            case .topLeading: "顶部左侧"
            case .topCenter: "顶部居中"
            case .topTrailing: "顶部右侧"
            case .singleImageOnly: "水印只用于一页放一张照片的布局。"
            }
        case .french:
            switch self {
            case .section: "Filigrane"
            case .enabled: "Filigrane"
            case .background: "Fond"
            case .white: "Blanc"
            case .black: "Noir"
            case .blur: "Flou"
            case .textColor: "Couleur du texte"
            case .histogramColor: "Couleur de l’histogramme"
            case .topBand: "Bordure du haut"
            case .bandHeight: "Hauteur de bordure"
            case .camera: "Appareil"
            case .lens: "Objectif"
            case .logo: "Logo"
            case .logoFile: "Fichier du logo"
            case .chooseLogo: "Choisir une image"
            case .removeLogo: "Revenir au logo negaflow"
            case .logoUnreadable: "Cette image ne peut pas servir de logo."
            case .logoMissing: "Fichier du logo introuvable :"
            case .focalLength: "Focale"
            case .aperture: "Ouverture"
            case .shutter: "Vitesse"
            case .iso: "ISO"
            case .captureDate: "Date"
            case .histogram: "Histogramme"
            case .userName: "Nom"
            case .placement: "Position"
            case .bottomCenter: "En bas au centre"
            case .topLeading: "En haut à gauche"
            case .topCenter: "En haut au centre"
            case .topTrailing: "En haut à droite"
            case .singleImageOnly: "Le filigrane s’applique aux mises en page d’une photo par feuille."
            }
        case .german:
            switch self {
            case .section: "Wasserzeichen"
            case .enabled: "Wasserzeichen"
            case .background: "Hintergrund"
            case .white: "Weiß"
            case .black: "Schwarz"
            case .blur: "Unschärfe"
            case .textColor: "Schriftfarbe"
            case .histogramColor: "Histogrammfarbe"
            case .topBand: "Rand oben"
            case .bandHeight: "Randhöhe"
            case .camera: "Kamera"
            case .lens: "Objektiv"
            case .logo: "Logo"
            case .logoFile: "Logodatei"
            case .chooseLogo: "Bild wählen"
            case .removeLogo: "negaflow-Logo verwenden"
            case .logoUnreadable: "Dieses Bild lässt sich nicht als Logo verwenden."
            case .logoMissing: "Logodatei nicht gefunden:"
            case .focalLength: "Brennweite"
            case .aperture: "Blende"
            case .shutter: "Verschluss"
            case .iso: "ISO"
            case .captureDate: "Datum"
            case .histogram: "Histogramm"
            case .userName: "Name"
            case .placement: "Position"
            case .bottomCenter: "Unten Mitte"
            case .topLeading: "Oben links"
            case .topCenter: "Oben Mitte"
            case .topTrailing: "Oben rechts"
            case .singleImageOnly: "Wasserzeichen gelten für Layouts mit einem Foto pro Seite."
            }
        }
    }
}
