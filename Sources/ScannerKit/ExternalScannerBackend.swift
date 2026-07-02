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
    let processLock = NSLock()
    var currentProcess: Process?

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

    func failure(_ code: ScannerError.Code, _ message: String) -> ScannerError {
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
