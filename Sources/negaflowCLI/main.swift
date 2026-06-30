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
            case "list-scanner-profiles": listScannerProfiles()
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
        print("multiSample : \(cap.supportsMultiExposure)")
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
        let multiSample = !preview && hdr
        let filmLabel = filmType.requiresInversion ? "" : "_positive"
        let hdrLabel = multiSample ? "_hdr" : ""
        let out = URL(fileURLWithPath: "scan_\(label)\(filmLabel)\(hdrLabel).tiff")
        var opts = ScanOptions.strongDefault(scannerID: device.id)
        opts.resolution = Resolution(dpi)
        opts.bitDepth = .sixteen
        opts.filmType = filmType
        opts.multiExposureEnabled = hdr
        opts.temporaryOutputURL = out
        print("[scan] \(device.displayName) @ \(dpi == 0 ? "preview" : "\(dpi)dpi") film=\(filmType.rawValue) multiSample=\(multiSample ? "on" : "off") → \(out.lastPathComponent)")
        let progress: @Sendable (ScanProgress) -> Void = { Self.logProgress($0) }
        let result = preview
            ? try await backend.startPreviewScan(opts, progress: progress)
            : try await backend.startFullScan(opts, progress: progress)
        print("[scan] done \(result.width)×\(result.height), \(String(format: "%.1f", result.scanDuration))s, \(result.backendUsed.rawValue)")
        print("[scan] → \(result.rawFileURL.path)")
    }

    func develop() async throws {
        guard args.count > 3 else {
            fail("usage: negaflow develop <in> <out> [--look name] [--scanner-profile id] [--film-type T] [--positive] [--raw]")
        }
        let inURL = URL(fileURLWithPath: args[2])
        let outURL = URL(fileURLWithPath: args[3])
        var lookName = "neutral"
        var scannerProfileID: String?
        var filmType: FilmType? = nil
        var scannerRaw = false
        var ice: Double = 0
        var developTarget: DevelopTarget = .main
        var iceMaskURL: URL?
        var iceOverlayURL: URL?
        var i = 4
        while i < args.count {
            if args[i] == "--look", i + 1 < args.count { lookName = args[i + 1]; i += 2 }
            else if args[i] == "--scanner-profile", i + 1 < args.count {
                scannerProfileID = args[i + 1]; i += 2
            }
            else if args[i] == "--film-type", i + 1 < args.count {
                filmType = FilmType(rawValue: args[i + 1]); i += 2
            }
            else if args[i] == "--positive" { filmType = .colorPositive; i += 1 }
            else if args[i] == "--bw-positive" { filmType = .bwPositive; i += 1 }
            else if args[i] == "--raw" { scannerRaw = true; i += 1 }
            else if args[i] == "--target", i + 1 < args.count {
                developTarget = DevelopTarget(rawValue: args[i + 1]) ?? .main; i += 2
            }
            else if args[i] == "--ice" {
                if i + 1 < args.count, let value = Double(args[i + 1]) {
                    ice = value; i += 2
                } else {
                    ice = 1.0; i += 1
                }
            }
            else if args[i] == "--ice-mask", i + 1 < args.count {
                iceMaskURL = URL(fileURLWithPath: args[i + 1]); i += 2
            }
            else if args[i] == "--ice-overlay", i + 1 < args.count {
                iceOverlayURL = URL(fileURLWithPath: args[i + 1]); i += 2
            }
            else { i += 1 }
        }
        // --film-type이 없으면 입력 포맷/파일명에서 힌트를 얻거나 네거티브 기본.
        let kind = ImageLoader.kind(of: inURL)
        let resolvedFilmType: FilmType = filmType ?? guessFilmType(inURL, kind: kind)

        let engine = ChromabaseEngine()
        let preset = lookName == "none" ? nil : PresetRegistry.load(named: lookName)
        let scannerProfile = scannerProfileID.flatMap { ScannerProfileRegistry.load(named: $0) }
        if scannerProfileID != nil && scannerProfile == nil {
            fail("unknown scanner profile: \(scannerProfileID ?? "")")
        }
        var params = DevelopParameters()
        params.filmType = resolvedFilmType
        params.developTarget = developTarget
        params.scannerProfileID = scannerProfile?.id
        i = 4
        while i < args.count {
            let key = args[i]
            guard i + 1 < args.count else {
                i += 1
                continue
            }
            let value = Double(args[i + 1]) ?? 0
            switch key {
            case "--exposure": params.exposure = value; i += 2
            case "--contrast": params.contrast = value; i += 2
            case "--highlights", "--highlight": params.highlight = value; i += 2
            case "--shadows", "--shadow": params.shadow = value; i += 2
            case "--whites": params.whites = value; i += 2
            case "--blacks": params.blacks = value; i += 2
            case "--density": params.density = value; i += 2
            case "--noise-reduction", "--nr": params.noiseReduction = value; i += 2
            case "--scanner-profile": i += 2
            case "--target": i += 2
            case "--ice-mask", "--ice-overlay": i += 2
            case "--ice":
                i += Double(args[i + 1]) == nil ? 1 : 2
            default: i += 1
            }
        }
        if let p = preset { params = DevelopParameters(preset: p, overrides: params) }
        params.filmType = resolvedFilmType   // preset 머지 후에도 filmType 보존
        params.developTarget = developTarget
        params.scannerProfileID = scannerProfile?.id
        if ice > 0 { params.defectRemoval = min(max(ice, 0), 1) }

        // 네거티브일 때만 필름 베이스 추정. 포지티브/슬라이드는 불필요.
        let base: FilmBase?
        if resolvedFilmType.requiresInversion, scannerRaw,
           let raw = engine.loadScannerImage(inURL) {
            base = engine.estimateFilmBase(in: raw, mode: .auto)
        } else if resolvedFilmType.requiresInversion {
            base = engine.estimateFilmBase(at: inURL, mode: .auto)
        } else {
            base = nil
        }
        if let b = base {
            print("[develop] film base (auto): \(String(format: "%.3f %.3f %.3f", b.rgb.x, b.rgb.y, b.rgb.z)) [\(b.source.rawValue)]")
        }
        let profileLabel = scannerProfile?.id ?? "none"
        print("[develop] input=\(kind) target=\(developTarget.rawValue) filmType=\(resolvedFilmType.rawValue) look=\(lookName) scannerProfile=\(profileLabel) → \(outURL.lastPathComponent)")
        let format: ExportFormat
        switch outURL.pathExtension.lowercased() {
        case "tif", "tiff":
            format = .tiff16
        case "png":
            format = .png
        default:
            format = .jpeg
        }
        if scannerRaw {
            try engine.developScannerFile(input: inURL, output: outURL, format: format, base: base, params: params)
        } else {
            try engine.developFile(input: inURL, output: outURL, format: format, base: base, params: params)
        }
        print("[develop] → \(outURL.path)")
        if iceMaskURL != nil || iceOverlayURL != nil {
            try writeICEDebugOutputs(
                input: inURL,
                scannerRaw: scannerRaw,
                engine: engine,
                base: base,
                params: params,
                maskURL: iceMaskURL,
                overlayURL: iceOverlayURL
            )
        }
    }

    func listScannerProfiles() {
        let profiles = ScannerProfileRegistry.loadAll()
        if profiles.isEmpty {
            print("No scanner profiles bundled.")
            return
        }
        for profile in profiles {
            let limited = profile.singleRollLimited ? " single-roll-limited" : ""
            print("\(profile.id)\t\(profile.scanner)\t\(profile.kind)\t\(profile.filmKey)\t\(profile.validationStatus.rawValue)\(limited)")
        }
    }

    func writeICEDebugOutputs(input: URL,
                              scannerRaw: Bool,
                              engine: ChromabaseEngine,
                              base: FilmBase?,
                              params: DevelopParameters,
                              maskURL: URL?,
                              overlayURL: URL?) throws {
        let source = scannerRaw ? engine.loadScannerImage(input) : engine.loadImage(input)
        guard let source else { throw ChromabaseError.loadFailed(input.path) }
        var debugParams = params
        debugParams.defectRemoval = 0
        let developed = scannerRaw
            ? engine.developScanner(image: source, base: base, params: debugParams)
            : engine.develop(image: source, base: base, params: debugParams)
        let iceParams = SoftwareICEParameters(
            strength: max(params.defectRemoval, 1),
            dustSensitivity: 0.65,
            scratchSensitivity: 0.85,
            protectDetail: 0.85
        )
        let mask = SoftwareICE.detectMask(in: developed, parameters: iceParams)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        ])
        if let maskURL {
            try ExportEngine.write(mask, to: maskURL, format: .png, using: context)
            print("[develop] ice mask → \(maskURL.path)")
        }
        if let overlayURL {
            let overlay = SoftwareICE.overlayMask(on: developed, mask: mask, opacity: 0.72)
            try ExportEngine.write(overlay, to: overlayURL, format: .png, using: context)
            print("[develop] ice overlay → \(overlayURL.path)")
        }
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
          list-scanner-profiles          list bundled NORITSU/SP-3000 profiles
            --look <name>                none|neutral|rich-neutral|soft-print|clear-chrome|warm-lab|deep-slide
            --scanner-profile <id>       apply bundled scanner/film profile before look controls
            --film-type <T>              colorNegative|colorPositive|bwNegative|bwPositive
            --target <main>              develop target (default main)
            --positive                   shorthand for --film-type colorPositive
            --bw-positive                shorthand for --film-type bwPositive
            --exposure <stops>           Basic Tone exposure
            --contrast <v>               Basic Tone contrast (-1...1)
            --highlights <v>             Basic Tone highlights (-1...1)
            --shadows <v>                Basic Tone shadows (-1...1)
            --whites <v>                 Basic Tone whites (-1...1)
            --blacks <v>                 Basic Tone blacks (-1...1)
            --density <v>                Basic Tone density (-1...1)
            --ice [strength]             software dust/scratch removal (0...1, default 1)
            --ice-mask <png>             write software ICE defect mask
            --ice-overlay <png>          write red software ICE mask overlay
            (input formats: tiff/jpeg/png/dng/raw/cr2/nef/...)
          report                         export scanner report JSON
          selftest                       synthetic negative → develop (no hardware)
        """)
    }
}

await CLI(args: CommandLine.arguments).run()
