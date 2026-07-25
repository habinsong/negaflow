import Foundation

enum OutputSharpeningLocalizedText {
    case amount
    case medium
    case screen
    case mattePaper
    case glossyPaper

    func resolved(language: AppLanguage) -> String {
        switch language.resolved {
        case .system, .english:
            switch self {
            case .amount: "Output Sharpening"
            case .medium: "Sharpen For"
            case .screen: "Screen"
            case .mattePaper: "Matte Paper"
            case .glossyPaper: "Glossy Paper"
            }
        case .korean:
            switch self {
            case .amount: "출력 선명도"
            case .medium: "출력 매체"
            case .screen: "화면"
            case .mattePaper: "무광 용지"
            case .glossyPaper: "광택 용지"
            }
        case .japanese:
            switch self {
            case .amount: "出力シャープ"
            case .medium: "出力媒体"
            case .screen: "画面"
            case .mattePaper: "マット紙"
            case .glossyPaper: "光沢紙"
            }
        case .simplifiedChinese:
            switch self {
            case .amount: "输出锐化"
            case .medium: "输出介质"
            case .screen: "屏幕"
            case .mattePaper: "哑光纸"
            case .glossyPaper: "光面纸"
            }
        case .french:
            switch self {
            case .amount: "Netteté de sortie"
            case .medium: "Support de sortie"
            case .screen: "Écran"
            case .mattePaper: "Papier mat"
            case .glossyPaper: "Papier brillant"
            }
        case .german:
            switch self {
            case .amount: "Ausgabeschärfung"
            case .medium: "Ausgabemedium"
            case .screen: "Bildschirm"
            case .mattePaper: "Mattes Papier"
            case .glossyPaper: "Glanzpapier"
            }
        }
    }
}
