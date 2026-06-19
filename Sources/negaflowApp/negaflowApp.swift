import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

// MARK: - negaflow SwiftUI App
//
// 순정 macOS 앱 톤(Apple Photos / Image Capture 느낌).
// NavigationSplitView = 자동 Liquid Glass. AI SaaS/대시보드 냄새 금지.
// 엔진(색감)은 건드리지 않는다 — UI/UX만.
@main
struct negaflowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1180, minHeight: 720)
                .environmentObject(AppModel())
        }
    }
}

// MARK: - AppModel
@MainActor
final class AppModel: ObservableObject {
    let saneBackend = SANEBackend()
    let mockBackend = MockScannerBackend()

    @Published var demoMode: Bool = false
    @Published var devices: [ScannerDescriptor] = []
    @Published var selectedDeviceID: String?
    @Published var isDetecting: Bool = false

    // 진행/상태(전역)
    @Published var scanPhase: ScanPhase = .idle
    @Published var scanFraction: Double = 0
    @Published var statusMessage: String = "Idle"
    @Published var isScanning: Bool = false
    @Published var batchTotal: Int = 0
    @Published var batchIndex: Int = 0

    // 롤/프레임
    @Published var frames: [ScanFrame] = []
    @Published var selectedFrameID: UUID?

    // 스캔 옵션(다음 스캔에 적용)
    @Published var filmType: FilmType = .colorNegative
    @Published var resolutionChoice: Resolution = .r3600

    @Published var capabilities: ScannerCapabilities?
    @Published var diagnostics: String = ""

    let presets: [LookPreset] = PresetRegistry.loadAll()

    var backend: ScannerBackend? { demoMode ? mockBackend : (hasSANE ? saneBackend : nil) }
    var hasSANE: Bool { devices.contains { $0.backendType == .sane } }
    var hasScanner: Bool { backend != nil }
    var canScan: Bool { hasScanner && !isScanning }
    var effectiveScannerID: String? {
        if demoMode { return "mock" }
        return devices.first(where: { $0.backendType == .sane })?.id
    }
    var selectedFrame: ScanFrame? {
        guard let id = selectedFrameID else { return nil }
        return frames.first(where: { $0.id == id })
    }

    init() {}

    // MARK: detection
    func refreshDevices() async {
        isDetecting = true
        defer { isDetecting = false }
        _ = SaneConfigTuner.tune()   // dll.conf 최적화(idempotent)
        saneBackend.invalidateAddressCache()
        let sane = (try? await saneBackend.detectScanners()) ?? []
        devices = sane
        if hasSANE, selectedDeviceID == nil {
            selectedDeviceID = sane.first?.id
            await loadCapabilities()
        }
        statusMessage = !hasSANE ? (demoMode ? "Demo 모드" : "스캐너 연결 대기 중") : "Ready"
    }

    func toggleDemo(_ on: Bool) {
        demoMode = on
        if on { selectedDeviceID = "mock"; Task { await loadCapabilities() }; statusMessage = "Demo 모드" }
        else { statusMessage = hasSANE ? "Ready" : "스캐너 연결 대기 중" }
    }

    func loadCapabilities() async {
        guard let id = effectiveScannerID, let b = backend else { return }
        capabilities = try? await b.getCapabilities(scannerID: id)
    }

    // MARK: scan (단일 + 배치)
    func runScan(preview: Bool) async {
        await scanFrames(count: 1, preview: preview)
    }

    /// N프레임 연속 스캔. 한 번에 하나만(currentProcess 단일 슬롯).
    /// 배치 진행률 = (frameIndex + frameFraction) / totalFrames 로 리매핑.
    func scanFrames(count: Int, preview: Bool) async {
        guard let id = effectiveScannerID, let backend = backend else {
            statusMessage = "스캐너가 없습니다 — USB를 연결하거나 Demo 모드를 켜세요."
            return
        }
        batchTotal = count
        isScanning = true
        for i in 0..<count {
            batchIndex = i
            var opts: ScanOptions
            if preview {
                opts = ScanOptions.preview(scannerID: id, filmType: filmType)
            } else {
                opts = ScanOptions.strongDefault(scannerID: id)
                opts.resolution = resolutionChoice
                opts.bitDepth = .sixteen
                opts.filmType = filmType
                opts.multiExposureEnabled = !filmType.requiresInversion
            }
            opts.temporaryOutputURL = SANEBackend.makeTempURL(prefix: "negaflow_app", suffix: ".tiff")
            scanPhase = preview ? .previewScanning : .scanningRGB
            do {
                let remap: @Sendable (ScanProgress) -> ScanProgress = { p in
                    var q = p
                    if let f = p.fraction {
                        let total = Double(count)
                        q.fraction = (Double(i) + f) / total
                    }
                    return q
                }
                let result = preview
                    ? try await backend.startPreviewScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(remap(p)) }
                    })
                    : try await backend.startFullScan(opts, progress: { [weak self] p in
                        Task { @MainActor in self?.update(remap(p)) }
                    })
                let frame = ScanFrame(scanIndex: frames.count + 1, rawScanURL: result.rawFileURL, filmType: filmType)
                frame.preset = presets.first(where: { $0.id == "neutral" })
                frame.params.filmType = filmType
                frames.append(frame)
                selectedFrameID = frame.id
                statusMessage = "Frame \(frame.scanIndex) 스캔 완료: \(result.width)×\(result.height)"
                await developFrame(frame)
            } catch {
                statusMessage = "Frame \(i+1) 스캔 오류: \(error.localizedDescription)"
                scanPhase = .error
                break
            }
        }
        batchTotal = 0
        batchIndex = 0
        isScanning = false
        if scanPhase != .error {
            scanPhase = .complete
            statusMessage = "\(count)프레임 스캔 완료"
        }
    }

    func cancelScan() async {
        await backend?.cancelScan()
        isScanning = false
        batchTotal = 0
        scanPhase = .idle
        statusMessage = "스캔 취소됨"
    }

    func deleteFrame(_ frame: ScanFrame) {
        frames.removeAll { $0.id == frame.id }
        if selectedFrameID == frame.id { selectedFrameID = frames.last?.id }
    }

    // MARK: develop (엔진 호출 — 색감 로직은 그대로)
    func developFrame(_ frame: ScanFrame) async {
        frame.isDeveloping = true
        scanPhase = .processingNegative
        let engine = ChromabaseEngine()
        frame.params.filmType = frame.filmType
        let base: FilmBase? = frame.filmType.requiresInversion
            ? engine.estimateFilmBase(at: frame.rawScanURL, mode: frame.params.baseEstimationMode,
                                      manual: frame.params.manualBaseRGB)
            : nil
        frame.baseRGB = base?.rgb
        guard let input = engine.loadImage(frame.rawScanURL) else {
            statusMessage = "이미지 로드 실패: \(frame.rawScanURL.lastPathComponent)"
            scanPhase = .error
            frame.isDeveloping = false
            return
        }
        loadRawPreview(frame)
        var effectiveParams: DevelopParameters
        if let preset = frame.preset { effectiveParams = DevelopParameters(preset: preset, overrides: frame.params) }
        else { effectiveParams = frame.params }
        effectiveParams.filmType = frame.filmType
        effectiveParams.imageTransform = frame.imageTransform
        let out = engine.develop(image: input, base: base, params: effectiveParams)
        // developCurrent 의 sRGB working space 통일(흰 화면 버그 방지) — 그대로 유지.
        let ctx = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        if let cg = ctx.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: cs) {
            frame.developedImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        scanPhase = .complete
        frame.isDeveloping = false
        statusMessage = "현상 완료"
    }

    func loadRawPreview(_ frame: ScanFrame) {
        let engine = ChromabaseEngine()
        guard let input = engine.loadImage(frame.rawScanURL) else { return }
        let image = ImageTransformStage.apply(to: input, transform: frame.imageTransform)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        if let cg = ctx.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: cs) {
            frame.rawPreviewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    func exportFrame(_ frame: ScanFrame, to url: URL, format: ExportFormat, writeSidecar: Bool = true) {
        let engine = ChromabaseEngine()
        frame.params.filmType = frame.filmType
        let base: FilmBase? = frame.filmType.requiresInversion
            ? engine.estimateFilmBase(at: frame.rawScanURL, mode: frame.params.baseEstimationMode,
                                      manual: frame.params.manualBaseRGB)
            : nil
        var effectiveParams = frame.preset.map { DevelopParameters(preset: $0, overrides: frame.params) } ?? frame.params
        effectiveParams.filmType = frame.filmType
        effectiveParams.imageTransform = frame.imageTransform
        let meta = ExportMeta(
            scannerModel: devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : nil),
            resolutionDPI: frame.developedImage != nil ? resolutionChoice.dpi : nil,
            filmType: frame.filmType.rawValue,
            software: "negaflow 0.1.0"
        )
        do {
            try engine.developFile(input: frame.rawScanURL, output: url, format: format,
                                   base: base, params: effectiveParams, metadata: meta)
            if writeSidecar { writeSidecarFor(frame, exportURL: url, format: format, base: base) }
            statusMessage = "내보내기 완료 → \(url.lastPathComponent)"
        } catch {
            statusMessage = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    /// 프레임의 현상 파라미터/transform/crop/base를 sidecar JSON 으로 저장.
    /// raw 스캔 옆(<name>.negaflow.json) + export 옆(<name>.negaflow.json) 둘 다.
    func writeSidecarFor(_ frame: ScanFrame, exportURL: URL?, format: ExportFormat, base: FilmBase?) {
        var s = Sidecar(filmType: frame.filmType, parameters: frame.params)
        s.scannerModel = devices.first(where: { $0.backendType == .sane })?.displayName
        s.backendUsed = (backend?.backendType).map { $0.rawValue }
        s.scanResolution = resolutionChoice.dpi
        s.bitDepth = 16
        s.presetName = frame.preset?.id
        if let c = frame.imageTransform.cropRect {
            s.crop = Sidecar.CropRect(x: c.x, y: c.y, w: c.z, h: c.w)
        }
        if let b = base { s.baseSample = Sidecar.BaseSample(b) }
        // raw 스캔 옆.
        let rawSidecar = rawSidecarURL(for: frame.rawScanURL)
        try? s.write(to: rawSidecar)
        // export 파일 옆(export 시).
        if let exportURL = exportURL {
            let exportSidecar = exportURL.deletingPathExtension()
                .appendingPathExtension("negaflow.json")
            var s2 = s
            s2.exportHistory.append(Sidecar.ExportRecord(
                path: exportURL.path, format: format.rawValue, at: Date()))
            try? s2.write(to: exportSidecar)
        }
    }

    /// raw 스캔 옆의 sidecar 경로.
    func rawSidecarURL(for rawURL: URL) -> URL {
        rawURL.deletingPathExtension().appendingPathExtension("negaflow.json")
    }

    func runDiagnostics() async {
        guard let id = effectiveScannerID, let b = backend else { diagnostics = "활성 스캐너가 없습니다."; return }
        let cap = (try? await b.getCapabilities(scannerID: id)) ?? ScannerCapabilities()
        diagnostics = """
        Scanner   : \(devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : id))
        Backend   : \(b.backendType.rawValue)
        Resol.    : \(cap.supportedResolutions.map(\.dpi))
        Modes     : \(cap.supportedModes.map(\.rawValue))
        BitDepth  : \(cap.supportedBitDepths.map(\.rawValue))
        IR        : \(cap.supportsInfrared)
        dll tuned : \(SaneConfigTuner.isTuned)
        """
    }

    private func update(_ p: ScanProgress) {
        scanPhase = p.phase
        scanFraction = p.fraction ?? scanFraction
        statusMessage = p.message.isEmpty ? p.phase.rawValue : p.message
    }
}
