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
    static let mockDeviceID = "mock"
    static let mockDisplayName = "Plustek OpticFilm 8200i (Demo)"

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
    @Published var bitDepthChoice: BitDepth = .sixteen
    @Published var colorModeChoice: ColorMode = .color
    @Published var multiExposureEnabled: Bool = false
    @Published private(set) var nextScanOrientation: ImageTransform = .identity

    @Published var capabilities: ScannerCapabilities?
    @Published var diagnostics: String = ""

    let presets: [LookPreset] = PresetRegistry.loadAll()
    private var lastProgressUpdateAt: Date = .distantPast
    private var lastProgressFraction: Double = -1
    private var lastProgressPhase: ScanPhase = .idle
    private var lastProgressMessage: String = ""
    private var activeDevelopmentFrameIDs = Set<UUID>()

    var backend: ScannerBackend? { demoMode ? mockBackend : (hasSANE ? saneBackend : nil) }
    var saneDevices: [ScannerDescriptor] { devices.filter { $0.backendType == .sane } }
    var hasSANE: Bool { devices.contains { $0.backendType == .sane } }
    var hasScanner: Bool { backend != nil }
    var canScan: Bool { hasScanner && !isScanning }
    var effectiveScannerID: String? {
        if demoMode { return Self.mockDeviceID }
        return saneDevices.first(where: { $0.id == selectedDeviceID })?.id ?? saneDevices.first?.id
    }
    var activeScannerDisplayName: String {
        if demoMode { return Self.mockDisplayName }
        return saneDevices.first(where: { $0.id == selectedDeviceID })?.displayName
            ?? saneDevices.first?.displayName
            ?? "스캐너 없음"
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
        if demoMode {
            selectedDeviceID = Self.mockDeviceID
            await loadCapabilities()
        } else if hasSANE {
            if selectedDeviceID == nil || !saneDevices.contains(where: { $0.id == selectedDeviceID }) {
                selectedDeviceID = saneDevices.first?.id
            }
            await loadCapabilities()
        } else {
            selectedDeviceID = nil
            capabilities = nil
        }
        statusMessage = demoMode ? "Demo 모드" : (hasSANE ? "Ready" : "스캐너 연결 대기 중")
    }

    func toggleDemo(_ on: Bool) {
        demoMode = on
        if on {
            selectedDeviceID = Self.mockDeviceID
            statusMessage = "Demo 모드"
        } else {
            selectedDeviceID = saneDevices.first?.id
            statusMessage = hasSANE ? "Ready" : "스캐너 연결 대기 중"
        }
        Task { await loadCapabilities() }
    }

    func loadCapabilities() async {
        guard let id = effectiveScannerID, let b = backend else { return }
        capabilities = try? await b.getCapabilities(scannerID: id)
        if capabilities?.supportsMultiExposure != true {
            multiExposureEnabled = false
        }
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
                opts.bitDepth = bitDepthChoice
                opts.colorMode = colorModeChoice
                opts.filmType = filmType
                opts.multiExposureEnabled = multiExposureEnabled && capabilities?.supportsMultiExposure == true
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
                let frame = ScanFrame(
                    scanIndex: frames.count + 1,
                    rawScanURL: result.rawFileURL,
                    filmType: filmType,
                    initialTransform: nextScanOrientation
                )
                frame.preset = presets.first(where: { $0.id == "neutral" })
                frame.updateParams { $0.filmType = filmType }
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

    func rotate(_ frame: ScanFrame, clockwise: Bool) {
        frame.updateTransform {
            $0.rotation = clockwise
                ? $0.rotation.rotatedClockwise()
                : $0.rotation.rotatedCounterClockwise()
        }
        updateOrientationTemplate(from: frame)
    }

    func flipHorizontally(_ frame: ScanFrame) {
        frame.updateTransform { $0.flipHorizontal.toggle() }
        updateOrientationTemplate(from: frame)
    }

    func flipVertically(_ frame: ScanFrame) {
        frame.updateTransform { $0.flipVertical.toggle() }
        updateOrientationTemplate(from: frame)
    }

    func resetTransform(_ frame: ScanFrame) {
        frame.imageTransform = .identity
        nextScanOrientation = .identity
        Task { await developFrame(frame) }
    }

    private func updateOrientationTemplate(from frame: ScanFrame) {
        nextScanOrientation = frame.imageTransform.orientationTemplate
        Task { await developFrame(frame) }
    }

    // MARK: develop (엔진 호출 — 색감 로직은 그대로)
    func developFrame(_ frame: ScanFrame) async {
        frame.developRevision += 1
        frame.updateParams { $0.filmType = frame.filmType }
        guard activeDevelopmentFrameIDs.insert(frame.id).inserted else { return }
        await renderLatestDevelopment(for: frame)
    }

    private func renderLatestDevelopment(for frame: ScanFrame) async {
        frame.isDeveloping = true
        scanPhase = .processingNegative
        var revision = frame.developRevision

        while true {
            let baseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB
            )
            let snapshot = DevelopFrameSnapshot(
                rawScanURL: frame.rawScanURL,
                filmType: frame.filmType,
                params: frame.params,
                preset: frame.preset,
                imageTransform: frame.imageTransform,
                cachedBase: frame.cachedBaseKey == baseKey ? frame.cachedBase : nil,
                baseKey: baseKey,
                needsRawPreview: frame.rawPreviewImage == nil || frame.rawPreviewTransform != frame.imageTransform
            )

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DevelopFrameRenderer.render(snapshot)
                }.value
                guard frame.developRevision == revision else {
                    revision = frame.developRevision
                    continue
                }
                frame.cachedBase = result.base
                frame.cachedBaseKey = snapshot.baseKey
                frame.baseRGB = result.base?.rgb
                if let rawPreview = result.rawPreview {
                    frame.rawPreviewImage = NSImage(
                        cgImage: rawPreview,
                        size: NSSize(width: rawPreview.width, height: rawPreview.height)
                    )
                    frame.rawPreviewTransform = snapshot.imageTransform
                }
                frame.developedImage = NSImage(
                    cgImage: result.developed,
                    size: NSSize(width: result.developed.width, height: result.developed.height)
                )
                scanPhase = .complete
                frame.isDeveloping = false
                activeDevelopmentFrameIDs.remove(frame.id)
                statusMessage = "현상 완료"
                return
            } catch {
                guard frame.developRevision == revision else {
                    revision = frame.developRevision
                    continue
                }
                statusMessage = "이미지 로드 실패: \(frame.rawScanURL.lastPathComponent)"
                scanPhase = .error
                frame.isDeveloping = false
                activeDevelopmentFrameIDs.remove(frame.id)
                return
            }
        }
    }

    func loadRawPreview(_ frame: ScanFrame) {
        let snapshot = DevelopFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            filmType: frame.filmType,
            params: frame.params,
            preset: frame.preset,
            imageTransform: frame.imageTransform,
            cachedBase: nil,
            baseKey: FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB
            ),
            needsRawPreview: true
        )
        Task {
            let rawPreview = try? await Task.detached(priority: .utility) {
                try DevelopFrameRenderer.renderRawPreview(snapshot)
            }.value
            guard let rawPreview else { return }
            frame.rawPreviewImage = NSImage(
                cgImage: rawPreview,
                size: NSSize(width: rawPreview.width, height: rawPreview.height)
            )
            frame.rawPreviewTransform = snapshot.imageTransform
        }
    }

    func exportFrame(_ frame: ScanFrame, to url: URL, format: ExportFormat, writeSidecar: Bool = true) {
        var effectiveParams = frame.preset.map { DevelopParameters(preset: $0, overrides: frame.params) } ?? frame.params
        effectiveParams.filmType = frame.filmType
        effectiveParams.imageTransform = frame.imageTransform
        let baseKey = FilmBaseCacheKey(
            filmType: frame.filmType,
            mode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB
        )
        let cachedBase = frame.cachedBaseKey == baseKey ? frame.cachedBase : nil
        let snapshot = ExportFrameSnapshot(
            rawScanURL: frame.rawScanURL,
            outputURL: url,
            format: format,
            filmType: frame.filmType,
            params: effectiveParams,
            baseMode: frame.params.baseEstimationMode,
            manualBaseRGB: frame.params.manualBaseRGB,
            cachedBase: cachedBase,
            scannerModel: devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : nil),
            resolutionDPI: frame.developedImage != nil ? resolutionChoice.dpi : nil,
            backendUsed: (backend?.backendType).map { $0.rawValue },
            presetName: frame.preset?.id,
            cropRect: frame.imageTransform.cropRect,
            writeSidecar: writeSidecar
        )
        frame.isDeveloping = true
        statusMessage = "내보내는 중..."
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ExportFrameWriter.write(snapshot)
                }.value
                if let base = result.base {
                    frame.cachedBaseKey = baseKey
                    frame.cachedBase = base
                    frame.baseRGB = base.rgb
                }
                frame.isDeveloping = false
                statusMessage = "내보내기 완료 → \(url.lastPathComponent)"
            } catch {
                frame.isDeveloping = false
                statusMessage = "내보내기 실패: \(error.localizedDescription)"
            }
        }
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
        let now = Date()
        let nextFraction = p.fraction ?? scanFraction
        let message = p.message.isEmpty ? p.phase.rawValue : p.message
        let phaseChanged = p.phase != lastProgressPhase
        let messageChanged = message != lastProgressMessage
        let fractionMoved = abs(nextFraction - lastProgressFraction) >= 0.015
        let timeElapsed = now.timeIntervalSince(lastProgressUpdateAt) >= 0.20
        guard phaseChanged || messageChanged || fractionMoved || timeElapsed else { return }
        lastProgressUpdateAt = now
        lastProgressFraction = nextFraction
        lastProgressPhase = p.phase
        lastProgressMessage = message
        scanPhase = p.phase
        scanFraction = nextFraction
        statusMessage = message
    }
}

private struct ExportFrameSnapshot: Sendable {
    let rawScanURL: URL
    let outputURL: URL
    let format: ExportFormat
    let filmType: FilmType
    let params: DevelopParameters
    let baseMode: DevelopParameters.BaseMode
    let manualBaseRGB: SIMD3<Double>?
    let cachedBase: FilmBase?
    let scannerModel: String?
    let resolutionDPI: Int?
    let backendUsed: String?
    let presetName: String?
    let cropRect: SIMD4<Double>?
    let writeSidecar: Bool
}

private struct ExportFrameResult: @unchecked Sendable {
    let base: FilmBase?
}

private enum ExportFrameWriter {
    static func write(_ snapshot: ExportFrameSnapshot) throws -> ExportFrameResult {
        let engine = ChromabaseEngine()
        guard let rawInput = engine.loadScannerImage(snapshot.rawScanURL) else {
            throw ChromabaseError.loadFailed(snapshot.rawScanURL.path)
        }
        let base = snapshot.filmType.requiresInversion
            ? snapshot.cachedBase ?? engine.estimateFilmBase(
                in: rawInput,
                mode: snapshot.baseMode,
                manual: snapshot.manualBaseRGB
            )
            : nil
        let meta = ExportMeta(
            scannerModel: snapshot.scannerModel,
            resolutionDPI: snapshot.resolutionDPI,
            filmType: snapshot.filmType.rawValue,
            software: "negaflow 0.1.0"
        )
        let developed = engine.developScanner(image: rawInput, base: base, params: snapshot.params)
        try ExportEngine.write(developed, to: snapshot.outputURL, format: snapshot.format, using: renderContext(), metadata: meta)
        if snapshot.writeSidecar {
            writeSidecars(for: snapshot, base: base)
        }
        return ExportFrameResult(base: base)
    }

    private static func renderContext() -> CIContext {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        ])
    }

    private static func writeSidecars(for snapshot: ExportFrameSnapshot, base: FilmBase?) {
        var sidecar = Sidecar(filmType: snapshot.filmType, parameters: snapshot.params)
        sidecar.scannerModel = snapshot.scannerModel
        sidecar.backendUsed = snapshot.backendUsed
        sidecar.scanResolution = snapshot.resolutionDPI
        sidecar.bitDepth = 16
        sidecar.presetName = snapshot.presetName
        if let crop = snapshot.cropRect {
            sidecar.crop = Sidecar.CropRect(x: crop.x, y: crop.y, w: crop.z, h: crop.w)
        }
        if let base {
            sidecar.baseSample = Sidecar.BaseSample(base)
        }
        try? sidecar.write(to: rawSidecarURL(for: snapshot.rawScanURL))

        let exportSidecar = snapshot.outputURL
            .deletingPathExtension()
            .appendingPathExtension("negaflow.json")
        var exportSidecarBody = sidecar
        exportSidecarBody.exportHistory.append(Sidecar.ExportRecord(
            path: snapshot.outputURL.path,
            format: snapshot.format.rawValue,
            at: Date()
        ))
        try? exportSidecarBody.write(to: exportSidecar)
    }

    private static func rawSidecarURL(for rawURL: URL) -> URL {
        rawURL.deletingPathExtension().appendingPathExtension("negaflow.json")
    }
}

private struct DevelopFrameSnapshot: Sendable {
    let rawScanURL: URL
    let filmType: FilmType
    let params: DevelopParameters
    let preset: LookPreset?
    let imageTransform: ImageTransform
    let cachedBase: FilmBase?
    let baseKey: FilmBaseCacheKey
    let needsRawPreview: Bool
}

private struct DevelopFrameRenderResult: @unchecked Sendable {
    let base: FilmBase?
    let rawPreview: CGImage?
    let developed: CGImage
}

private enum DevelopFrameRenderError: Error {
    case loadFailed
    case rawPreviewFailed
    case developedFailed
}

private enum DevelopFrameRenderer {
    private static let displayMaxDimension: CGFloat = 3600
    private static let sharedRenderContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])

    static func render(_ snapshot: DevelopFrameSnapshot) throws -> DevelopFrameRenderResult {
        let engine = ChromabaseEngine()
        guard let rawInput = engine.loadScannerImage(snapshot.rawScanURL) else {
            throw DevelopFrameRenderError.loadFailed
        }
        let base = snapshot.filmType.requiresInversion
            ? snapshot.cachedBase ?? engine.estimateFilmBase(
                in: rawInput,
                mode: snapshot.params.baseEstimationMode,
                manual: snapshot.params.manualBaseRGB
            )
            : nil
        let context = renderContext()
        let rawPreview = snapshot.needsRawPreview
            ? try renderRawPreview(
                from: displayProxy(rawInput),
                transform: snapshot.imageTransform,
                context: context
            )
            : nil
        let developed = try renderDeveloped(
            input: rawInput,
            base: base,
            snapshot: snapshot,
            engine: engine,
            context: context
        )
        return DevelopFrameRenderResult(base: base, rawPreview: rawPreview, developed: developed)
    }

    static func renderRawPreview(_ snapshot: DevelopFrameSnapshot) throws -> CGImage {
        let engine = ChromabaseEngine()
        guard let rawInput = engine.loadScannerImage(snapshot.rawScanURL) else {
            throw DevelopFrameRenderError.loadFailed
        }
        return try renderRawPreview(
            from: displayProxy(rawInput),
            transform: snapshot.imageTransform,
            context: renderContext()
        )
    }

    private static func renderDeveloped(
        input: CIImage,
        base: FilmBase?,
        snapshot: DevelopFrameSnapshot,
        engine: ChromabaseEngine,
        context: CIContext
    ) throws -> CGImage {
        var effectiveParams: DevelopParameters
        if let preset = snapshot.preset {
            effectiveParams = DevelopParameters(preset: preset, overrides: snapshot.params)
        } else {
            effectiveParams = snapshot.params
        }
        effectiveParams.filmType = snapshot.filmType
        effectiveParams.imageTransform = snapshot.imageTransform
        let out = displayProxy(engine.developScanner(image: input, base: base, params: effectiveParams))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw DevelopFrameRenderError.developedFailed
        }
        return cg
    }

    private static func renderRawPreview(
        from input: CIImage,
        transform: ImageTransform,
        context: CIContext
    ) throws -> CGImage {
        let image = ImageTransformStage.apply(to: input, transform: transform)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw DevelopFrameRenderError.rawPreviewFailed
        }
        return cg
    }

    private static func displayProxy(_ input: CIImage) -> CIImage {
        let extent = input.extent.integral
        let maxSide = max(extent.width, extent.height)
        guard maxSide > displayMaxDimension else {
            return input
        }
        let scale = displayMaxDimension / maxSide
        let scaledSize = CGSize(width: extent.width * scale, height: extent.height * scale)
        return input
            .applyingFilter("CILanczosScaleTransform", parameters: [
                "inputScale": scale,
                "inputAspectRatio": 1.0,
            ])
            .cropped(to: CGRect(origin: .zero, size: scaledSize))
    }

    private static func renderContext() -> CIContext {
        sharedRenderContext
    }
}
