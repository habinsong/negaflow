import Foundation

// MARK: - ExternalScannerBackend
//
// 설치된 외부 스캐너 플러그인 하나를 감싸는 백엔드. 플러그인 실행파일을 Process 로 띄워
// JSON/CLI 프로토콜(detect / capabilities / scan)로 통신한다. negaflow 는 이 백엔드만 알고
// SANE 같은 구체 구현은 전혀 모른다.
public final class ExternalScannerBackend: ScannerBackend, @unchecked Sendable {
    public let backendType: BackendType = .plugin
    public let plugin: InstalledScannerPlugin

    private var lastError: ScannerError?
    private let processLock = NSLock()
    private var currentProcess: Process?

    public init(plugin: InstalledScannerPlugin) { self.plugin = plugin }

    public func getLastError() -> ScannerError? { lastError }

    /// 이 백엔드가 소유한 장치 id 인가. 외부 id 는 `plugin:<pluginId>:<내부id>`.
    public func owns(scannerID: String) -> Bool {
        scannerID.hasPrefix(externalPrefix)
    }

    private var externalPrefix: String { "plugin:\(plugin.id):" }
    private func externalID(_ internalID: String) -> String { externalPrefix + internalID }
    private func internalID(_ scannerID: String) -> String {
        scannerID.hasPrefix(externalPrefix)
            ? String(scannerID.dropFirst(externalPrefix.count))
            : scannerID
    }

    // MARK: detect
    public func detectScanners() async throws -> [ScannerDescriptor] {
        let out = try await run(args: ["detect"], stdin: nil, onLine: nil)
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin detect 실패: \(out.stderrText)")
        }
        guard let response = try? JSONDecoder().decode(PluginDetectResponse.self, from: out.stdout) else {
            throw failure(.ioFailure, "plugin detect 응답 파싱 실패")
        }
        return response.devices.map { device in
            ScannerDescriptor(
                id: externalID(device.id),
                displayName: device.displayName,
                vendor: device.vendor,
                model: device.model,
                backendType: .plugin,
                connectionType: ConnectionType(rawValue: device.connectionType ?? "usb") ?? .usb,
                usbVendorID: device.usbVendorID,
                usbProductID: device.usbProductID,
                serialNumber: device.serialNumber,
                verifiedStatus: VerifiedStatus(rawValue: device.verifiedStatus ?? "") ?? .compatibleTarget,
                driverVersion: device.driverVersion ?? plugin.name
            )
        }
    }

    // MARK: capabilities
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        let out = try await run(args: ["capabilities", internalID(scannerID)], stdin: nil, onLine: nil)
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin capabilities 실패: \(out.stderrText)")
        }
        guard let caps = try? JSONDecoder().decode(PluginCapabilities.self, from: out.stdout) else {
            throw failure(.ioFailure, "plugin capabilities 응답 파싱 실패")
        }
        return ScannerCapabilities(
            supportedResolutions: caps.resolutionsDPI.map { Resolution($0) }.sorted(),
            supportedModes: caps.modes.compactMap { ColorMode(rawValue: $0) },
            supportedBitDepths: caps.bitDepths.compactMap { BitDepth(rawValue: $0) },
            supportsPreview: caps.supportsPreview ?? true,
            supportsTransparency: caps.supportsTransparency ?? true,
            supportsInfrared: caps.supportsInfrared ?? false,
            supportsMultiExposure: caps.supportsMultiExposure ?? false,
            supportsScanArea: caps.supportsScanArea ?? true,
            supportsLampWarmupStatus: false,
            maxScanArea: ScanArea(
                widthMM: caps.maxScanAreaWidthMM ?? 36.0,
                heightMM: caps.maxScanAreaHeightMM ?? 24.0
            ),
            outputFormats: caps.outputFormats ?? ["tiff"]
        )
    }

    // MARK: scan
    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        try await scan(options, preview: true, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        try await scan(options, preview: false, progress: progress)
    }

    private func scan(
        _ options: ScanOptions,
        preview: Bool,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let outputURL = options.temporaryOutputURL
            ?? ScanTempFile.makeURL(prefix: "negaflow_plugin", suffix: ".tiff")
        let wire = PluginScanOptions(
            deviceID: internalID(options.scannerID),
            resolutionDPI: options.resolution.dpi,
            bitDepth: options.bitDepth.rawValue,
            colorMode: options.colorMode.rawValue,
            filmType: options.filmType.rawValue,
            preview: preview,
            multiExposure: options.multiExposureEnabled,
            infrared: options.infraredEnabled,
            outputPath: outputURL.path
        )
        let stdinData = try JSONEncoder().encode(wire)

        let sink = ScanEventSink()
        let start = Date()

        let out = try await run(args: ["scan"], stdin: stdinData) { line in
            guard let data = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(PluginScanEvent.self, from: data) else { return }
            switch event.type {
            case "progress":
                let phase = event.phase.flatMap { ScanPhase(rawValue: $0) } ?? .scanningRGB
                progress(ScanProgress(phase: phase, fraction: event.fraction, message: event.message ?? ""))
            case "result":
                sink.setResult(event)
            case "error":
                sink.setError(event.message)
            default:
                break
            }
        }

        if let errorMessage = sink.error {
            throw failure(.ioFailure, errorMessage)
        }
        guard out.status == 0 else {
            throw failure(.ioFailure, "plugin scan 실패: \(out.stderrText)")
        }
        guard let resultEvent = sink.result, let path = resultEvent.path else {
            throw failure(.ioFailure, "plugin scan 결과 누락")
        }
        return ScanResult(
            rawFileURL: URL(fileURLWithPath: path),
            width: resultEvent.width ?? 0,
            height: resultEvent.height ?? 0,
            resolution: Resolution(resultEvent.resolutionDPI ?? options.resolution.dpi),
            bitDepth: BitDepth(rawValue: resultEvent.bitDepth ?? options.bitDepth.rawValue) ?? options.bitDepth,
            scanDuration: Date().timeIntervalSince(start),
            backendUsed: .plugin
        )
    }

    public func cancelScan() async {
        snapshotCurrentProcess()?.terminate()
    }

    // 락 사용을 동기 헬퍼로 격리한다(async 컨텍스트에서 NSLock 직접 호출 회피).
    private func setCurrentProcess(_ proc: Process?) {
        processLock.lock(); currentProcess = proc; processLock.unlock()
    }
    private func snapshotCurrentProcess() -> Process? {
        processLock.lock(); defer { processLock.unlock() }
        return currentProcess
    }

    // MARK: process runner
    private struct ProcessOutput {
        let status: Int32
        let stdout: Data
        let stderr: Data
        var stderrText: String { String(data: stderr, encoding: .utf8) ?? "" }
    }

    /// 플러그인 실행파일을 Process 로 실행한다. onLine 이 있으면 stdout 을 줄 단위(NDJSON)로 스트리밍한다.
    private func run(
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
        // 종료 후 남은 데이터를 마저 읽는다.
        let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remaining.isEmpty { buffer.append(remaining) }
        buffer.flush()

        let stderrRemaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !stderrRemaining.isEmpty { stderrBuffer.append(stderrRemaining) }
        setCurrentProcess(nil)
        return ProcessOutput(status: process.terminationStatus, stdout: buffer.allData, stderr: stderrBuffer.allData)
    }

    private func failure(_ code: ScannerError.Code, _ message: String) -> ScannerError {
        let err = ScannerError(code, message)
        lastError = err
        return err
    }
}

/// scan 이벤트(result/error)를 백그라운드 스트리밍 콜백에서 안전하게 수집한다.
private final class ScanEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: PluginScanEvent?
    private var _error: String?
    func setResult(_ e: PluginScanEvent) { lock.lock(); _result = e; lock.unlock() }
    func setError(_ m: String?) { lock.lock(); _error = m; lock.unlock() }
    var result: PluginScanEvent? { lock.lock(); defer { lock.unlock() }; return _result }
    var error: String? { lock.lock(); defer { lock.unlock() }; return _error }
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
