import SwiftUI

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum CanvasBackground: String, CaseIterable, Identifiable {
    case black, gray, white

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .black: return Color(white: 0.07)
        case .gray:  return Color(white: 0.5)
        case .white: return Color(white: 0.97)
        }
    }

    var hudColorScheme: ColorScheme {
        switch self {
        case .black: return .dark
        case .gray, .white: return .light
        }
    }

    /// 캔버스 위 컨트롤(비교 토글·줌 캡슐)의 글자/아이콘 색. 앱 외형(라이트/다크/자동)이 아니라
    /// **캔버스 배경의 반대색**으로 고정한다 — 다크 모드에서 흰 배경을 고르면 흰 글자가 흰
    /// 바탕에 얹혀 컨트롤이 통째로 사라졌다.
    var hudContentColor: Color {
        switch self {
        case .black, .gray: return Color(white: 0.97)
        case .white: return Color(white: 0.12)
        }
    }

    /// 컨트롤 판 색. 글래스가 아니라 배경에서 한 단 들린 **불투명 면**이라 배경이 무엇이든
    /// 캡슐 경계가 그대로 보인다.
    var hudSurfaceColor: Color {
        switch self {
        case .black: return Color(white: 0.20)
        case .gray:  return Color(white: 0.30)
        case .white: return Color(white: 0.86)
        }
    }

    var label: String {
        label(language: .system)
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .black: return AppLocalization.text(.canvasBackgroundBlack, language: language)
        case .gray: return AppLocalization.text(.canvasBackgroundGray, language: language)
        case .white: return AppLocalization.text(.canvasBackgroundWhite, language: language)
        }
    }
}
