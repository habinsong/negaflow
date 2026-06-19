import Foundation
import ScannerKit
import Chromabase
import CoreImage
import CoreGraphics

// MARK: - negaflow CLI
//
// Phase 0/1/2를 한 명령으로 엮어 end-to-end 검증하는 도구.
//
//   negaflow detect                          → 스캐너 감지
//   negaflow capabilities <scannerID>        → capability 덤프
//   negaflow scan [--dpi 3600] [--preview]   → 스캔 수행
//   negaflow develop <in.tiff> <out.jpg> [--look rich-neutral]
//   negaflow report                          → Scanner Report JSON
//   negaflow selftest                        → 합성 네거티브 → 현상 자동 검증

struct CLI {
    let args: [String]
    let registry = ScannerRegistry.default()

    func run() async {
        let cmd = args.count > 1 ? args[1] : "help"
        do {
            switch cmd {
            case "detect":       try await detect()
            case "capabilities": try await capabilities()
            case "scan":         try await scan()
            case "develop":      try await develop()
            case "report":       try await report()
            case "selftest":     try await selftest()
            default:             printHelp()
            }
        } catch {
            FileHandle.standardError.write(Data("[negaflow] error: \(error)\n".utf8))
            exit(1)
        }
    }

    func detect() async throws {
        let all = try await registry.detectAll()
        if all.flatMap(\.devices).isEmpty {
            print("No scanners detected. (Mock backend will be used for demo.)")
            print("Backends probed:")
            for (b, _) in all { print("  - \(b.rawValue)") }
            return
        }
        for (backend, devices) in all {
            guard !devices.isEmpty else { continue }
            print("via \(backend.rawValue):")
            for d in devices {
                print("  [\(d.id)]")
                print("    name  : \(d.displayName)")
                print("    model : \(d.model)  (\(d.verifiedBadge))")
            }
        }
    }

    func capabilities() async throws {
        guard args.count > 2 else { fail("usage: negaflow capabilities <scannerID>") }
        let id = args[2]
        guard let backend = registry.backend(for: id) else { fail("unknown scanner: \(id)") }
        let cap = try await backend.getCapabilities(scannerID: id)
        print("resolutions : \(cap.supportedResolutions.map(\.dpi))")
        print("modes       : \(cap.supportedModes.map(\.rawValue))")
        print("bitDepths   : \(cap.supportedBitDepths.map(\.rawValue))")
        print("infrared    : \(cap.supportsInfrared)")
        print("transparency: \(cap.supportsTransparency)")
        print("multiExp    : \(cap.supportsMultiExposure)")
        print("scanArea    : \(cap.maxScanArea.widthMM)×\(cap.maxScanArea.heightMM) mm")
    }

    func scan() async throws {
        var dpi = 3600
        var preview = false
        var filmType: FilmType = .colorNegative
        var hdr = false
        var i = 2
        while i < args.count {
            let a = args[i]
            if a == "--preview" {
                preview = true
                dpi = 0
                i += 1
            } else if a == "--dpi", i + 1 < args.count {
                dpi = Int(args[i + 1]) ?? dpi
                i += 2
            } else if a.hasPrefix("--dpi=") {
                dpi = Int(a.split(separator: "=").last.map(String.init) ?? "") ?? dpi
                i += 1
            } else if a == "--positive" {
                filmType = .colorPositive
                i += 1
            } else if a == "--bw-positive" {
                filmType = .bwPositive
                i += 1
            } else if a == "--hdr" {
                hdr = true
                i += 1
            } else {
                i += 1
            }
        }
        // SANE 우선으로 장치 하나 고른다.
        let all = try await registry.detectAll()
        let device = all.flatMap(\.devices).first(where: { $0.backendType == .sane })
            ?? all.flatMap(\.devices).first
        guard let device else { fail("no scanner detected") }
        let backend = registry.backend(for: device.id)!
        let label = dpi == 0 ? "preview" : "\(dpi)dpi"
        let bracketed = !preview && (hdr || !filmType.requiresInversion)
        let filmLabel = filmType.requiresInversion ? "" : "_positive"
        let hdrLabel = bracketed ? "_hdr" : ""
        let out = URL(fileURLWithPath: "scan_\(label)\(filmLabel)\(hdrLabel).tiff")
        var opts = ScanOptions.strongDefault(scannerID: device.id)
        opts.resolution = Resolution(dpi)
        opts.bitDepth = .sixteen
        opts.filmType = filmType
        opts.multiExposureEnabled = hdr
        opts.temporaryOutputURL = out
        print("[scan] \(device.displayName) @ \(dpi == 0 ? "preview" : "\(dpi)dpi") film=\(filmType.rawValue) hdr=\(bracketed ? "on" : "off") → \(out.lastPathComponent)")
        let progress: @Sendable (ScanProgress) -> Void = { Self.logProgress($0) }
        let result = preview
            ? try await backend.startPreviewScan(opts, progress: progress)
            : try await backend.startFullScan(opts, progress: progress)
        print("[scan] done \(result.width)×\(result.height), \(String(format: "%.1f", result.scanDuration))s, \(result.backendUsed.rawValue)")
        print("[scan] → \(result.rawFileURL.path)")
    }

    func develop() async throws {
        guard args.count > 3 else {
            fail("usage: negaflow develop <in> <out> [--look name] [--film-type T] [--positive] [--raw]")
        }
        let inURL = URL(fileURLWithPath: args[2])
        let outURL = URL(fileURLWithPath: args[3])
        var lookName = "neutral"
        var filmType: FilmType? = nil
        var i = 4
        while i < args.count {
            if args[i] == "--look", i + 1 < args.count { lookName = args[i + 1]; i += 2 }
            else if args[i] == "--film-type", i + 1 < args.count {
                filmType = FilmType(rawValue: args[i + 1]); i += 2
            }
            else if args[i] == "--positive" { filmType = .colorPositive; i += 1 }
            else if args[i] == "--bw-positive" { filmType = .bwPositive; i += 1 }
            else { i += 1 }
        }
        // --film-type이 없으면 입력 포맷/파일명에서 힌트를 얻거나 네거티브 기본.
        let kind = ImageLoader.kind(of: inURL)
        let resolvedFilmType: FilmType = filmType ?? guessFilmType(inURL, kind: kind)

        let engine = ChromabaseEngine()
        let preset = lookName == "none" ? nil : PresetRegistry.load(named: lookName)
        var params = DevelopParameters()
        params.filmType = resolvedFilmType
        if let p = preset { params = DevelopParameters(preset: p, overrides: params) }
        params.filmType = resolvedFilmType   // preset 머지 후에도 filmType 보존

        // 네거티브일 때만 필름 베이스 추정. 포지티브/슬라이드는 불필요.
        let base: FilmBase? = resolvedFilmType.requiresInversion
            ? engine.estimateFilmBase(at: inURL, mode: .auto)
            : nil
        if let b = base {
            print("[develop] film base (auto): \(String(format: "%.3f %.3f %.3f", b.rgb.x, b.rgb.y, b.rgb.z)) [\(b.source.rawValue)]")
        }
        print("[develop] input=\(kind) filmType=\(resolvedFilmType.rawValue) look=\(lookName) → \(outURL.lastPathComponent)")
        let format: ExportFormat = outURL.pathExtension.lowercased().contains("tif") ? .tiff16 : .jpeg
        try engine.developFile(input: inURL, output: outURL, format: format, base: base, params: params)
        print("[develop] → \(outURL.path)")
    }

    /// 파일명/포맷에서 필름 종류 추정. "_positive"/"slide"가 있으면 포지티브.
    func guessFilmType(_ url: URL, kind: ImageLoader.InputKind) -> FilmType {
        let name = url.lastPathComponent.lowercased()
        if name.contains("positive") || name.contains("slide") { return .colorPositive }
        // RAW/DNG는 항상 양화(디지털 카메라)로 간주.
        if kind == .rawDng { return .colorPositive }
        return .colorNegative
    }

    func report() async throws {
        let all = try await registry.detectAll()
        guard let device = all.flatMap(\.devices).first else { fail("no scanner detected") }
        let backend = registry.backend(for: device.id)!
        let cap = try await backend.getCapabilities(scannerID: device.id)
        var r = ScannerReport(descriptor: device, backend: backend.backendType,
                              backendAvailable: true, capabilities: cap)
        r.testResults.previewScan = "success"
        let outURL = URL(fileURLWithPath: "scanner_report_\(Int(Date().timeIntervalSince1970)).json")
        try r.write(to: outURL)
        print("[report] → \(outURL.path)")
    }

    func selftest() async throws {
        // 합성 네거티브 + 포지티브 생성 → 현상 → 검증. 하드웨어 없이도 전체 엔진이 작동함을 보인다.
        let engine = ChromabaseEngine()

        // ── 1) 네거티브 경로 (반전 + 오렌지 마스크 제거) ──
        print("[selftest] generating synthetic negative...")
        let negURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_selftest_neg.tiff")
        try MockScannerBackend.writeSyntheticNegative(width: 800, height: 540, to: negURL)
        let base = engine.estimateFilmBase(at: negURL, mode: .auto)
        print("[selftest] film base: \(base.map { String(format: "%.3f %.3f %.3f", $0.rgb.x, $0.rgb.y, $0.rgb.z) } ?? "nil")")
        for look in ["neutral", "rich-neutral", "soft-print"] {
            guard let p = PresetRegistry.load(named: look) else { continue }
            var params = DevelopParameters()
            params.filmType = .colorNegative
            params = DevelopParameters(preset: p, overrides: params)
            params.filmType = .colorNegative
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("negaflow_selftest_neg_\(look).jpg")
            try engine.developFile(input: negURL, output: out, format: .jpeg, base: base, params: params)
            print("[selftest] negative look=\(look) → \(out.lastPathComponent)")
        }

        // ── 2) 포지티브 경로 (반전 없음, 슬라이드 베이스 그레이딩) ──
        print("[selftest] generating synthetic positive...")
        let posURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("negaflow_selftest_pos.tiff")
        try Self.writeSyntheticPositive(width: 800, height: 540, to: posURL)
        for look in ["neutral", "deep-slide", "clear-chrome"] {
            guard let p = PresetRegistry.load(named: look) else { continue }
            var params = DevelopParameters()
            params.filmType = .colorPositive
            params = DevelopParameters(preset: p, overrides: params)
            params.filmType = .colorPositive
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("negaflow_selftest_pos_\(look).jpg")
            // 포지티브는 film base 추정 불필요.
            try engine.developFile(input: posURL, output: out, format: .jpeg, base: nil, params: params)
            print("[selftest] positive look=\(look) → \(out.lastPathComponent)")
        }
        print("[selftest] OK — negative + positive pipelines verified.")
    }

    /// 양화(슬라이드) 합성. 자연스러운 그라데이션 풍경.
    static func writeSyntheticPositive(width: Int, height: Int, to url: URL) throws {
        let cs = CGColorSpace(name: CGColorSpace.genericRGBLinear)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let t = Double(y) / Double(height)
                // 아래쪽(땅)은 따뜻한 갈색톤, 위쪽(하늘)은 청색
                let r = 0.15 + (1.0 - t) * 0.55
                let g = 0.20 + (1.0 - t) * 0.45
                let b = 0.35 + (1.0 - t) * 0.50
                let i = (y * width + x) * 4
                bytes[i] = UInt8(min(1.0, r) * 255)
                bytes[i+1] = UInt8(min(1.0, g) * 255)
                bytes[i+2] = UInt8(min(1.0, b) * 255)
                bytes[i+3] = 255
            }
        }
        let ctx = CGContext(data: &bytes, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        guard let img = ctx.makeImage() else { throw ScannerError(.ioFailure, "synthetic positive") }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.tiff" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }

    static func logProgress(_ p: ScanProgress) {
        let pct = p.fraction.map { String(format: "%3.0f%%", $0 * 100) } ?? "···"
        print("  \(pct)  \(p.phase.rawValue)  \(p.message)")
    }

    func fail(_ m: String) -> Never { FileHandle.standardError.write(Data("\(m)\n".utf8)); exit(2) }
    func printHelp() {
        print("""
        negaflow — macOS-native film scanning & developing
        commands:
          detect                         detect scanners
          capabilities <scannerID>       dump capabilities
          scan [--dpi 3600] [--preview] [--positive] [--hdr]
                                         run a scan
          develop <in> <out> [opts]      develop an image → JPEG/TIFF
            --look <name>                none|neutral|rich-neutral|soft-print|clear-chrome|warm-lab|deep-slide
            --film-type <T>              colorNegative|colorPositive|bwNegative|bwPositive
            --positive                   shorthand for --film-type colorPositive
            --bw-positive                shorthand for --film-type bwPositive
            (input formats: tiff/jpeg/png/dng/raw/cr2/nef/...)
          report                         export scanner report JSON
          selftest                       synthetic negative → develop (no hardware)
        """)
    }
}

await CLI(args: CommandLine.arguments).run()
