import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage

// MARK: - ContentView (명시적 3칼럼 — 겹침 없는 순정 레이아웃)
//
// Apple Photos 스타일: [사이드바 | 캔버스 | 인스펙터] 명시적 HSplitView.
// NavigationSplitView 의 .inspector 겹침 버그를 피하기 위해 분리.
// 툴바는 캔버스 위에만. 인스펙터는 오른쪽 독립 패널.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showDiagnostics = false
    @State private var cropFrameID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // 상단 툴바 — 전체 폭, 한 줄, 깔끔하게.
            toolbar
            Divider()
            // 3칼럼 본문 — 명시적 HSplitView.
            HSplitView {
                sidebar
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                centerPane
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                inspectorPane
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            }
        }
        .task { await model.refreshDevices() }
    }

    // MARK: toolbar — 깔끔한 한 줄. 우측 정렬 그룹.
    var toolbar: some View {
        HStack(spacing: 10) {
            Text("negaflow").font(.headline).padding(.leading, 8)

            devicePicker

            Button(action: { Task { await model.refreshDevices() } }) {
                Label("다시 찾기", systemImage: "arrow.clockwise")
            }
            .disabled(model.isDetecting)
            .help("스캐너 다시 찾기")

            if model.isDetecting {
                ProgressView().controlSize(.small)
                Text("감지 중…").font(.caption).foregroundStyle(.secondary)
            } else if !model.hasSANE {
                statusBadge("대기", .orange)
            } else {
                statusBadge("Ready", .green)
            }

            Spacer()

            Toggle("Demo", isOn: Binding(get: { model.demoMode }, set: { model.toggleDemo($0) }))
                .toggleStyle(.switch)
                .help("Demo 모드")

            Button(action: { Task { await model.runDiagnostics() }; showDiagnostics = true }) {
                Label("진단", systemImage: "stethoscope")
            }
            .popover(isPresented: $showDiagnostics) {
                Text(model.diagnostics.isEmpty ? "진단 정보 없음" : model.diagnostics)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(minWidth: 320, maxWidth: 440)
                    .textSelection(.enabled)
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    var devicePicker: some View {
        Picker("", selection: $model.selectedDeviceID) {
            if model.hasSANE {
                ForEach(model.devices.filter { $0.backendType == .sane }) {
                    Text("\($0.displayName)").tag($0.id as String?)
                }
            } else {
                Text("스캐너 없음").tag(String?.none)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 240)
        .disabled(!model.hasSANE)
    }

    func statusBadge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: sidebar — 프레임 리스트
    @ViewBuilder
    var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selectedFrameID },
                set: { model.selectedFrameID = $0 }
            )) {
                ForEach(model.frames) { frame in
                    FrameRowView(frame: frame)
                        .tag(frame.id)
                        .contextMenu { Button("삭제", role: .destructive) { model.deleteFrame(frame) } }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if model.frames.isEmpty {
                    ContentUnavailableView("스캔 없음", systemImage: "film",
                        description: Text("Scan을 눌러 시작"))
                }
            }
        }
    }

    // MARK: center pane — 캔버스 + 상태바
    @ViewBuilder
    var centerPane: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if model.isDetecting {
                    DetectingView()
                } else if !model.hasScanner {
                    NoScannerView(onRefresh: { Task { await model.refreshDevices() } })
                } else if let frame = model.selectedFrame {
                    CanvasView(frame: frame, cropMode: cropModeBinding(for: frame))
                } else {
                    ContentUnavailableView("프레임을 선택하세요", systemImage: "photo.on.rectangle")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: status bar — 하단, 한 줄
    var statusBar: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(model.scanPhase.rawValue).font(.caption).foregroundStyle(.secondary)
            if model.isScanning {
                if model.batchTotal > 1 {
                    ProgressView(value: Double(model.batchIndex) + model.scanFraction,
                                 total: Double(model.batchTotal))
                        .frame(maxWidth: 200)
                    Text("Frame \(model.batchIndex + 1)/\(model.batchTotal)").font(.caption2)
                } else {
                    ProgressView(value: model.scanFraction).frame(maxWidth: 160)
                }
            }
            Text(model.statusMessage).font(.caption).lineLimit(1).truncationMode(.tail)
            Spacer()
            if let b = model.selectedFrame?.baseRGB {
                Text("base \(String(format: "%.2f %.2f %.2f", b.x, b.y, b.z))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(.bar)
    }

    var statusColor: Color {
        switch model.scanPhase {
        case .error: return .red
        case .complete: return .green
        case .idle: return .gray
        default: return .blue
        }
    }

    @ViewBuilder
    var inspectorPane: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.regularMaterial)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let frame = model.selectedFrame {
                        DevelopWorkflowInspector(frame: frame, cropMode: cropModeBinding(for: frame))
                        Divider()
                        ScanSection(collapsedByDefault: true)
                        ExportSection()
                    } else {
                        ScanSection(collapsedByDefault: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    func cropModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { cropFrameID == frame.id },
            set: { isOn in cropFrameID = isOn ? frame.id : nil }
        )
    }
}

// MARK: - Detecting / NoScanner
struct DetectingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.large)
            Text("스캐너를 찾는 중…").foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct NoScannerView: View {
    let onRefresh: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text("스캐너 연결 대기").font(.headline).foregroundStyle(.white)
            Text("USB로 Plustek OpticFilm을 연결하고 다시 찾기를 누르거나, Demo 토글로 색감 엔진을 시연하세요.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center).frame(maxWidth: 400)
            Button("다시 찾기", action: onRefresh).buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - FrameRowView
struct FrameRowView: View {
    @ObservedObject var frame: ScanFrame
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25))
                if let img = frame.developedImage ?? frame.rawPreviewImage {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 34).clipped().cornerRadius(4)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary).font(.caption)
                }
            }
            .frame(width: 46, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(frame.displayName).font(.callout).lineLimit(1)
                Text(frame.filmType.displayName).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - CanvasView (줌/팬 + before/after + crop 오버레이 + 히스토그램)
struct CanvasView: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    @Binding var cropMode: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    // crop 핸들 (정규화 0~1)
    @State private var cropRect: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black
                if let img = displayedImage {
                    let fit = fitScale(img.size, in: geo.size) * scale
                    let imgW = img.size.width * fit
                    let imgH = img.size.height * fit
                    // 이미지는 캔버스 중앙에 배치.
                    let imgX = (geo.size.width - imgW) / 2 + offset.width
                    let imgY = (geo.size.height - imgH) / 2 + offset.height
                    Image(nsImage: img)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: imgW, height: imgH)
                        .position(x: imgX + imgW/2, y: imgY + imgH/2)
                        .gesture(MagnificationGesture().onChanged { v in scale = max(0.5, min(6, lastScale * v)) }
                            .onEnded { _ in lastScale = scale })
                        .gesture(DragGesture().onChanged { g in
                            if !cropMode {
                                offset = CGSize(width: lastOffset.width + g.translation.width,
                                                height: lastOffset.height + g.translation.height)
                            }
                        }.onEnded { _ in lastOffset = offset })
                        .onTapGesture(count: 2) {
                            withAnimation { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                        }
                    // crop 오버레이 (cropMode 일 때만) — 이미지 영역에 맞춰 정렬.
                    if cropMode {
                        CropOverlay(cropRect: $cropRect,
                                    imageFrame: CGRect(x: imgX, y: imgY, width: imgW, height: imgH),
                                    onApply: {
                            frame.imageTransform.cropRect = SIMD4(cropRect.minX, cropRect.minY,
                                                                   cropRect.width, cropRect.height)
                            cropMode = false
                            Task { await model.developFrame(frame) }
                        }, onReset: {
                            cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                            frame.imageTransform.cropRect = nil
                            Task { await model.developFrame(frame) }
                        })
                    }
                }
                // 좌상단: before/after 토글
                if frame.developedImage != nil {
                    beforeAfterToggle.padding(10)
                }
            }
        }
        .onChange(of: cropMode) { _, isOn in
            guard isOn else { return }
            if let existing = frame.imageTransform.cropRect {
                cropRect = CGRect(x: existing.x, y: existing.y, width: existing.z, height: existing.w)
            }
        }
    }

    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.rawPreviewImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    var beforeAfterToggle: some View {
        HStack(spacing: 0) {
            ForEach(["Raw", "Developed"], id: \.self) { label in
                let active = (label == "Developed") == frame.showDeveloped
                Button { frame.showDeveloped = (label == "Developed") } label: {
                    Text(label).font(.caption.weight(active ? .semibold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(active ? Color.black : Color.white.opacity(0.8))
                        .background(active ? Color.white : Color.clear)
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .background(.regularMaterial).clipShape(Capsule())
    }

    private func fitScale(_ s: NSSize, in c: CGSize) -> CGFloat {
        min(c.width / s.width, c.height / s.height)
    }
}

// MARK: - CropOverlay (드래그 가능한 사각형 — 4모서리 핸들)
//
// 정규화 cropRect(0~1, imageFrame 기준)를 화면에 표시. 4개 모서리 핸들로 조절.
// 본체 드래그는 지원 안 함(단순화) — 핸들로 크기만. 적용/리셋 버튼은 콜백.
struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let imageFrame: CGRect          // 화면 좌표에서 이미지가 차지하는 영역
    let onApply: () -> Void
    let onReset: () -> Void

    var body: some View {
        let r = screenRect
        ZStack {
            // 외부 어두운 마스크 — 사각형 구멍(even-odd fill).
            Color.black.opacity(0.45)
                .mask {
                    GeometryReader { g in
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: g.size))
                            p.addRect(r)
                            p.addRect(r)   // even-odd 구멍
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }
                }
            // crop 사각형 테두리 + 3분할 가이드.
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white, lineWidth: 1.5)
                GeometryReader { g in
                    let w = g.size.width / 3, h = g.size.height / 3
                    Path { p in
                        for i in 1...2 {
                            p.move(to: CGPoint(x: w * CGFloat(i), y: 0))
                            p.addLine(to: CGPoint(x: w * CGFloat(i), y: g.size.height))
                            p.move(to: CGPoint(x: 0, y: h * CGFloat(i)))
                            p.addLine(to: CGPoint(x: g.size.width, y: h * CGFloat(i)))
                        }
                    }.stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                }
            }
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            // 4 모서리 핸들.
            ForEach(handles(r), id: \.0) { name, pt in
                handleView.position(pt).gesture(handleDrag(name: name))
            }
            // 적용/리셋 버튼 — 사각형 아래.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button("적용", action: onApply).buttonStyle(.borderedProminent).font(.caption)
                    Button("리셋", action: onReset).font(.caption)
                }
                .padding(8)
            }
        }
    }

    var handleView: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: 14, height: 14)
    }

    // 정규화 → 화면 좌표.
    var screenRect: CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGRect(
            x: imageFrame.minX + cropRect.minX * imageFrame.width,
            y: imageFrame.minY + cropRect.minY * imageFrame.height,
            width: cropRect.width * imageFrame.width,
            height: cropRect.height * imageFrame.height
        )
    }

    func handles(_ r: CGRect) -> [(String, CGPoint)] {
        [ ("tl", CGPoint(x: r.minX, y: r.minY)),
          ("tr", CGPoint(x: r.maxX, y: r.minY)),
          ("bl", CGPoint(x: r.minX, y: r.maxY)),
          ("br", CGPoint(x: r.maxX, y: r.maxY)) ]
    }

    func handleDrag(name: String) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { g in
            guard imageFrame.width > 0, imageFrame.height > 0 else { return }
            let nx = (g.location.x - imageFrame.minX) / imageFrame.width
            let ny = (g.location.y - imageFrame.minY) / imageFrame.height
            var c = cropRect
            switch name {
            case "tl":
                let mx = min(nx, c.maxX - 0.05), my = min(ny, c.maxY - 0.05)
                let dx = c.minX - mx, dy = c.minY - my
                c.origin.x = max(0, mx); c.origin.y = max(0, my)
                c.size.width += dx; c.size.height += dy
            case "tr":
                let my = min(ny, c.maxY - 0.05)
                c.origin.y = max(0, my)
                c.size.height = max(0.05, c.maxY - c.minY)
                c.size.width = max(0.05, min(nx, 1) - c.minX)
            case "bl":
                let mx = min(nx, c.maxX - 0.05)
                let dx = c.minX - mx
                c.origin.x = max(0, mx)
                c.size.width += dx
                c.size.height = max(0.05, min(ny, 1) - c.minY)
            case "br":
                c.size.width = max(0.05, min(nx, 1) - c.minX)
                c.size.height = max(0.05, min(ny, 1) - c.minY)
            default: break
            }
            cropRect = c
        }
    }
}

@MainActor
enum HistogramToneRegion: CaseIterable {
    case shadow
    case density
    case exposure
    case highlight

    var title: String {
        switch self {
        case .shadow: return "Shadow"
        case .density: return "Density"
        case .exposure: return "Exposure"
        case .highlight: return "Highlight"
        }
    }

    var symbolName: String {
        switch self {
        case .shadow: return "moon.fill"
        case .density: return "circle.lefthalf.filled"
        case .exposure: return "plusminus.circle"
        case .highlight: return "sun.max.fill"
        }
    }

    var lowerBound: CGFloat {
        switch self {
        case .shadow: return 0.00
        case .density: return 0.26
        case .exposure: return 0.50
        case .highlight: return 0.74
        }
    }

    var upperBound: CGFloat {
        switch self {
        case .shadow: return 0.26
        case .density: return 0.50
        case .exposure: return 0.74
        case .highlight: return 1.00
        }
    }

    var sensitivity: Double {
        switch self {
        case .exposure: return 4.0
        default: return 2.0
        }
    }

    var limits: ClosedRange<Double> {
        switch self {
        case .exposure: return -2...2
        default: return -1...1
        }
    }

    func contains(_ unitX: CGFloat) -> Bool {
        unitX >= lowerBound && unitX < upperBound
    }

    func value(in frame: ScanFrame) -> Double {
        switch self {
        case .shadow: return frame.params.shadow
        case .density: return frame.params.density
        case .exposure: return frame.params.exposure
        case .highlight: return frame.params.highlight
        }
    }

    func apply(to frame: ScanFrame, value: Double) {
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        switch self {
        case .shadow: frame.params.shadow = clamped
        case .density: frame.params.density = clamped
        case .exposure: frame.params.exposure = clamped
        case .highlight: frame.params.highlight = clamped
        }
    }

    static func region(at x: CGFloat, width: CGFloat) -> HistogramToneRegion {
        let unitX = min(max(x / max(width, 1), 0), 0.999)
        return allCases.first { $0.contains(unitX) } ?? .exposure
    }
}

struct InteractiveHistogramView: View {
    let image: NSImage
    @ObservedObject var frame: ScanFrame
    let onChange: () -> Void
    @State private var bins: (r: [Int], g: [Int], b: [Int])?
    @State private var hoverRegion: HistogramToneRegion?
    @State private var dragRegion: HistogramToneRegion?
    @State private var dragStartValue: Double?

    init(image: NSImage, frame: ScanFrame, onChange: @escaping () -> Void) {
        self.image = image
        self._frame = ObservedObject(wrappedValue: frame)
        self.onChange = onChange
        self._bins = State(initialValue: HistogramSampler.compute(image))
    }

    var body: some View {
        GeometryReader { geo in
            let activeRegion = dragRegion ?? hoverRegion
            ZStack(alignment: .bottomLeading) {
                if let activeRegion {
                    activeBand(activeRegion, size: geo.size)
                }
                Canvas { ctx, size in
                    let plot = CGRect(x: 8, y: 24, width: max(1, size.width - 16), height: max(1, size.height - 50))
                    var background = Path()
                    background.addRoundedRect(in: plot, cornerSize: CGSize(width: 8, height: 8))
                    ctx.fill(background, with: .color(Color.black.opacity(0.22)))
                    guard let bins = bins else { return }
                    let n = bins.r.count
                    let bw = plot.width / CGFloat(n)
                    for region in HistogramToneRegion.allCases.dropFirst() {
                        let x = plot.minX + plot.width * region.lowerBound
                        var divider = Path()
                        divider.move(to: CGPoint(x: x, y: plot.minY))
                        divider.addLine(to: CGPoint(x: x, y: plot.maxY))
                        ctx.stroke(divider, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                    }
                    func drawChannel(_ data: [Int], _ color: Color) {
                        let maxV = max(data.max() ?? 1, 1)
                        var path = Path()
                        for (i, v) in data.enumerated() {
                            let unit = sqrt(CGFloat(v) / CGFloat(maxV))
                            let h = unit * plot.height
                            let x = plot.minX + CGFloat(i) * bw
                            let y = plot.maxY - h
                            let rect = CGRect(
                                x: x,
                                y: y,
                                width: max(1, bw),
                                height: h
                            )
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                            ctx.fill(Path(rect), with: .color(color.opacity(0.12)))
                        }
                        ctx.stroke(path, with: .color(color.opacity(0.92)), lineWidth: 1.4)
                    }
                    drawChannel(bins.r, .red)
                    drawChannel(bins.g, .green)
                    drawChannel(bins.b, .blue)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Histogram")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let activeRegion {
                            Label(valueText(for: activeRegion), systemImage: activeRegion.symbolName)
                                .labelStyle(.titleAndIcon)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(HistogramToneRegion.allCases, id: \.self) { region in
                            Text(region.title)
                                .font(.system(size: 9, weight: activeRegion == region ? .semibold : .regular))
                                .foregroundStyle(activeRegion == region ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(8)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geo.size.width))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverRegion = HistogramToneRegion.region(at: location.x, width: geo.size.width)
                case .ended:
                    hoverRegion = nil
                }
            }
        }
        .frame(height: 118)
        .liquidSurface(cornerRadius: 14, interactive: true)
        .onAppear { bins = HistogramSampler.compute(image) }
        .onChange(of: ObjectIdentifier(image)) { _, _ in bins = HistogramSampler.compute(image) }
    }

    func activeBand(_ region: HistogramToneRegion, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: size.width * (region.upperBound - region.lowerBound), height: size.height)
            .offset(x: size.width * region.lowerBound)
    }

    func valueText(for region: HistogramToneRegion) -> String {
        "\(region.title) \(String(format: "%+.2f", region.value(in: frame)))"
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let region = dragRegion ?? HistogramToneRegion.region(at: value.startLocation.x, width: width)
                if dragRegion == nil {
                    dragRegion = region
                    dragStartValue = region.value(in: frame)
                }
                guard let dragStartValue else { return }
                let delta = Double(value.translation.width / max(width, 1)) * region.sensitivity
                region.apply(to: frame, value: dragStartValue + delta)
                onChange()
            }
            .onEnded { _ in
                dragRegion = nil
                dragStartValue = nil
            }
    }
}

enum HistogramSampler {
    static func compute(_ image: NSImage) -> (r: [Int], g: [Int], b: [Int])? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let directImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        let bitmapImage = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.cgImage
        guard let cg = directImage ?? bitmapImage else { return nil }
        let targetW = 256, scale = Double(targetW) / Double(cg.width)
        let targetH = max(1, Int(Double(cg.height) * scale))
        var px = [UInt8](repeating: 0, count: targetW * targetH * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &px, width: targetW, height: targetH, bitsPerComponent: 8,
            bytesPerRow: targetW * 4, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        let nbins = 64
        var r = [Int](repeating: 0, count: nbins), g = r, b = r
        for i in stride(from: 0, to: px.count, by: 4) {
            r[Int(px[i]) * nbins / 256] += 1
            g[Int(px[i+1]) * nbins / 256] += 1
            b[Int(px[i+2]) * nbins / 256] += 1
        }
        return (r, g, b)
    }
}

// MARK: - ScanSection
struct ScanSection: View {
    @EnvironmentObject var model: AppModel
    let collapsedByDefault: Bool
    @State private var batchCount: Int = 1
    @State private var isExpanded: Bool

    init(collapsedByDefault: Bool = false) {
        self.collapsedByDefault = collapsedByDefault
        self._isExpanded = State(initialValue: !collapsedByDefault)
    }

    var body: some View {
        if collapsedByDefault {
            DisclosureGroup(isExpanded: $isExpanded) {
                controls
                    .padding(.top, 8)
            } label: {
                Label("Scan", systemImage: "scanner")
                    .font(.subheadline.weight(.semibold))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Scan", systemImage: "scanner")
                    .font(.headline)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            InspectorControlRow("Film") {
                Picker("Film", selection: $model.filmType) {
                    ForEach(FilmType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
            }
            InspectorControlRow("Resolution") {
                Picker("Resolution", selection: $model.resolutionChoice) {
                    Text("Preview").tag(Resolution.preview)
                    ForEach(resolutions, id: \.self) { Text("\($0.dpi) dpi").tag($0) }
                }
                .labelsHidden()
            }
            Stepper("프레임: \(batchCount)", value: $batchCount, in: 1...12)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button {
                    Task { await model.runScan(preview: true) }
                } label: {
                    Text("Preview")
                        .frame(maxWidth: .infinity)
                }
                    .disabled(!model.canScan)
                if model.isScanning {
                    Button(role: .destructive) {
                        Task { await model.cancelScan() }
                    } label: {
                        Text("취소")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button {
                        Task { await model.scanFrames(count: batchCount, preview: false) }
                    } label: {
                        Text(batchCount > 1 ? "스캔 ×\(batchCount)" : "스캔")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canScan)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var resolutions: [Resolution] {
        let fromCap = (model.capabilities?.supportedResolutions ?? [.r900, .r1800, .r3600, .r7200])
            .filter { $0.dpi > 0 }
        return fromCap.isEmpty ? [.r3600, .r7200] : fromCap
    }
}

struct InspectorControlRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

enum InspectorPanel: CaseIterable {
    case tone
    case color
    case detail
}

struct DevelopWorkflowInspector: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @State private var expandedPanel: InspectorPanel = .tone
    @State private var redevelopTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = displayedImage {
                InteractiveHistogramView(image: image, frame: frame) { scheduleRedevelop(frame) }
            }

            ToolStripSection(frame: frame, cropMode: $cropMode)

            WorkflowSection(
                title: "Basic Tone",
                systemImage: "slider.horizontal.3",
                isExpanded: expandedPanel == .tone,
                toggle: { toggle(.tone) }
            ) {
                Picker("Look", selection: Binding(
                    get: { frame.preset },
                    set: { frame.preset = $0; scheduleRedevelop(frame) }
                )) {
                    Text("없음").tag(LookPreset?.none)
                    ForEach(model.presets) { Text($0.name).tag(LookPreset?.some($0)) }
                }
                .pickerStyle(.menu)
                InspectorSlider("Exposure", value: toneBinding(\.exposure), range: -2...2)
                InspectorSlider("Density", value: toneBinding(\.density), range: -1...1)
                InspectorSlider("Highlight", value: toneBinding(\.highlight), range: -1...1)
                InspectorSlider("Shadow", value: toneBinding(\.shadow), range: -1...1)
            }

            WorkflowSection(
                title: "Color",
                systemImage: "eyedropper.halffull",
                isExpanded: expandedPanel == .color,
                toggle: { toggle(.color) }
            ) {
                InspectorSlider("Warmth", value: toneBinding(\.warmth), range: -1...1)
                InspectorSlider("Tint", value: toneBinding(\.tint), range: -1...1)
                InspectorSlider("Color Depth", value: toneBinding(\.colorDepth), range: -1...1)
            }

            WorkflowSection(
                title: "Detail",
                systemImage: "camera.macro",
                isExpanded: expandedPanel == .detail,
                toggle: { toggle(.detail) }
            ) {
                InspectorSlider("Grain", value: toneBinding(\.grain), range: 0...1)
                InspectorSlider("Sharpness", value: toneBinding(\.sharpness), range: 0...1)
                InspectorSlider("Halation", value: toneBinding(\.halation), range: 0...1)
            }
        }
    }

    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.rawPreviewImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    func toggle(_ panel: InspectorPanel) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedPanel = panel
        }
    }

    func toneBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: {
                frame.params[keyPath: keyPath] = $0
                scheduleRedevelop(frame)
            }
        )
    }

    func scheduleRedevelop(_ frame: ScanFrame) {
        redevelopTask?.cancel()
        redevelopTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            await model.developFrame(frame)
        }
    }
}

struct ToolStripSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolRow
            Text(frame.imageTransform.displayName)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var toolRow: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                buttons
            }
        } else {
            buttons
        }
    }

    var buttons: some View {
        HStack {
            ToolIconButton(systemName: "crop", help: "크롭", isActive: cropMode) {
                withAnimation(.snappy(duration: 0.18)) { cropMode.toggle() }
            }
            ToolIconButton(systemName: "rotate.left", help: "왼쪽으로 회전") {
                frame.imageTransform.rotation = frame.imageTransform.rotation.rotatedCounterClockwise()
                redevelop()
            }
            ToolIconButton(systemName: "rotate.right", help: "오른쪽으로 회전") {
                frame.imageTransform.rotation = frame.imageTransform.rotation.rotatedClockwise()
                redevelop()
            }
            ToolIconButton(systemName: "arrow.left.and.right", help: "좌우 반전", isActive: frame.imageTransform.flipHorizontal) {
                frame.imageTransform.flipHorizontal.toggle()
                redevelop()
            }
            ToolIconButton(systemName: "arrow.up.and.down", help: "상하 반전", isActive: frame.imageTransform.flipVertical) {
                frame.imageTransform.flipVertical.toggle()
                redevelop()
            }
            Spacer()
            ToolIconButton(systemName: "arrow.counterclockwise", help: "변형 초기화", isDisabled: frame.imageTransform.isIdentity) {
                frame.imageTransform = .identity
                cropMode = false
                redevelop()
            }
        }
    }

    func redevelop() {
        Task { await model.developFrame(frame) }
    }
}

struct ToolIconButton: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
        .liquidSurface(cornerRadius: 8, interactive: !isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct WorkflowSection<Content: View>: View {
    let title: String
    let systemImage: String
    let isExpanded: Bool
    let toggle: () -> Void
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .frame(width: 18)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
        }
    }
}

struct InspectorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) {
        self.title = title
        self._value = value
        self.range = range
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%+.2f", value))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - ExportSection
struct ExportSection: View {
    @EnvironmentObject var model: AppModel
    @State private var format: ExportFormat = .jpeg
    @State private var writeSidecar: Bool = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export").font(.headline)
            InspectorControlRow("Format") {
                Picker("Format", selection: $format) {
                    Text("JPEG").tag(ExportFormat.jpeg)
                    Text("TIFF 16-bit").tag(ExportFormat.tiff16)
                }
                .labelsHidden()
            }
            Toggle("Sidecar JSON 저장", isOn: $writeSidecar)
                .font(.caption)
                .help("현상 파라미터를 <이름>.negaflow.json 으로 저장")
            Text("EXIF(scanner/dpi/film) 자동 포함").font(.caption2).foregroundStyle(.secondary)
            if let frame = model.selectedFrame {
                Button {
                    exportUsingPanel(frame)
                } label: {
                    Text("내보내기…")
                        .frame(maxWidth: .infinity)
                }
                    .disabled(frame.developedImage == nil)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func exportUsingPanel(_ frame: ScanFrame) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .jpeg ? [.jpeg] : [.tiff]
        panel.nameFieldStringValue = "frame\(frame.scanIndex).\(format == .jpeg ? "jpg" : "tif")"
        if panel.runModal() == .OK, let url = panel.url {
            model.exportFrame(frame, to: url, format: format, writeSidecar: writeSidecar)
        }
    }
}

extension View {
    @ViewBuilder
    func liquidSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
