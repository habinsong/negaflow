import Foundation
import Darwin

extension ExternalScannerBackend {
    func run(
        args: [String],
        stdin: Data?,
        onLine: (@Sendable (String) -> String?)?
    ) async throws -> ProcessOutput {
        try await run(
            args: args,
            stdin: stdin,
            onLine: onLine,
            timeoutPolicy: .policy(for: args)
        )
    }

    /// 짧은 timeout 정책을 주입해 프로세스 종료 계약을 검증할 수 있는 내부 seam.
    func run(
        args: [String],
        stdin: Data?,
        onLine: (@Sendable (String) -> String?)?,
        timeoutPolicy: ProcessTimeoutPolicy,
        outputLimits: ProcessOutputLimits = .standard
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = plugin.executableURL
        process.arguments = args
        process.currentDirectoryURL = plugin.manifestURL.deletingLastPathComponent()
        process.environment = Self.sanitizedPluginEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = stdin == nil ? nil : Pipe()
        if let stdinPipe { process.standardInput = stdinPipe }

        let pipeReaders = PipeReadCoordinator()
        let runToken = ProcessRunToken(process: process, policy: timeoutPolicy)
        let buffer = LineBuffer(
            limit: outputLimits.stdoutBytes,
            label: "stdout",
            onLine: onLine
        ) { message in
            runToken.requestStop(
                .ioFailure,
                message: message,
                terminationGracePeriod: 0.1
            )
        }
        let stderrBuffer = ByteBuffer(
            limit: outputLimits.stderrBytes,
            label: "stderr"
        ) { message in
            runToken.requestStop(
                .ioFailure,
                message: message,
                terminationGracePeriod: 0.1
            )
        }
        let cleanupToken = ProcessCleanupToken()
        process.terminationHandler = { _ in runToken.signalExit() }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            guard pipeReaders.beginRead() else { return }
            defer { pipeReaders.endRead() }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            guard pipeReaders.beginRead() else { return }
            defer { pipeReaders.endRead() }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(data)
            }
        }
        guard setCurrentProcess(
            process,
            cancellation: { runToken.requestStop(.cancelled) },
            completion: cleanupToken
        ) else {
            cleanupPipes(
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe,
                stdoutBuffer: buffer,
                stderrBuffer: stderrBuffer,
                pipeReaders: pipeReaders,
                drain: false
            )
            process.terminationHandler = nil
            cleanupToken.signalFinished()
            throw failure(.busy, "plugin process가 이미 실행 중임")
        }

        do {
            try process.run()
        } catch {
            cleanupPipes(
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe,
                stdoutBuffer: buffer,
                stderrBuffer: stderrBuffer,
                pipeReaders: pipeReaders,
                drain: false
            )
            process.terminationHandler = nil
            clearCurrentProcess(ifSameProcess: process)
            cleanupToken.signalFinished()
            throw failure(.ioFailure, "plugin 실행 실패: \(error.localizedDescription)")
        }
        runToken.markLaunched()

        // Process 시작 후 부모가 보유한 pipe 반대편을 닫아야 자식 종료 시 EOF가 보장된다.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        try? stdinPipe?.fileHandleForReading.close()

        if let stdin, let stdinPipe {
            stdinPipe.fileHandleForWriting.write(stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

        await withTaskCancellationHandler {
            await runToken.waitForExit()
        } onCancel: {
            runToken.requestStop(.cancelled)
        }
        cleanupPipes(
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            stdinPipe: stdinPipe,
            stdoutBuffer: buffer,
            stderrBuffer: stderrBuffer,
            pipeReaders: pipeReaders,
            drain: runToken.stopReason == nil
        )
        process.terminationHandler = nil
        clearCurrentProcess(ifSameProcess: process)
        cleanupToken.signalFinished()

        switch runToken.stopReason {
        case .timeout:
            throw failure(
                .timeout,
                "plugin \(args.first ?? "process") 시간 초과 (\(timeoutPolicy.wallTimeout)초)"
            )
        case .cancelled:
            throw failure(.cancelled, "plugin \(args.first ?? "process") 취소됨")
        case .ioFailure:
            throw failure(
                .ioFailure,
                runToken.stopMessage ?? buffer.failure ?? stderrBuffer.failure ?? "plugin process 출력 계약 위반"
            )
        case nil:
            break
        default:
            break
        }

        if let outputFailure = buffer.failure ?? stderrBuffer.failure {
            throw failure(.ioFailure, outputFailure)
        }

        if process.terminationReason == .uncaughtSignal,
           process.terminationStatus == SIGTERM {
            throw failure(.cancelled, "plugin \(args.first ?? "process") 취소됨")
        }
        return ProcessOutput(status: process.terminationStatus, stdout: buffer.allData, stderr: stderrBuffer.allData)
    }
}

private func cleanupPipes(
    stdoutPipe: Pipe,
    stderrPipe: Pipe,
    stdinPipe: Pipe?,
    stdoutBuffer: LineBuffer,
    stderrBuffer: ByteBuffer,
    pipeReaders: PipeReadCoordinator,
    drain: Bool
) {
    stdoutPipe.fileHandleForReading.readabilityHandler = nil
    stderrPipe.fileHandleForReading.readabilityHandler = nil
    // 이미 예약된 readability callback이 availableData를 소비한 뒤 buffer append를 끝내기 전에
    // drain/flush가 먼저 실행되면 마지막 NDJSON result 줄을 놓칠 수 있다. 새 read를 닫고 진행 중
    // callback이 끝날 때까지 기다린 뒤 현재 도착한 pipe 바이트만 비차단으로 비운다.
    pipeReaders.stopAndWait()

    if drain {
        drainAvailableData(from: stdoutPipe.fileHandleForReading) { data in
            stdoutBuffer.append(data)
            return stdoutBuffer.failure == nil
        }
        drainAvailableData(from: stderrPipe.fileHandleForReading) { data in
            stderrBuffer.append(data)
            return stderrBuffer.failure == nil
        }
    }
    stdoutBuffer.flush()

    try? stdoutPipe.fileHandleForReading.close()
    try? stdoutPipe.fileHandleForWriting.close()
    try? stderrPipe.fileHandleForReading.close()
    try? stderrPipe.fileHandleForWriting.close()
    try? stdinPipe?.fileHandleForReading.close()
    try? stdinPipe?.fileHandleForWriting.close()
}
