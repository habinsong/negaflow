import Foundation

struct AppLaunchConfiguration: Equatable {
    private enum EnvironmentKey {
        static let uiTestMode = "NEGAFLOW_UI_TEST_MODE"
        static let uiTestRoot = "NEGAFLOW_UI_TEST_ROOT"
        static let importSyntheticNegative = "NEGAFLOW_UI_TEST_IMPORT_SYNTHETIC"
        static let demoScanner = "NEGAFLOW_UI_TEST_DEMO"
        static let corruptCatalog = "NEGAFLOW_UI_TEST_CORRUPT_CATALOG"
        static let dropTargetFolder = "NEGAFLOW_UI_TEST_DROP_FOLDER"
        static let developImportsAutomatically = "NEGAFLOW_UI_TEST_AUTO_DEVELOP"
        static let selectAllFrames = "NEGAFLOW_UI_TEST_SELECT_ALL"
        static let libraryMaintenance = "NEGAFLOW_UI_TEST_MAINTENANCE"
    }

    /// 진단 패널의 두 단추와 같은 일을 시작하자마자 한 번 한다. 종료·재실행 경로를 사람 손 없이
    /// 끝까지 시험하기 위한 것이다.
    enum LibraryMaintenance: String, Equatable {
        case repair
        case reinstall
    }

    let uiTestRoot: URL
    let importsSyntheticNegative: Bool
    let enablesDemoScanner: Bool
    let preparesCorruptCatalog: Bool
    let createsDropTargetFolder: Bool
    let developsImportsAutomatically: Bool
    let selectsAllFrames: Bool
    var libraryMaintenance: LibraryMaintenance? = nil

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
            createsDropTargetFolder: environment[EnvironmentKey.dropTargetFolder] == "1",
            developsImportsAutomatically:
                environment[EnvironmentKey.developImportsAutomatically] == "1",
            selectsAllFrames: environment[EnvironmentKey.selectAllFrames] == "1",
            libraryMaintenance: environment[EnvironmentKey.libraryMaintenance]
                .flatMap(LibraryMaintenance.init(rawValue:))
        )
    }

    /// 재실행한 앱이 받을 환경. `open` 은 부른 쪽의 환경을 새 앱에 그대로 넘기므로 격리 루트는
    /// 그대로 이어진다. 한 번만 할 유지보수 지시는 뺀다 — 남기면 재실행할 때마다 다시 돌아
    /// 끝나지 않는다.
    static func relaunchEnvironment(
        from environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        environment.filter { $0.key != EnvironmentKey.libraryMaintenance }
    }
}
