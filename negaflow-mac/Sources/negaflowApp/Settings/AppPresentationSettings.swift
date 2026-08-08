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
