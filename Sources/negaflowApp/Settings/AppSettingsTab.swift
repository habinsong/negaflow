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
}
