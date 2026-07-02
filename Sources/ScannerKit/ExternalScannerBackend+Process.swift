import Foundation

extension ExternalScannerBackend {
    struct ProcessOutput {
        let status: Int32
        let stdout: Data
        let stderr: Data
        var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    func setCurrentProcess(_ proc: Process?) {
        processLock.lock(); currentProcess = proc; processLock.unlock()
    }

    func snapshotCurrentProcess() -> Process? {
        processLock.lock(); defer { processLock.unlock() }
        return currentProcess
    }

    /// 플러그인 실행파일을 Process 로 실행한다. onLine 이 있으면 stdout 을 줄 단위(NDJSON)로 스트리밍한다.
    func run(
        args: [String],
        stdin: Data?,
        onLine: (@Sendable (String) -> Void)?
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = plugin.executableURL
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = Pipe()
        if stdin != nil { process.standardInput = stdinPipe }

        let buffer = LineBuffer(onLine: onLine)
        let stderrBuffer = ByteBuffer()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            throw failure(.ioFailure, "plugin 실행 실패: \(error.localizedDescription)")
        }
        setCurrentProcess(process)

        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty { buffer.append(remaining) }
        buffer.flush()

        let stderrRemaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !stderrRemaining.isEmpty { stderrBuffer.append(stderrRemaining) }
        setCurrentProcess(nil)
        return ProcessOutput(status: process.terminationStatus, stdout: buffer.allData, stderr: stderrBuffer.allData)
    }
}

private final class ByteBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var collected = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        collected.append(data)
        lock.unlock()
    }

    var allData: Data {
        lock.lock(); defer { lock.unlock() }
        return collected
    }
}

/// stdout 바이트를 누적하며 개행 단위로 onLine 콜백을 호출하는 스레드 안전 버퍼.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var collected = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ data: Data) {
        lock.lock()
        collected.append(data)
        guard onLine != nil else { lock.unlock(); return }
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<nl)
            pending.removeSubrange(pending.startIndex...nl)
            if let s = String(data: lineData, encoding: .utf8) { lines.append(s) }
        }
        lock.unlock()
        for line in lines { onLine?(line) }
    }

    func flush() {
        lock.lock()
        let leftover = pending
        pending.removeAll()
        lock.unlock()
        if let onLine, !leftover.isEmpty, let s = String(data: leftover, encoding: .utf8) {
            onLine(s)
        }
    }

    var allData: Data {
        lock.lock(); defer { lock.unlock() }
        return collected
    }
}
