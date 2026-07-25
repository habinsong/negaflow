import Foundation

enum PixelSamplerLocalizedText {
    case original, working, proof, sourcePixel, movePointer, enabled

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            ["Original", "Working", "Proof", "Source Pixel", "Move the pointer over the photo", "Pixel sampler"][index]
        case .korean:
            ["원본", "작업", "프루프", "원본 픽셀", "사진 위로 포인터를 이동하세요", "픽셀 샘플러"][index]
        case .japanese:
            ["オリジナル", "作業", "校正", "ソースピクセル", "写真上にポインタを移動", "ピクセルサンプラー"][index]
        case .simplifiedChinese:
            ["原始", "工作", "打样", "源像素", "将指针移到照片上", "像素取样器"][index]
        case .french:
            ["Original", "Travail", "Épreuve", "Pixel source", "Placez le pointeur sur la photo", "Échantillonneur de pixels"][index]
        case .german:
            ["Original", "Arbeitsfarbraum", "Proof", "Quellpixel", "Zeiger über das Foto bewegen", "Pixel-Sampler"][index]
        }
    }

    private var index: Int {
        switch self {
        case .original: 0; case .working: 1; case .proof: 2
        case .sourcePixel: 3; case .movePointer: 4; case .enabled: 5
        }
    }
}
