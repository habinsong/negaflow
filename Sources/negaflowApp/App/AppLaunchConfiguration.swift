import Foundation

struct AppLaunchConfiguration: Equatable {
    private enum EnvironmentKey {
        static let uiTestMode = "NEGAFLOW_UI_TEST_MODE"
        static let uiTestRoot = "NEGAFLOW_UI_TEST_ROOT"
        static let importSyntheticNegative = "NEGAFLOW_UI_TEST_IMPORT_SYNTHETIC"
        static let demoScanner = "NEGAFLOW_UI_TEST_DEMO"
        static let corruptCatalog = "NEGAFLOW_UI_TEST_CORRUPT_CATALOG"
        static let dropTargetFolder = "NEGAFLOW_UI_TEST_DROP_FOLDER"
    }

    let uiTestRoot: URL
    let importsSyntheticNegative: Bool
    let enablesDemoScanner: Bool
    let preparesCorruptCatalog: Bool
    let createsDropTargetFolder: Bool

    static let current = from(environment: ProcessInfo.processInfo.environment)

    static func from(environment: [String: String]) -> AppLaunchConfiguration? {
        guard environment[EnvironmentKey.uiTestMode] == "1",
              let rawRoot = environment[EnvironmentKey.uiTestRoot],
              rawRoot.hasPrefix("/") else {
            return nil
        }
        return AppLaunchConfiguration(
            uiTestRoot: URL(fileURLWithPath: rawRoot, isDirectory: true).standardizedFileURL,
            importsSyntheticNegative: environment[EnvironmentKey.importSyntheticNegative] == "1",
            enablesDemoScanner: environment[EnvironmentKey.demoScanner] == "1",
            preparesCorruptCatalog: environment[EnvironmentKey.corruptCatalog] == "1",
            createsDropTargetFolder: environment[EnvironmentKey.dropTargetFolder] == "1"
        )
    }
}
