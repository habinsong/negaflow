import Foundation

enum AppSettingsTab: String, CaseIterable {
    case general
    case interface
    case workflow
    case scan
    case disk
    case export
    case shortcuts
    case legal

    static let defaultsKey = "settings.selectedTab"

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .interface: "sidebar.left"
        case .workflow: "rectangle.stack"
        case .scan: "scanner"
        case .disk: "externaldrive"
        case .export: "square.and.arrow.up"
        case .shortcuts: "keyboard"
        case .legal: "doc.text.magnifyingglass"
        }
    }
}
