import Foundation
import Chromabase
import CoreGraphics
import CoreImage
import ImageIO

// MARK: - SANEBackend (plan §6.3 — scanimage CLI wrapper)
//
// Phase 0 검증 결과에 기반한 PRIMARY 백엔드.
//   • scanimage -L  → 장치 감지 (genesys:libusb:xxx:xxx)
//   • scanimage -A  → 옵션 덤프 → ScannerCapabilities 로 파싱
//   • scanimage ... > file.tiff → 스캔 수행
//
// 검증된 8200i capability:
//   --mode Color|Gray, --depth 16, --resolution 7200|3600|2400|1200|600dpi,
//   --source "Transparency Adapter", -l/-t/-x/-y geometry.
//   (IR 채널은 genesys 백엔드 옵션에 노출되지 않음 → Phase 5 과제)
public final class SANEBackend: ScannerBackend, @unchecked Sendable {
    public let backendType: BackendType = .sane
    private let scanimage: String
    private var lastError: ScannerError?
    static let multiSamplePassCount = 3
    static let hardwareExposureTimes = [11_000, 14_000, 30_000]
    static var hardwareExposureSamplesPerStop: Int {
        let raw = ProcessInfo.processInfo.environment["NEGAFLOW_HWEXP_SAMPLES"] ?? ""
        let parsed = Int(raw) ?? 1
        return min(max(parsed, 1), 4)
    }

    static func hardwareExposurePlan(samplesPerStop: Int = hardwareExposureSamplesPerStop) -> [Int] {
        hardwareExposureTimes.flatMap { exposure in
            Array(repeating: exposure, count: min(max(samplesPerStop, 1), 4))
        }
    }

    /// nil이면 PATH에서 `scanimage`를 찾는다.
    public init(scanimagePath: String? = nil) {
        self.scanimage = scanimagePath
            ?? ProcessInfo.processInfo.environment["NEGAFLOW_SCANIMAGE_PATH"]
            ?? Self.findScanimage()
    }

    public func getLastError() -> ScannerError? { lastError }

    // MARK: detect
    public func detectScanners() async throws -> [ScannerDescriptor] {
        let out = try await runScanimage(args: ["-L"])
        // 형식: `device `genesys:libusb:000:010' is a PLUSTEK OpticFilm 8100 flatbed scanner`
        var devices: [ScannerDescriptor] = []
        let lines = out.split(separator: "\n")
        let deviceRegex = try NSRegularExpression(
            pattern: "device `([^']+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        for line in lines {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            if let m = deviceRegex.firstMatch(in: s, range: range),
               let devRange = Range(m.range(at: 1), in: s),
               let vendorRange = Range(m.range(at: 2), in: s),
               let modelRange = Range(m.range(at: 3), in: s) {
                let devname = String(s[devRange])        // genesys:libusb:000:010
                let vendor = String(s[vendorRange])       // PLUSTEK
                let modelRaw = String(s[modelRange])      // OpticFilm 8100
                let model = modelRaw.trimmingCharacters(in: .whitespaces)
                let id = "sane-\(devname)"
                // SANE은 8200i를 8100으로 리포트한다(동일 칩). 모델명이 아닌 capability로 판단한다 (plan §5.3).
                devices.append(ScannerDescriptor(
                    id: id,
                    displayName: "Plustek \(model)",
                    vendor: vendor.capitalized,
                    model: model,
                    backendType: .sane,
                    connectionType: .usb,
                    verifiedStatus: .verified,
                    driverVersion: "genesys (SANE)"
                ))
            }
        }
        return devices
    }

    // MARK: capabilities (scanimage -A 파싱)
    public func getCapabilities(scannerID: String) async throws -> ScannerCapabilities {
        // -A 도 동일하게 현재 주소가 필요하다(scannerID 주소가 만료될 수 있음).
        let devname = (try? await currentDeviceAddress()) ?? scannerID.replacingOccurrences(of: "sane-", with: "")
        let dump = try await runScanimage(args: ["-A", "-d", devname])
        return Self.parseCapabilities(dump)
    }

    /// 스캔 직전에 scanimage -L 을 다시 돌려 현재 장치의 libusb 주소를 얻는다.
    ///
    /// USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매 호출마다 바뀐다
    /// (Plustek 8200i + genesys 확인: 010 ↔ 011). scannerID 에 박힌 과거 주소로
    /// open 하면 "open of device failed: Invalid argument" 로 실패한다.
    /// 따라서 스캔 직전에 반드시 현재 주소를 다시 얻어야 한다.
    ///
    /// 매칭은 USB Vendor/Product ID(8200i = 0x07b3:0x130C)로 한다 — 주소가 아닌
    /// 안정적인 장치 식별자 기반. scannerID 접두사(sane-)를 벗긴 값이
    /// "genesys:libusb:..." 형태이므로, 그 안의 vid/pid 가 아니라 -L 의 동일
    /// 모델 문자열(PLUSTEK ... OpticFilm ...)을 기준으로 현재 주소를 찾는다.
    ///
    /// 최적화: 주소는 TTL 5초 캐싱. USB 주소는 리셋 시에만 바뀌므로, 연속 스캔/배치에서
    /// 매번 -L 를 돌릴 필요가 없다. notConnected 시 즉시 무효화.
    private nonisolated(unsafe) var cachedAddress: String?
    private nonisolated(unsafe) var cachedAddressAt: Date = .distantPast
    private let addressCacheTTL: TimeInterval = 5.0

    func currentDeviceAddress() async throws -> String {
        // 캐시 유효하면 재사용.
        if let cached = cachedAddress,
           Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL {
            return cached
        }
        let out = try await runScanimage(args: ["-L"])
        // `device `genesys:libusb:000:011' is a PLUSTEK OpticFilm 8100 flatbed scanner`
        let regex = try NSRegularExpression(
            pattern: "device `genesys:(libusb:[0-9]+:[0-9]+)' is a ([^\\s]+)\\s+(.+?) (?:flatbed |film )?scanner"
        )
        let range = NSRange(out.startIndex..., in: out)
        if let m = regex.firstMatch(in: out, range: range),
           let addrRange = Range(m.range(at: 1), in: out) {
            let addr = "genesys:" + String(out[addrRange])
            cachedAddress = addr
            cachedAddressAt = Date()
            return addr
        }
        // 실패 시 캐시 무효화.
        cachedAddress = nil
        cachedAddressAt = .distantPast
        throw ScannerError(.notConnected, "scanimage -L 이 장치를 찾지 못함 (주소 재획득 실패)")
    }

    /// 캐시 강제 무효화(장치 점유/재연결 등).
    public func invalidateAddressCache() {
        cachedAddress = nil
        cachedAddressAt = .distantPast
    }


    public func startPreviewScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        // 프리뷰는 저해상도 + --preview 플래그로 빠르게.
        var opts = options
        opts.resolution = .preview
        opts.bitDepth = .eight
        return try await startFullScan(opts, progress: progress)
    }

    public func startFullScan(
        _ options: ScanOptions,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        reapZombieScanimages()

        let outURL = options.temporaryOutputURL
            ?? Self.makeTempURL(prefix: "negaflow_scan", suffix: ".tiff")

        if options.multiExposureEnabled, options.resolution != .preview {
            return try await startSoftwareMultiPassScan(options, outputURL: outURL, progress: progress)
        }

        // 중요: USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매번 바뀐다.
        // scannerID에 박힌 과거 주소로 open하면 "Invalid argument"로 실패한다.
        // 따라서 스캔 직전에 반드시 scanimage -L 로 현재 주소를 다시 얻는다.
        // 그래도 -L 시점과 open 시점 사이에 주소가 바뀔 수 있으므로, open 실패 시
        // 캐시를 무효화하고 새 주소로 1회 재시도한다.
        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        progress(ScanProgress(phase: .scanningRGB, fraction: 0.1, message: "Scanning RGB"))

        let t0 = Date()
        try await runSingleAcquisition(
            options: options,
            outputURL: outURL,
            brightness: nil,
            staleRetryProgress: 0.05,
            progress: progress
        )
        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))
        let (w, h) = Self.imageSize(at: outURL)
        return ScanResult(
            rawFileURL: outURL,
            width: w, height: h,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: false,
            scanDuration: duration,
            backendUsed: .sane
        )
    }

    private func startSoftwareMultiPassScan(
        _ options: ScanOptions,
        outputURL: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let t0 = Date()
        let usesHardwareExposure = await supportsHardwareExposure(for: options)
        let exposurePlan = usesHardwareExposure ? Self.hardwareExposurePlan() : []
        let passCount = usesHardwareExposure ? exposurePlan.count : Self.multiSamplePassCount
        let labels = (0..<passCount).map { "sample\($0 + 1)" }
        let urls = labels.map { Self.makeTempURL(prefix: "negaflow_multipass_\($0)", suffix: ".tiff") }
        defer {
            if !Self.shouldKeepMultiPassArtifacts {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        for index in 0..<passCount {
            let base = 0.08 + Double(index) * (0.75 / Double(passCount))
            var passOptions = options
            if usesHardwareExposure {
                passOptions.hardwareExposureTime = exposurePlan[index]
            }
            progress(ScanProgress(
                phase: .scanningRGB,
                fraction: base,
                message: usesHardwareExposure
                    ? "Exposure bracket \(index + 1)/\(passCount) @ \(exposurePlan[index])"
                    : "Multi-sample \(index + 1)/\(passCount)"
            ))
            try await runSingleAcquisition(
                options: passOptions,
                outputURL: urls[index],
                brightness: nil,
                staleRetryProgress: base,
                progress: progress
            )
        }

        progress(ScanProgress(phase: .processingNegative, fraction: 0.86, message: "Averaging multi-sample scan"))
        do {
            if usesHardwareExposure {
                try Self.mergeHardwareExposureScans(
                    sampleURLs: urls,
                    exposureTimes: exposurePlan,
                    outputURL: outputURL
                )
            } else {
                try Self.averageMultiSampleScans(
                    sampleURLs: urls,
                    outputURL: outputURL
                )
            }
        } catch {
            self.lastError = ScannerError(.ioFailure, "multi-sample merge failed: \(error.localizedDescription)")
            throw lastError!
        }

        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Multi-sample scan complete"))
        let (w, h) = Self.imageSize(at: outputURL)
        var warnings = usesHardwareExposure ? [
            "Hardware scan-exposure-time bracket \(Self.hardwareExposureTimes) used with \(Self.hardwareExposureSamplesPerStop) sample(s) per exposure; same-exposure samples reduce random/color noise before clipped/low-signal regions are filled from alternate exposures."
        ] : [
            "SANE genesys does not expose scan-exposure-time on this device; averaged \(Self.multiSamplePassCount) identical 16-bit passes for random-noise reduction, not hardware HDR."
        ]
        if Self.shouldKeepMultiPassArtifacts {
            warnings.append("Multi-pass intermediate TIFFs kept: \(urls.map(\.path).joined(separator: ", "))")
        }
        return ScanResult(
            rawFileURL: outputURL,
            width: w,
            height: h,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: false,
            scanDuration: duration,
            backendUsed: .sane,
            warnings: warnings
        )
    }

    private func supportsHardwareExposure(for options: ScanOptions) async -> Bool {
        guard let capabilities = try? await getCapabilities(scannerID: options.scannerID) else {
            return false
        }
        return capabilities.supportsMultiExposure
    }

    private static var shouldKeepMultiPassArtifacts: Bool {
        let value = ProcessInfo.processInfo.environment["NEGAFLOW_KEEP_MULTIPASS"] ?? ""
        return value == "1" || value.lowercased() == "true"
    }

    private func runSingleAcquisition(
        options: ScanOptions,
        outputURL: URL,
        brightness: Int?,
        staleRetryProgress: Double,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws {
        var lastStderr = ""
        for attempt in 0..<2 {
            if attempt > 0 {
                invalidateAddressCache()
            }
            let devname = await resolveDeviceAddress(for: options)
            let args = makeScanimageArgs(devname: devname, options: options, brightness: brightness)
            do {
                let ec = try await runScanimageTo(args: args, outputURL: outputURL, progress: progress)
                if ec == 0 {
                    return
                }
                lastStderr = takeStderr()
                if attempt == 0, Self.isStaleDeviceError(lastStderr) {
                    progress(ScanProgress(
                        phase: .warmingLamp,
                        fraction: staleRetryProgress,
                        message: "Re-detecting scanner"
                    ))
                    continue
                }
                let detail = lastStderr.isEmpty ? "scanimage exit \(ec)" : "scanimage exit \(ec): \(lastStderr)"
                self.lastError = ScannerError(.ioFailure, detail)
                throw lastError!
            } catch let err as ScannerError {
                throw err
            } catch {
                self.lastError = ScannerError(.ioFailure, error.localizedDescription)
                throw error
            }
        }
        let detail = lastStderr.isEmpty ? "scanimage 재시도 실패" : "scanimage 재시도 실패: \(lastStderr)"
        self.lastError = ScannerError(.ioFailure, detail)
        throw lastError!
    }

    /// "open of device ... failed: Invalid argument" 등 USB 주소가 만료됐을 때
    /// 나타나는 전형적 오류인지 판별. 이 경우 주소를 다시 얻어 재시도하면 보통 성공한다.
    static func isStaleDeviceError(_ stderr: String) -> Bool {
        let s = stderr.lowercased()
        return s.contains("invalid argument")
            || s.contains("open of device")
            || s.contains("failed to open")
            || s.contains("device busy")
            || s.contains("no such device")
            || s.contains("i/o error")
            || s.contains("device i/o")
    }

    private func resolveDeviceAddress(for options: ScanOptions) async -> String {
        if let current = try? await currentDeviceAddressWithRetry() {
            return current
        }
        return options.scannerID.replacingOccurrences(of: "sane-", with: "")
    }

    private func currentDeviceAddressWithRetry() async throws -> String {
        var lastError: Error?
        for attempt in 0..<5 {
            do {
                return try await currentDeviceAddress()
            } catch {
                lastError = error
                if attempt < 4 {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        throw lastError ?? ScannerError(.notConnected, "scanimage -L 이 장치를 찾지 못함")
    }

    func makeScanimageArgs(devname: String, options: ScanOptions, brightness: Int? = nil) -> [String] {
        var args: [String] = ["-d", devname]
        args += ["--mode", options.colorMode == .gray ? "Gray" : "Color"]
        args += ["--source", "Transparency Adapter"]
        if let brightness {
            args += ["--brightness=\(brightness)"]
        }
        if let exposureTime = options.hardwareExposureTime {
            args += ["--scan-exposure-time=\(exposureTime)"]
        }
        if options.resolution == .preview { args += ["--preview=yes"] }
        if options.resolution.dpi > 0 { args += ["--resolution", "\(options.resolution.dpi)"] }
        args += ["--depth", "\(options.bitDepth.rawValue)"]
        args += ["-x", String(format: "%.2f", options.scanArea.widthMM),
                 "-y", String(format: "%.2f", options.scanArea.heightMM)]
        args += ["--format=tiff"]
        return args
    }



    public func cancelScan() async {
        // 진행 중인 scanimage 프로세스를 즉시 종료한다.
        // 단순 Task.cancel() 로는 잡히지 않는다 — 실제 Process 를 죽여야 USB 가 풀린다.
        if let proc = currentProcess, proc.isRunning {
            proc.terminate()
            // 0.5초 후에도 살아있으면 강제 kill.
            try? await Task.sleep(nanoseconds: 500_000_000)
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
        currentProcess = nil
    }

    /// 시작 전에 이전 scanimage 좀비 프로세스를 정리한다.
    /// 좀비가 USB 장치를 붙잡고 있으면 새 스캔이 "Invalid argument" 로 실패한다
    /// (실제로 발생한 버그). scanimage 바이너리 경로로 ps 를 돌려 잔류분을 죽인다.
    ///
    /// 최적화: 잔류 프로세스가 실제로 존재할 때만 정리 + 대기. 이전에는 매 스캔마다
    /// 무조건 1초 대기를 해서 배치/단일 스캔 모두 지연의 원인이 됐다. pgrep 로
    /// 잔류분이 없으면 즉시 반환(0초 비용).
    private func reapZombieScanimages() {
        let path = scanimage
        // 1) 잔류 scanimage 가 있는지 먼저 확인(비활성 pkill).
        let probe = Process()
        probe.launchPath = "/bin/sh"
        probe.arguments = ["-c", "pgrep -f '\(path)' || true"]
        let probePipe = Pipe()
        probe.standardOutput = probePipe
        try? probe.run(); probe.waitUntilExit()
        let out = (try? probePipe.fileHandleForReading.readToEnd()) ?? Data()
        let count = String(data: out, encoding: .utf8)?
            .split(separator: "\n")
            .filter { !$0.isEmpty }
            .count ?? 0
        guard count > 0 else { return }   // 잔류 없음 → 즉시 반환(1초 대기 생략)

        // 2) 잔류가 있으면 정리.
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "pkill -9 -f '\(path)' || true"]
        try? task.run()
        task.waitUntilExit()
        // USB 해제 대기(좀비가 있었을 때만).
        Thread.sleep(forTimeInterval: 1.0)
    }

    // MARK: helpers
    /// 마지막 scanimage 실행의 stderr(에러 진단용). exit!=0 일 때 오류 메시지로 쓴다.
    private var lastStderr: String = ""

    private func runScanimage(args: [String]) async throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: scanimage)
        proc.arguments = args
        proc.environment = makeSaneEnvironmentWithDefaultDevice()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // 파이프 버퍼(64KB)가 가득 차면 scanimage 가 블록한다(실제 교착 사례).
        // 반드시 proc.run() "이후에" 백그라운드에서 readDataToEndOfFile() 로 drain.
        let outBox = BufferBox()
        let errBox = BufferBox()
        let outQ = DispatchQueue(label: "negaflow.sane.stdout")
        let errQ = DispatchQueue(label: "negaflow.sane.stderr")
        try proc.run()
        let outWork = DispatchWorkItem { outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile() }
        let errWork = DispatchWorkItem { errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile() }
        outQ.async(execute: outWork)
        errQ.async(execute: errWork)
        proc.waitUntilExit()
        // 두 drain 작업이 끝날 때까지 대기.
        outWork.wait()
        errWork.wait()
        lastStderr = String(data: errBox.data, encoding: .utf8) ?? ""
        return String(data: outBox.data, encoding: .utf8) ?? ""
    }

    /// 백그라운드 drain 스레드가 안전하게 쓸 수 있는 버퍼 홀더.
    private final class BufferBox: @unchecked Sendable {
        var data = Data()
    }

    private func runScanimageTo(args: [String], outputURL: URL,
                                progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> Int32 {
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: scanimage)
            proc.arguments = args
            proc.environment = makeSaneEnvironmentWithDefaultDevice()
            self.stderrBuffer = ""
            try? FileManager.default.removeItem(at: outputURL)
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try? FileHandle(forWritingTo: outputURL)
            proc.standardOutput = handle
            let errPipe = Pipe()
            proc.standardError = errPipe
            errPipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
                if let chunk = try? fh.readToEnd(), let s = String(data: chunk, encoding: .utf8) {
                    self?.appendStderr(s)
                }
            }
            proc.terminationHandler = { [weak self] p in
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? errPipe.fileHandleForReading.readToEnd(),
                   let s = String(data: rest, encoding: .utf8) {
                    self?.appendStderr(s)
                }
                try? handle?.close()
                // 프로세스 추적 해제 — 좀비 방지.
                self?.clearCurrentProcess(p)
                cont.resume(returning: p.terminationStatus)
            }
            do {
                try proc.run()
                self.trackCurrentProcess(proc)
            } catch {
                try? handle?.close()
                cont.resume(throwing: error)
            }
        }
    }

    /// 현재 실행 중인 scanimage 프로세스(cancel 시 종료용).
    private nonisolated(unsafe) var currentProcess: Process?
    private func trackCurrentProcess(_ p: Process) { currentProcess = p }
    private func clearCurrentProcess(_ p: Process) {
        if let cp = currentProcess, cp.processIdentifier == p.processIdentifier { currentProcess = nil }
    }

    /// stderr drain 핸들러에서 MainActor 가 아닌 컨텍스트에서 안전하게 누적.
    private nonisolated(unsafe) var stderrBuffer = ""
    private func appendStderr(_ s: String) { stderrBuffer += s }
    private func takeStderr() -> String {
        let s = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        stderrBuffer = ""
        lastStderr = s
        return s
    }



    /// 인스턴스용 환경 — 정적 버전에 캐시된 기본 디바이스를 얹는다.
    /// SANE_DEFAULT_DEVICE 가 있으면 scanimage -L 가 probe 없이 그 장치를 바로 연다.
    func makeSaneEnvironmentWithDefaultDevice() -> [String: String] {
        var env = Self.makeSaneEnvironment()
        // 캐시된 주소가 유효하면 기본 디바이스로 주입.
        if let cached = cachedAddress,
           Date().timeIntervalSince(cachedAddressAt) < addressCacheTTL {
            env["SANE_DEFAULT_DEVICE"] = cached
        }
        return env
    }


}
