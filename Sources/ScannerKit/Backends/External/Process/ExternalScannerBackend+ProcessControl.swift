import Foundation
import Darwin

extension ExternalScannerBackend {

    struct ProcessOutputLimits: Sendable, Equatable {
        let stdoutBytes: Int
        let stderrBytes: Int

        init(stdoutBytes: Int, stderrBytes: Int) {
            self.stdoutBytes = max(1, stdoutBytes)
            self.stderrBytes = max(1, stderrBytes)
        }

        static let standard = ProcessOutputLimits(
            stdoutBytes: 4 * 1_024 * 1_024,
            stderrBytes: 1 * 1_024 * 1_024
        )
    }

    struct ProcessTimeoutPolicy: Sendable, Equatable {
        let wallTimeout: TimeInterval
        let terminationGracePeriod: TimeInterval

        init(wallTimeout: TimeInterval, terminationGracePeriod: TimeInterval) {
            self.wallTimeout = max(0.001, wallTimeout)
            self.terminationGracePeriod = max(0, terminationGracePeriod)
        }

        static func policy(for args: [String]) -> ProcessTimeoutPolicy {
            switch args.first {
            case "detect":
                return ProcessTimeoutPolicy(wallTimeout: 15, terminationGracePeriod: 1)
            case "capabilities":
                return ProcessTimeoutPolicy(wallTimeout: 20, terminationGracePeriod: 1)
            case "scan":
                return ProcessTimeoutPolicy(wallTimeout: 7_200, terminationGracePeriod: 3)
            default:
                return ProcessTimeoutPolicy(wallTimeout: 30, terminationGracePeriod: 1)
            }
        }
    }

    struct ProcessOutput {
        let status: Int32
        let stdout: Data
        let stderr: Data
        var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    /// 플러그인에는 실행에 필요한 최소 환경만 전달한다. 부모 앱의 토큰, credential,
    /// DYLD 주입 변수와 개발용 override가 외부 프로세스로 유출되지 않게 한다.
    static func sanitizedPluginEnvironment(
        from parent: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        for key in ["HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let value = parent[key], !value.isEmpty, !value.contains("\0") {
                environment[key] = value
            }
        }
        if environment["HOME"] == nil {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if environment["TMPDIR"] == nil {
            environment["TMPDIR"] = FileManager.default.temporaryDirectory.path
        }
        return environment
    }

    func setCurrentProcess(
        _ proc: Process,
        cancellation: @escaping @Sendable () -> Void,
        completion: ProcessCleanupToken
    ) -> Bool {
        processLock.lock()
        guard currentProcess == nil else {
            processLock.unlock()
            return false
        }
        currentProcess = proc
        currentProcessCancellation = cancellation
        currentProcessCompletion = completion
        processLock.unlock()
        return true
    }

    func snapshotCurrentProcess() -> Process? {
        processLock.lock(); defer { processLock.unlock() }
        return currentProcess
    }

    func cancelCurrentProcess() {
        processLock.lock()
        let cancellation = currentProcessCancellation
        processLock.unlock()
        cancellation?()
    }

    func cancelCurrentProcessAndWait() async {
        let (cancellation, completion) = snapshotCurrentProcessControl()
        cancellation?()
        await completion?.waitUntilFinished()
    }

    private func snapshotCurrentProcessControl() -> (
        cancellation: (@Sendable () -> Void)?,
        completion: ProcessCleanupToken?
    ) {
        processLock.lock()
        defer { processLock.unlock() }
        let cancellation = currentProcessCancellation
        let completion = currentProcessCompletion
        return (cancellation, completion)
    }

    func clearCurrentProcess(ifSameProcess process: Process) {
        processLock.lock()
        if currentProcess === process {
            currentProcess = nil
            currentProcessCancellation = nil
            currentProcessCompletion = nil
        }
        processLock.unlock()
    }

    /// 플러그인 실행파일을 Process 로 실행한다. onLine 이 있으면 stdout 을 줄 단위(NDJSON)로 스트리밍한다.

}
