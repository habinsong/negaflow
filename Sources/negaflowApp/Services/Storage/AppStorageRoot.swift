import Foundation

/// 앱이 기본 저장 위치를 물어보는 단 한 곳.
///
/// 카탈로그·결함 사이드카·export 저널·cleaned raw 캐시는 각자 Application Support 와 Caches
/// 경로를 직접 만들어 썼다. 그래서 테스트가 경로를 주입하지 않고 `AppModel()` 을 만들면 사용자의
/// 실제 라이브러리를 열고 썼고, `swift test --parallel` 로 프로세스를 나누면 서로의 파일을 밟았다.
///
/// 테스트 프로세스에서는 그 밑동을 프로세스마다 다른 임시 폴더로 돌린다. 뒤에 붙는 경로 구성은
/// 그대로라 각 저장소의 상대 구조와 파일 이름은 실제 실행과 같다.
enum AppStorageRoot {
    static func applicationSupport(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support", isDirectory: true
            )
        return isolatedBase(named: "Application Support") ?? base
    }

    /// 이 프로세스의 저장 위치가 테스트용으로 갈라져 있는지. 사용자 설정으로 기본 경로를
    /// 덮어쓰는 저장소는 이 값이 참일 때 그 설정을 무시해야 격리가 뚫리지 않는다.
    static var isolatesTestProcess: Bool { testProcessRoot != nil }

    static func caches(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return isolatedBase(named: "Caches") ?? base
    }

    /// XCTest 가 이 프로세스를 띄웠는지. 배포된 앱에는 XCTest 가 링크되지 않으므로 항상 nil 이다.
    /// UI 테스트가 띄우는 앱 프로세스에도 XCTest 는 없다 — 그쪽은 AppLaunchConfiguration 이 경로를
    /// 주입하므로 여기서 손댈 것이 없다.
    private static let testProcessRoot: URL? = {
        let environment = ProcessInfo.processInfo.environment
        let runsUnderXCTest = environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        guard runsUnderXCTest else { return nil }
        // `--parallel` 은 테스트마다 프로세스를 새로 띄운다. 프로세스 번호로 갈라야 워커끼리
        // 같은 파일을 밟지 않는다. 끝날 때 자기 몫만 지워 임시 폴더가 쌓이지 않게 한다.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("negaflow-test-storage", isDirectory: true)
            .appendingPathComponent(
                "\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true
            )
        testProcessRootPath = root.path
        atexit {
            guard let path = AppStorageRoot.testProcessRootPath else { return }
            try? FileManager.default.removeItem(atPath: path)
        }
        return root
    }()

    private nonisolated(unsafe) static var testProcessRootPath: String?

    private static func isolatedBase(named name: String) -> URL? {
        guard let testProcessRoot else { return nil }
        let base = testProcessRoot.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
