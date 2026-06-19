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
    static let positiveHDRBrightnessBrackets = [100, 30, -45]

    /// nil이면 PATH에서 `scanimage`를 찾는다.
    public init(scanimagePath: String? = nil) {
        self.scanimage = scanimagePath ?? Self.findScanimage()
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

    /// scanimage -A 출력을 ScannerCapabilities로 변환한다.
    /// 형식 예: `--resolution 7200|3600|2400|1200|600dpi [600]`
    static func parseCapabilities(_ dump: String) -> ScannerCapabilities {
        var resolutions: [Resolution] = []
        var modes: [ColorMode] = []
        var bitDepths: [BitDepth] = []
        var supportsTransparency = false

        for raw in dump.split(separator: "\n") {
            let line = String(raw)
            // --mode Color|Gray [Gray]
            if let r = captureAfter(line, option: "--mode") {
                let opts = r.split(whereSeparator: { $0 == "|" || $0 == " " })
                    .map { String($0).lowercased() }
                if opts.contains("color") { modes.append(.color) }
                if opts.contains("gray")  { modes.append(.gray) }
                if opts.contains("lineart") { modes.append(.lineart) }
            }
            // --depth 16 [16]
            if let r = captureAfter(line, option: "--depth") {
                for tok in r.split(whereSeparator: { $0 == " " || $0 == "|" }) {
                    if let v = Int(tok), let d = BitDepth(rawValue: v) { bitDepths.append(d) }
                }
            }
            // --resolution 7200|3600|2400|1200|600dpi [600]
            if let r = captureAfter(line, option: "--resolution") {
                for tok in r.split(whereSeparator: { $0 == "|" || $0 == " " }) {
                    let cleaned = tok.replacingOccurrences(of: "dpi", with: "")
                    if let v = Int(cleaned) { resolutions.append(Resolution(v)) }
                }
            }
            // --source Transparency Adapter [Transparency Adapter]
            if let r = captureAfter(line, option: "--source") {
                if r.localizedCaseInsensitiveContains("transparency") || r.localizedCaseInsensitiveContains("tpa") {
                    supportsTransparency = true
                }
            }
        }
        // 디폴트 보정 (비어 있으면 8200i 검증값)
        if resolutions.isEmpty { resolutions = [.r900, .r1800, .r3600, .r7200] }
        if modes.isEmpty { modes = [.color, .gray] }
        if bitDepths.isEmpty { bitDepths = [.eight, .sixteen] }

        return ScannerCapabilities(
            supportedResolutions: resolutions.sorted(),
            supportedModes: modes,
            supportedBitDepths: bitDepths,
            supportsPreview: true,
            supportsTransparency: supportsTransparency,
            // genesys 백엔드는 8200i에서 IR 옵션을 노출하지 않는다. (Phase 5 과제)
            supportsInfrared: false,
            supportsMultiExposure: false,
            supportsScanArea: true,
            supportsLampWarmupStatus: true,
            outputFormats: ["tiff", "pnm"]
        )
    }

    private static func captureAfter(_ line: String, option: String) -> String? {
        guard let r = line.range(of: option) else { return nil }
        let after = line[r.upperBound...]
        // ` Color|Gray [Gray]` → "Color|Gray [Gray]"
        return after.trimmingCharacters(in: .whitespaces)
    }

    // MARK: scan
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

        if Self.shouldUseBracketedScan(options) {
            return try await startBracketedFullScan(options, outputURL: outURL, progress: progress)
        }

        // 중요: USB 장치 주소(libusb:bus:dev)는 스캐너 리셋/재열거로 매번 바뀐다.
        // scannerID에 박힌 과거 주소로 open하면 "Invalid argument"로 실패한다.
        // 따라서 스캔 직전에 반드시 scanimage -L 로 현재 주소를 다시 얻는다.
        let devname = await resolveDeviceAddress(for: options)
        let args = makeScanimageArgs(devname: devname, options: options)

        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))
        progress(ScanProgress(phase: .scanningRGB, fraction: 0.1, message: "Scanning RGB"))

        let t0 = Date()
        do {
            let ec = try await runScanimageTo(args: args, outputURL: outURL, progress: progress)
            guard ec == 0 else {
                let stderr = takeStderr()
                let detail = stderr.isEmpty ? "scanimage exit \(ec)" : "scanimage exit \(ec): \(stderr)"
                self.lastError = ScannerError(.ioFailure, detail)
                throw lastError!
            }
        } catch let err as ScannerError {
            throw err
        } catch {
            self.lastError = ScannerError(.ioFailure, error.localizedDescription)
            throw error
        }
        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "Scan complete"))

        // 결과 메타데이터는 ImageIO로 채운다.
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

    private func startBracketedFullScan(
        _ options: ScanOptions,
        outputURL: URL,
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async throws -> ScanResult {
        let t0 = Date()
        let labels = ["shadows", "midtones", "highlights"]
        let urls = labels.map { Self.makeTempURL(prefix: "negaflow_hdr_\($0)", suffix: ".tiff") }
        defer {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }

        progress(ScanProgress(phase: .warmingLamp, fraction: 0.02, message: "Warming lamp"))

        for (index, brightness) in Self.positiveHDRBrightnessBrackets.enumerated() {
            let label = labels[index]
            let devname = await resolveDeviceAddress(for: options)
            let args = makeScanimageArgs(devname: devname, options: options, brightness: brightness)
            let fraction = 0.08 + (Double(index) * 0.27)
            progress(ScanProgress(
                phase: .scanningRGB,
                fraction: fraction,
                message: "HDR \(label) scan"
            ))

            do {
                let ec = try await runScanimageTo(args: args, outputURL: urls[index], progress: progress)
                guard ec == 0 else {
                    let stderr = takeStderr()
                    let detail = stderr.isEmpty
                        ? "scanimage exit \(ec) during HDR \(label) scan"
                        : "scanimage exit \(ec) during HDR \(label) scan: \(stderr)"
                    self.lastError = ScannerError(.ioFailure, detail)
                    throw lastError!
                }
            } catch let err as ScannerError {
                throw err
            } catch {
                self.lastError = ScannerError(.ioFailure, error.localizedDescription)
                throw error
            }
        }

        progress(ScanProgress(phase: .processingNegative, fraction: 0.88, message: "Merging HDR scan"))
        do {
            try Self.mergeBracketedScans(
                shadowURL: urls[0],
                midtoneURL: urls[1],
                highlightURL: urls[2],
                outputURL: outputURL
            )
        } catch {
            self.lastError = ScannerError(.ioFailure, "HDR merge failed: \(error.localizedDescription)")
            throw lastError!
        }

        let duration = Date().timeIntervalSince(t0)
        progress(ScanProgress(phase: .complete, fraction: 1.0, message: "HDR scan complete"))

        let (w, h) = Self.imageSize(at: outputURL)
        return ScanResult(
            rawFileURL: outputURL,
            width: w, height: h,
            resolution: options.resolution,
            bitDepth: options.bitDepth,
            hasInfraredChannel: false,
            scanDuration: duration,
            backendUsed: .sane,
            warnings: ["HDR bracket scan: brightness +100/+30/-45"]
        )
    }

    private static func shouldUseBracketedScan(_ options: ScanOptions) -> Bool {
        options.resolution != .preview
            && !options.filmType.requiresInversion
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

    private func makeScanimageArgs(
        devname: String,
        options: ScanOptions,
        brightness: Int? = nil
    ) -> [String] {
        var args: [String] = ["-d", devname]
        args += ["--mode", options.colorMode == .gray ? "Gray" : "Color"]
        args += ["--source", "Transparency Adapter"]
        if let brightness {
            args += ["--brightness=\(brightness)"]
        }
        if options.resolution == .preview { args += ["--preview=yes"] }
        if options.resolution.dpi > 0 { args += ["--resolution", "\(options.resolution.dpi)"] }
        args += ["--depth", "\(options.bitDepth.rawValue)"]
        args += ["-x", String(format: "%.2f", options.scanArea.widthMM),
                 "-y", String(format: "%.2f", options.scanArea.heightMM)]
        args += ["--format=tiff"]
        return args
    }

    private static func mergeBracketedScans(
        shadowURL: URL,
        midtoneURL: URL,
        highlightURL: URL,
        outputURL: URL
    ) throws {
        guard let shadow = CIImage(contentsOf: shadowURL),
              let midtone = CIImage(contentsOf: midtoneURL),
              let highlight = CIImage(contentsOf: highlightURL) else {
            throw ScannerError(.ioFailure, "HDR bracket TIFF 로드 실패")
        }

        let extent = midtone.extent.integral
        let shadowImage = shadow.cropped(to: extent)
        let midtoneImage = midtone.cropped(to: extent)
        let highlightImage = highlight.cropped(to: extent)

        let luma = midtoneImage.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ]).cropped(to: extent)

        let darkMask = clampMask(
            luma.applyingFilter("CIColorInvert")
                .applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 0,
                    "inputContrast": 1.7,
                    "inputBrightness": -0.28,
                ])
        ).cropped(to: extent)

        let brightMask = clampMask(
            luma.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 0,
                "inputContrast": 1.7,
                "inputBrightness": -0.28,
            ])
        ).cropped(to: extent)

        let shadowMerged = shadowImage.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": midtoneImage,
            "inputMaskImage": darkMask,
        ]).cropped(to: extent)

        let merged = highlightImage.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": shadowMerged,
            "inputMaskImage": brightMask,
        ]).cropped(to: extent)
        let toneMapped = merged.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.75,
            "inputHighlightAmount": 0.28,
        ]).cropped(to: extent)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = context.createCGImage(toneMapped, from: toneMapped.extent, format: .RGBAh, colorSpace: colorSpace) else {
            throw ScannerError(.ioFailure, "HDR 병합 이미지 생성 실패")
        }

        try? FileManager.default.removeItem(at: outputURL)
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.tiff" as CFString, 1, nil) else {
            throw ScannerError(.ioFailure, "HDR TIFF 출력 생성 실패")
        }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScannerError(.ioFailure, "HDR TIFF 출력 저장 실패")
        }
    }

    private static func clampMask(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
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

    static func findScanimage() -> String {
        let candidates = [
            "/opt/homebrew/bin/scanimage",
            "/usr/local/bin/scanimage",
            "/usr/bin/scanimage",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        return "scanimage"
    }

    /// SANE 설정 디렉토리(dll.conf, genesys.conf 등이 있는 곳)를 찾는다.
    /// Homebrew 로 설치한 경우 기본 컴파일 경로에 없으므로 SANE_CONFIG_DIR 가 필요하다.
    /// scanimage 가 이 디렉토리를 못 찾으면 "open of device failed: Invalid argument".
    static func findSaneConfigDir() -> String? {
        // 1) 환경변수가 이미 있으면 그대로 사용.
        if let v = ProcessInfo.processInfo.environment["SANE_CONFIG_DIR"],
           FileManager.default.fileExists(atPath: v) { return v }
        // 2) Homebrew 표준 경로 후보.
        let candidates = [
            "/opt/homebrew/etc/sane.d",
            "/usr/local/etc/sane.d",
            "/etc/sane.d",
        ]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return c }
        }
        return nil
    }

    /// GUI .app 환경에서는 기본 PATH 가 /usr/bin:/bin 뿐이라 scanimage 가
    /// 의존하는 동적 라이브러리(libsane)나 SANE_CONFIG_DIR 를 못 찾는다.
    /// 따라서 Process 에 명시적으로 환경을 주입한다.
    static func makeSaneEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Homebrew 경로를 PATH 앞에 추가(libsane*.dylib 해석 + 일반 도구 접근).
        let brew = "/opt/homebrew/bin:/opt/homebrew/sbin"
        let existing = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "\(brew):\(existing)"
        // SANE 설정 디렉토리.
        if let cfg = findSaneConfigDir() {
            env["SANE_CONFIG_DIR"] = cfg
        }
        // 백엔드 라이브러리 경로(SANE가 .so/.dylib 를 찾는 위치).
        let libdirs = ["/opt/homebrew/lib/sane", "/usr/local/lib/sane"]
            .filter { FileManager.default.fileExists(atPath: $0) }
        if !libdirs.isEmpty, env["SANE_BACKENDS_PATH"] == nil {
            env["SANE_BACKENDS_PATH"] = libdirs.joined(separator: ":")
        }
        return env
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

    public static func makeTempURL(prefix: String, suffix: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("\(prefix)_\(UUID().uuidString)\(suffix)")
    }

    public static func imageSize(at url: URL) -> (Int, Int) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let w = props["PixelWidth"] as? Int,
              let h = props["PixelHeight"] as? Int
        else { return (0, 0) }
        return (w, h)
    }
}
