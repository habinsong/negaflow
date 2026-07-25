import Foundation
import Darwin

final class ProcessRunToken: @unchecked Sendable {
    private let process: Process
    private let policy: ExternalScannerBackend.ProcessTimeoutPolicy
    private let lock = NSLock()
    private var launched = false
    private var didExit = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var forceKillWorkItem: DispatchWorkItem?
    private var _stopReason: ScannerError.Code?
    private var _stopMessage: String?
    private var stopGracePeriod: TimeInterval?

    init(process: Process, policy: ExternalScannerBackend.ProcessTimeoutPolicy) {
        self.process = process
        self.policy = policy
    }

    var stopReason: ScannerError.Code? {
        lock.lock(); defer { lock.unlock() }
        return _stopReason
    }

    var stopMessage: String? {
        lock.lock(); defer { lock.unlock() }
        return _stopMessage
    }

    func markLaunched() {
        let timeout = DispatchWorkItem { [weak self] in self?.requestStop(.timeout) }
        lock.lock()
        launched = true
        let needsStop = _stopReason != nil
        timeoutWorkItem = timeout
        lock.unlock()

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + policy.wallTimeout,
            execute: timeout
        )
        if needsStop { beginTermination() }
    }

    func requestStop(
        _ reason: ScannerError.Code,
        message: String? = nil,
        terminationGracePeriod: TimeInterval? = nil
    ) {
        lock.lock()
        let isFirstRequest = !didExit && _stopReason == nil
        if isFirstRequest {
            _stopReason = reason
            _stopMessage = message
            stopGracePeriod = terminationGracePeriod
        }
        let shouldTerminate = isFirstRequest && launched
        lock.unlock()

        if shouldTerminate { beginTermination() }
    }

    func waitForExit() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didExit {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func signalExit() {
        lock.lock()
        didExit = true
        timeoutWorkItem?.cancel()
        forceKillWorkItem?.cancel()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    private func beginTermination() {
        signal(SIGTERM)
        let forceKill = DispatchWorkItem { [weak self] in self?.signal(SIGKILL) }
        lock.lock()
        let gracePeriod = stopGracePeriod ?? policy.terminationGracePeriod
        forceKillWorkItem = forceKill
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + gracePeriod,
            execute: forceKill
        )
    }

    private func signal(_ value: Int32) {
        guard process.isRunning else { return }
        _ = Darwin.kill(process.processIdentifier, value)
    }
}
