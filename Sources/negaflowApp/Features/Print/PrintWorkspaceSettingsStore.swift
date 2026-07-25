import Chromabase
import Combine
import Foundation

enum PrintWorkspaceLayoutMode: String, CaseIterable, Codable, Sendable {
    case singleImage
    case contactSheet
    case picturePackage
    case customPackage

    var packageMode: PrintPackageLayoutMode? {
        switch self {
        case .singleImage: nil
        case .contactSheet: .contactSheet
        case .picturePackage: .picturePackage
        case .customPackage: .customPackage
        }
    }
}

@MainActor
final class PrintWorkspaceSettingsStore: ObservableObject {
    private enum Keys {
        static let paperSize = "print.paperSize"
        static let orientation = "print.orientation"
        static let marginMM = "print.marginMM"
        static let perforationStyle = "print.perforationStyle"
        static let layoutMode = "print.layoutMode"
        static let packageSettings = "print.packageSettings"
    }

    private let defaults: UserDefaults

    @Published var paperSize: PrintPaperSize {
        didSet { defaults.set(paperSize.rawValue, forKey: Keys.paperSize) }
    }

    @Published var orientation: PrintPaperOrientation {
        didSet { defaults.set(orientation.rawValue, forKey: Keys.orientation) }
    }

    @Published var marginMM: Double {
        didSet {
            let normalized = Self.normalizedMargin(marginMM)
            if normalized != marginMM {
                marginMM = normalized
            } else {
                defaults.set(normalized, forKey: Keys.marginMM)
            }
        }
    }

    @Published var perforationStyle: PrintPerforationStyle {
        didSet { defaults.set(perforationStyle.rawValue, forKey: Keys.perforationStyle) }
    }

    @Published var layoutMode: PrintWorkspaceLayoutMode {
        didSet { defaults.set(layoutMode.rawValue, forKey: Keys.layoutMode) }
    }

    @Published var packageSettings: PrintPackageSettings {
        didSet {
            guard packageSettings.isValid,
                  let data = try? JSONEncoder().encode(packageSettings) else { return }
            defaults.set(data, forKey: Keys.packageSettings)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paperSize = defaults.string(forKey: Keys.paperSize)
            .flatMap(PrintPaperSize.init(rawValue:)) ?? .a4
        orientation = defaults.string(forKey: Keys.orientation)
            .flatMap(PrintPaperOrientation.init(rawValue:)) ?? .automatic
        let storedMargin = defaults.object(forKey: Keys.marginMM) as? Double
        marginMM = Self.normalizedMargin(storedMargin ?? 10)
        perforationStyle = defaults.string(forKey: Keys.perforationStyle)
            .flatMap(PrintPerforationStyle.init(rawValue:)) ?? .none
        layoutMode = defaults.string(forKey: Keys.layoutMode)
            .flatMap(PrintWorkspaceLayoutMode.init(rawValue:)) ?? .singleImage
        if let data = defaults.data(forKey: Keys.packageSettings),
           let decoded = try? JSONDecoder().decode(PrintPackageSettings.self, from: data),
           decoded.isValid {
            packageSettings = decoded
        } else {
            packageSettings = PrintPackageSettings()
        }
    }

    func compositionSettings(dpi: Int) -> PrintCompositionSettings {
        PrintCompositionSettings(
            paperSize: paperSize,
            orientation: orientation,
            marginMM: marginMM,
            dpi: dpi > 0 ? dpi : 300,
            perforationStyle: perforationStyle
        )
    }

    func effectivePackageSettings(sourceCount: Int? = nil) -> PrintPackageSettings? {
        guard let mode = layoutMode.packageMode else { return nil }
        var result = packageSettings
        result.mode = mode
        if mode == .customPackage, let sourceCount, sourceCount > 0 {
            let maximumSourceIndex = sourceCount - 1
            for index in result.customItems.indices {
                result.customItems[index].sourceIndex = min(
                    result.customItems[index].sourceIndex,
                    maximumSourceIndex
                )
            }
        }
        return result.isValid ? result : nil
    }

    func apply(_ settings: PrintLayoutTemplateSettings) {
        guard settings.isValid else { return }
        paperSize = settings.paperSize
        orientation = settings.orientation
        marginMM = settings.marginMM
        perforationStyle = settings.perforationStyle
        layoutMode = settings.layoutMode
        packageSettings = settings.packageSettings
    }

    func templateSettings() -> PrintLayoutTemplateSettings {
        PrintLayoutTemplateSettings(
            paperSize: paperSize,
            orientation: orientation,
            marginMM: marginMM,
            perforationStyle: perforationStyle,
            layoutMode: layoutMode,
            packageSettings: packageSettings
        )
    }

    private static func normalizedMargin(_ value: Double) -> Double {
        guard value.isFinite else { return 10 }
        return min(max(value, 0), 50)
    }
}
