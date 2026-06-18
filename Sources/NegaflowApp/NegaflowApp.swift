import SwiftUI
import ScannerKit
import Chromabase
import CoreImage
import AppKit

// MARK: - Negaflow SwiftUI App
//
// plan §9 UI 구조. 3 영역 단일 윈도우:
//   좌측 Roll/Frames · 중앙 Preview Canvas · 우측 Scan & Develop Controls · 하단 Status
//
// 기본 동작: 8200i(SANE)가 연결되지 않으면 "스캐너 연결 대기" 화면을 보여주고
// 스캔 버튼을 비활성화한다. 상단의 Demo 토글을 켜면 Mock 백엔드로 색감 엔진을
// 시연할 수 있다(samples/ 의 실제 스캔을 가져온다).
@main
struct NegaflowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 1180, minHeight: 760)
                .environmentObject(AppModel())
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let saneBackend = SANEBackend()
    let mockBackend = MockScannerBackend()
    @Published var demoMode: Bool = false
    @Published var devices: [ScannerDescriptor] = []
    @Published var selectedDeviceID: String?

    @Published var scanPhase: ScanPhase = .idle
    @Published var scanFraction: Double = 0
    @Published var statusMessage: String = "Idle"
    @Published var isScanning: Bool = false

    @Published var rawScanURL: URL?
    @Published var developedImage: NSImage?
    @Published var rawPreviewImage: NSImage?
    @Published var showDeveloped: Bool = true
    @Published var baseRGB: SIMD3<Double>?

    @Published var preset: LookPreset?
    @Published var params = DevelopParameters()
    @Published var presets: [LookPreset] = PresetRegistry.loadAll()

    @Published var capabilities: ScannerCapabilities?
    @Published var diagnostics: String = ""

    // 사용자 스캔 옵션
    @Published var filmType: FilmType = .colorNegative
    @Published var resolutionChoice: Resolution = .r3600
    @Published var imageTransform: ImageTransform = .identity

    /// 현재 활성 백엔드. demoMode면 Mock, 아니면 SANE(없으면 nil).
    var backend: ScannerBackend? {
        demoMode ? mockBackend : (hasSANE ? saneBackend : nil)
    }

    /// SANE 장치가 한 개라도 감지됐는지.
    var hasSANE: Bool {
        devices.contains(where: { $0.backendType == .sane })
    }

    var hasScanner: Bool { backend != nil }

    /// 스캔 가능 여부. SANE 장치가 있거나 demoMode 켜져 있어야 한다.
    var canScan: Bool { hasScanner && !isScanning }

    init() {}

    func refreshDevices() async {
        do {
            var all: [ScannerDescriptor] = []
            // SANE 장치 감지
            let sane = (try? await saneBackend.detectScanners()) ?? []
            all.append(contentsOf: sane)
            devices = all
            // SANE이 감지되면 자동으로 선택.
            if hasSANE, selectedDeviceID == nil {
                selectedDeviceID = sane.first?.id
                await loadCapabilities()
            }
            if !hasSANE {
                statusMessage = demoMode ? "Demo 모드" : "스캐너 연결 대기 중"
            } else {
                statusMessage = "Ready"
            }
        }
    }

    func toggleDemo(_ on: Bool) {
        demoMode = on
        if on {
            // demo에서는 가상 장치를 선택한 것처럼 처리
            selectedDeviceID = "mock"
            Task { await loadCapabilities() }
            statusMessage = "Demo 모드 — Mock 스캐너로 색감 엔진 시연"
        } else {
            statusMessage = hasSANE ? "Ready" : "스캐너 연결 대기 중"
        }
    }

    func setFilmType(_ next: FilmType) {
        guard filmType != next else { return }
        filmType = next
        preset = nil
        params = DevelopParameters()
        baseRGB = nil
        refreshCurrentImages()
    }

    func loadCapabilities() async {
        guard let id = effectiveScannerID, let b = backend else { return }
        do {
            capabilities = try await b.getCapabilities(scannerID: id)
        } catch {
            capabilities = nil
        }
    }

    /// SANE 장치의 실제 id(demo면 "mock").
    var effectiveScannerID: String? {
        if demoMode { return "mock" }
        return devices.first(where: { $0.backendType == .sane })?.id
    }

    func runScan(preview: Bool) async {
        guard let id = effectiveScannerID, let backend = backend else {
            statusMessage = "스캐너가 없습니다 — USB를 연결하거나 Demo 모드를 켜세요."
            return
        }
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
        rawScanURL = nil
        rawPreviewImage = nil
        developedImage = nil
        baseRGB = nil
        isScanning = true
        do {
            scanPhase = preview ? .previewScanning : .scanningRGB
            let result = preview
                ? try await backend.startPreviewScan(opts, progress: { [weak self] p in
                    Task { @MainActor in self?.update(p) }
                })
                : try await backend.startFullScan(opts, progress: { [weak self] p in
                    Task { @MainActor in self?.update(p) }
                })
            rawScanURL = result.rawFileURL
            loadRawPreview()
            statusMessage = "스캔 완료: \(result.width)×\(result.height)"
            await developCurrent()
        } catch {
            statusMessage = "스캔 오류: \(error.localizedDescription)"
            scanPhase = .error
        }
        isScanning = false
    }

    func cancelScan() async {
        await backend?.cancelScan()
        isScanning = false
        scanPhase = .idle
        statusMessage = "스캔 취소됨"
    }

    /// 룩/슬라이더 변경 시 자동 재현상(디바운스는 View 측에서 처리).
    func developCurrent() async {
        guard let url = rawScanURL else { return }
        scanPhase = .processingNegative
        let engine = ChromabaseEngine()
        params.filmType = filmType
        let base: FilmBase? = filmType.requiresInversion
            ? engine.estimateFilmBase(at: url, mode: params.baseEstimationMode,
                                      manual: params.manualBaseRGB)
            : nil
        baseRGB = base?.rgb
        guard let input = engine.loadImage(url) else {
            statusMessage = "이미지 로드 실패: \(url.lastPathComponent)"
            scanPhase = .error
            return
        }
        var effectiveParams: DevelopParameters
        if let preset { effectiveParams = DevelopParameters(preset: preset, overrides: params) }
        else { effectiveParams = params }
        effectiveParams.filmType = filmType
        effectiveParams.imageTransform = imageTransform
        let out = engine.develop(image: input, base: base, params: effectiveParams)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        if let cg = ctx.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: cs) {
            developedImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        scanPhase = .complete
        statusMessage = base != nil
            ? "현상 완료 — base \(String(format: "%.2f %.2f %.2f", base!.rgb.x, base!.rgb.y, base!.rgb.z))"
            : "현상 완료"
    }

    func loadRawPreview() {
        guard let url = rawScanURL,
              let input = ChromabaseEngine().loadImage(url) else { return }
        let image = ImageTransformStage.apply(to: input, transform: imageTransform)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = ctx.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: cs) else { return }
        rawPreviewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func exportDeveloped(to url: URL, format: ExportFormat) {
        guard let rawURL = rawScanURL else { return }
        let engine = ChromabaseEngine()
        params.filmType = filmType
        let base: FilmBase? = filmType.requiresInversion
            ? engine.estimateFilmBase(at: rawURL, mode: params.baseEstimationMode,
                                      manual: params.manualBaseRGB)
            : nil
        var effectiveParams = preset.map { DevelopParameters(preset: $0, overrides: params) } ?? params
        effectiveParams.filmType = filmType
        effectiveParams.imageTransform = imageTransform
        do {
            try engine.developFile(input: rawURL, output: url, format: format,
                                   base: base, params: effectiveParams)
            statusMessage = "내보내기 완료 → \(url.lastPathComponent)"
        } catch {
            statusMessage = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    func runDiagnostics() async {
        guard let id = effectiveScannerID, let b = backend else {
            diagnostics = "활성 스캐너가 없습니다."
            return
        }
        do {
            let cap = try await b.getCapabilities(scannerID: id)
            diagnostics = """
            Scanner   : \(devices.first(where: { $0.backendType == .sane })?.displayName ?? (demoMode ? "Mock" : id))
            Backend   : \(b.backendType.rawValue)
            Resol.    : \(cap.supportedResolutions.map(\.dpi))
            Modes     : \(cap.supportedModes.map(\.rawValue))
            BitDepth  : \(cap.supportedBitDepths.map(\.rawValue))
            IR        : \(cap.supportsInfrared)
            Transp.   : \(cap.supportsTransparency)
            """
        } catch {
            diagnostics = "진단 실패: \(error.localizedDescription)"
        }
    }

    func rotateImageClockwise() {
        imageTransform.rotation = imageTransform.rotation.rotatedClockwise()
        refreshCurrentImages()
    }

    func rotateImageCounterClockwise() {
        imageTransform.rotation = imageTransform.rotation.rotatedCounterClockwise()
        refreshCurrentImages()
    }

    func flipImageHorizontal() {
        imageTransform.flipHorizontal.toggle()
        refreshCurrentImages()
    }

    func flipImageVertical() {
        imageTransform.flipVertical.toggle()
        refreshCurrentImages()
    }

    func resetImageTransform() {
        imageTransform = .identity
        refreshCurrentImages()
    }

    private func refreshCurrentImages() {
        loadRawPreview()
        guard rawScanURL != nil else { return }
        Task { await developCurrent() }
    }

    private func update(_ p: ScanProgress) {
        scanPhase = p.phase
        scanFraction = p.fraction ?? scanFraction
        statusMessage = p.message.isEmpty ? p.phase.rawValue : p.message
    }
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                frameList.frame(minWidth: 210, idealWidth: 240)
                VSplitView {
                    canvasArea
                    statusBar.frame(maxHeight: 56)
                }
                controls.frame(minWidth: 300, idealWidth: 320)
            }
        }
        .task { await model.refreshDevices() }
    }

    var topBar: some View {
        HStack(spacing: 12) {
            Text("Negaflow").font(.headline)
            deviceBadge
            Picker("Scanner", selection: $model.selectedDeviceID) {
                if model.hasSANE {
                    ForEach(model.devices.filter { $0.backendType == .sane }) {
                        Text("\($0.displayName)").tag($0.id as String?)
                    }
                } else {
                    Text("스캐너 없음").tag(String?.none)
                }
            }
            .frame(width: 260)
            .disabled(!model.hasSANE)

            Button("다시 찾기") { Task { await model.refreshDevices() } }

            Spacer()

            Toggle("Demo", isOn: Binding(
                get: { model.demoMode },
                set: { model.toggleDemo($0) }
            ))
            .toggleStyle(.switch)
            .help("하드웨어 없이 Mock 백엔드로 색감 엔진 시연")

            Button("진단") { Task { await model.runDiagnostics() }; showDiagnostics = true }
                .popover(isPresented: $showDiagnostics, arrowEdge: .bottom) {
                    Text(model.diagnostics.isEmpty ? "진단 정보 없음" : model.diagnostics)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: 420)
                }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    var deviceBadge: some View {
        if model.demoMode {
            badge("Demo", color: .secondary)
        } else if model.hasSANE {
            badge("Verified", color: .green)
        } else {
            badge("대기", color: .orange)
        }
    }
    func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    var frameList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Roll / Frames")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            if let url = model.rawScanURL {
                FrameRow(title: url.lastPathComponent, subtitle: "raw scan",
                         active: true)
            } else {
                Text("아직 스캔 없음")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            Spacer()
        }
    }

    @ViewBuilder
    var canvasArea: some View {
        ZStack {
            Color.black
            if !model.hasScanner {
                waitingView
            } else if let img = displayedImage {
                ImageCanvas(image: img)
            } else {
                Text("Preview Canvas")
                    .foregroundStyle(.white.opacity(0.4))
                    .font(.title3)
            }
            // 좌측 상단 Before/After 토글
            if model.developedImage != nil {
                VStack {
                    HStack {
                        beforeAfterToggle
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    var waitingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "scanner")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.4))
            Text("Plustek OpticFilm 스캐너 연결 대기")
                .font(.title3).foregroundStyle(.white)
            Text("USB로 스캐너를 연결한 뒤 '다시 찾기'를 누르거나, 상단의 Demo 토글로 색감 엔진을 시연하세요.")
                .font(.callout).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.horizontal)
            Button("다시 찾기") { Task { await model.refreshDevices() } }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    var beforeAfterToggle: some View {
        let showRaw = model.rawPreviewImage != nil && !model.showDeveloped
        HStack(spacing: 0) {
            toggleBtn("Raw", active: showRaw) { model.showDeveloped = false }
            toggleBtn("Developed", active: !showRaw) { model.showDeveloped = true }
        }
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    func toggleBtn(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(active ? Color.black : Color.white.opacity(0.8))
                .background(active ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    var displayedImage: NSImage? {
        if model.showDeveloped { return model.developedImage ?? model.rawPreviewImage }
        return model.rawPreviewImage ?? model.developedImage
    }

    var statusBar: some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(model.scanPhase.rawValue).font(.caption).foregroundStyle(.secondary)
            if model.isScanning {
                ProgressView(value: model.scanFraction).frame(maxWidth: 180)
            }
            Text(model.statusMessage).font(.caption).lineLimit(1)
            Spacer()
            if let b = model.baseRGB {
                Text("base \(String(format: "%.2f %.2f %.2f", b.x, b.y, b.z))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
    }
    var statusColor: Color {
        switch model.scanPhase {
        case .error: return .red
        case .complete: return .green
        case .idle: return .gray
        default: return .blue
        }
    }

    var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                scanSection
                DevelopControls()
                ExportControls()
            }
            .padding(.vertical)
            .padding(.horizontal, 8)
        }
        .background(.regularMaterial)
    }

    var scanSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan").font(.headline)
            LabeledContent("Film Type") {
                Picker("", selection: Binding(
                    get: { model.filmType },
                    set: { model.setFilmType($0) }
                )) {
                    ForEach(FilmType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            LabeledContent("Resolution") {
                Picker("", selection: $model.resolutionChoice) {
                    Text("Preview").tag(Resolution.preview)
                    ForEach(availableResolutions, id: \.self) { r in
                        Text("\(r.dpi)").tag(r)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            LabeledContent("Orientation") {
                HStack(spacing: 6) {
                    iconButton("rotate.left", "왼쪽으로 90도 회전") { model.rotateImageCounterClockwise() }
                    iconButton("rotate.right", "오른쪽으로 90도 회전") { model.rotateImageClockwise() }
                    iconButton("arrow.left.and.right", "좌우 뒤집기") { model.flipImageHorizontal() }
                    iconButton("arrow.up.and.down", "상하 뒤집기") { model.flipImageVertical() }
                    iconButton("arrow.counterclockwise", "방향 초기화") { model.resetImageTransform() }
                    Text(model.imageTransform.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 48, alignment: .leading)
                }
            }
            HStack {
                Button("Preview") { Task { await model.runScan(preview: true) } }
                    .disabled(!model.canScan)
                if model.isScanning {
                    Button("Cancel") { Task { await model.cancelScan() } }
                        .tint(.red)
                } else {
                    Button("Scan") { Task { await model.runScan(preview: false) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canScan)
                }
            }
        }
    }

    var availableResolutions: [Resolution] {
        let cap = model.capabilities
        let fromCap = (cap?.supportedResolutions ?? [.r900, .r1800, .r3600, .r7200])
            .filter { $0.dpi > 0 }
        return fromCap.isEmpty ? [.r3600, .r7200] : fromCap
    }

    func iconButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }
}

struct FrameRow: View {
    let title: String; let subtitle: String; let active: Bool
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.35))
                .frame(width: 52, height: 38)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(active ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}

// MARK: - Image canvas (줌/팬)
struct ImageCanvas: View {
    let image: NSImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fit = fitScale(image.size, in: geo.size) * scale
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: image.size.width * fit,
                       height: image.size.height * fit)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            scale = max(0.5, min(6.0, lastScale * val))
                        }
                        .onEnded { _ in lastScale = scale }
                )
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            offset = CGSize(width: lastOffset.width + g.translation.width,
                                            height: lastOffset.height + g.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
                }
        }
        .padding(12)
    }

    private func fitScale(_ imageSize: NSSize, in canvas: CGSize) -> CGFloat {
        let sx = canvas.width / imageSize.width
        let sy = canvas.height / imageSize.height
        return min(sx, sy)
    }
}

// MARK: - Develop controls

struct DevelopControls: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Develop").font(.headline)

            Picker("Look", selection: $model.preset) {
                Text("없음").tag(LookPreset?.none)
                ForEach(model.presets) { Text($0.name).tag(LookPreset?.some($0)) }
            }
            .onChange(of: model.preset) { _ in scheduleRedevelop() }

            Group {
                sliderRow("Exposure", value: $model.params.exposure, range: -2...2, step: 0.02)
                sliderRow("Density",  value: $model.params.density,  range: -1...1, step: 0.02)
                sliderRow("Highlight", value: $model.params.highlight, range: -1...1, step: 0.02)
                sliderRow("Shadow",   value: $model.params.shadow,   range: -1...1, step: 0.02)
            }
            Divider()
            Group {
                sliderRow("Warmth",      value: $model.params.warmth,     range: -1...1, step: 0.02)
                sliderRow("Tint",        value: $model.params.tint,       range: -1...1, step: 0.02)
                sliderRow("Color Depth", value: $model.params.colorDepth, range: -1...1, step: 0.02)
            }
            Divider()
            Group {
                sliderRow("Grain",     value: $model.params.grain,     range: 0...1, step: 0.02)
                sliderRow("Sharpness", value: $model.params.sharpness, range: 0...1, step: 0.02)
                sliderRow("Halation",  value: $model.params.halation,  range: 0...1, step: 0.02)
            }

            Button("Apply Develop") { Task { await model.developCurrent() } }
                .buttonStyle(.bordered)
                .disabled(model.rawScanURL == nil)
        }
        .onChange(of: model.filmType) { _ in scheduleRedevelop() }
    }

    @State private var redevelopTask: Task<Void, Never>?

    func scheduleRedevelop() {
        redevelopTask?.cancel()
        redevelopTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)   // 0.25s 디바운스
            guard !Task.isCancelled, model.rawScanURL != nil else { return }
            await model.developCurrent()
        }
    }

    func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>,
                   step: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%+.2f", value.wrappedValue))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step) { editing in
                if !editing { scheduleRedevelop() }
            }
        }
    }
}

struct ExportControls: View {
    @EnvironmentObject var model: AppModel
    @State private var format: ExportFormat = .jpeg

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export").font(.headline)
            Picker("Format", selection: $format) {
                Text("JPEG").tag(ExportFormat.jpeg)
                Text("TIFF 16-bit").tag(ExportFormat.tiff16)
            }
            Button("내보내기…") { exportUsingPanel() }
                .disabled(model.rawScanURL == nil)
        }
    }

    func exportUsingPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .jpeg ? [.jpeg] : [.tiff]
        panel.nameFieldStringValue = "negaflow_export.\(format == .jpeg ? "jpg" : "tif")"
        if panel.runModal() == .OK, let url = panel.url {
            model.exportDeveloped(to: url, format: format)
        }
    }
}
