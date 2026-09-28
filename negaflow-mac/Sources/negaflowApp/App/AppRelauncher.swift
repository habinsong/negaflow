import Foundation

/// 이 프로세스가 끝난 뒤 같은 앱 번들을 다시 연다.
///
/// 종료가 승인된 뒤(`applicationWillTerminate`)에만 부른다. 먼저 띄우면 두 번째 인스턴스가
/// 라이브러리 프로세스 잠금에 걸리고, 종료가 취소되면 대기하던 셸이 엉뚱한 때 앱을 연다.
enum AppRelauncher {
    /// 종료가 끝나지 않을 때 무한히 기다리지 않도록 둔 상한(0.2초 × 300 = 60초).
    static let maximumWaitTicks = 300

    static func relaunchAfterExit(
        bundleURL: URL = Bundle.main.bundleURL,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        environment: [String: String] = AppLaunchConfiguration.relaunchEnvironment()
    ) throws {
        guard bundleURL.pathExtension == "app" else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            i=0
            while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt \(maximumWaitTicks) ]; do
              /bin/sleep 0.2
              i=$((i + 1))
            done
            exec /usr/bin/open "$2"
            """,
            "negaflow-relaunch",
            String(processID),
            bundleURL.path,
        ]
        // `open` 은 부른 쪽의 환경을 새 앱에 그대로 넘긴다(실측). 이 셸이 넘길 환경을 정한다.
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
