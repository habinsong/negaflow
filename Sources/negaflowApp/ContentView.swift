import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

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
                    .frame(minWidth: 150, idealWidth: 180, maxWidth: 230)
                centerPane
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                inspectorPane
                    .frame(minWidth: 220, idealWidth: 252, maxWidth: 304)
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
            } else if model.demoMode {
                statusBadge("Demo", .blue)
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
        Picker("", selection: Binding(
            get: { model.selectedDeviceID },
            set: {
                model.selectedDeviceID = $0
                Task { await model.loadCapabilities() }
            }
        )) {
            if model.demoMode {
                Text(AppModel.mockDisplayName).tag(AppModel.mockDeviceID as String?)
            } else if model.hasSANE {
                ForEach(model.saneDevices) {
                    Text("\($0.displayName)").tag($0.id as String?)
                }
            } else {
                Text("스캐너 없음").tag(String?.none)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 240)
        .disabled(model.demoMode || !model.hasSANE)
        .help(model.activeScannerDisplayName)
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
                        .id(frame.id)
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

private let canvasCoordinateSpace = "negaflow.canvas"

private func clampedUnitRect(_ rect: CGRect, minimumSize: CGFloat = 0.035) -> CGRect {
    let width = min(max(rect.width, minimumSize), 1)
    let height = min(max(rect.height, minimumSize), 1)
    let x = min(max(rect.minX, 0), 1 - width)
    let y = min(max(rect.minY, 0), 1 - height)
    return CGRect(x: x, y: y, width: width, height: height)
}

private func unitRect(from a: CGPoint, to b: CGPoint) -> CGRect {
    clampedUnitRect(CGRect(
        x: min(a.x, b.x),
        y: min(a.y, b.y),
        width: abs(a.x - b.x),
        height: abs(a.y - b.y)
    ))
}

private func engineCrop(from visibleCrop: CGRect, existingCrop: SIMD4<Double>?) -> SIMD4<Double>? {
    let visible = clampedUnitRect(visibleCrop)
    guard visible.width < 0.995 || visible.height < 0.995 else {
        return existingCrop
    }
    let crop = SIMD4(
        Double(visible.minX),
        Double(1 - visible.maxY),
        Double(visible.width),
        Double(visible.height)
    )
    guard let existingCrop else {
        return crop
    }
    return SIMD4(
        existingCrop.x + crop.x * existingCrop.z,
        existingCrop.y + crop.y * existingCrop.w,
        crop.z * existingCrop.z,
        crop.w * existingCrop.w
    )
}

struct CanvasView: View {
    @ObservedObject var frame: ScanFrame
    @EnvironmentObject var model: AppModel
    @Binding var cropMode: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    private let minScale: CGFloat = 0.2
    private let maxScale: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let image = displayedImage
            let imageSize = image?.size
            ZStack(alignment: .topLeading) {
                Color.black
                if let img = image {
                    let imageFrame = fittedImageFrame(for: img.size, in: geo.size)
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                        .onTapGesture(count: 2) {
                            resetViewport()
                        }
                    if cropMode {
                        CropOverlay(
                            cropRect: $cropRect,
                            imageFrame: imageFrame,
                            onApply: applyCrop,
                            onReset: resetCrop,
                            onCancel: { cropMode = false }
                        )
                    }
                    canvasHUD(imageSize: img.size, canvasSize: geo.size)
                }
                if frame.developedImage != nil {
                    beforeAfterToggle.padding(10)
                }
            }
            .coordinateSpace(name: canvasCoordinateSpace)
            .contentShape(Rectangle())
            .gesture(panGesture(imageSize: imageSize, canvasSize: geo.size))
            .simultaneousGesture(zoomGesture(imageSize: imageSize, canvasSize: geo.size))
        }
        .onChange(of: cropMode) { _, isOn in
            if isOn {
                cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }
        .onChange(of: frame.imageTransform.displayName) { _, _ in
            if !cropMode {
                resetViewport(animated: false)
            }
        }
    }

    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.rawPreviewImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    @ViewBuilder
    func canvasHUD(imageSize: NSSize, canvasSize: CGSize) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                CanvasToolHUD(
                    zoomText: "\(Int((scale * 100).rounded()))%",
                    cropMode: cropMode,
                    onZoomOut: { setScale(scale / 1.25, imageSize: imageSize, canvasSize: canvasSize) },
                    onZoomIn: { setScale(scale * 1.25, imageSize: imageSize, canvasSize: canvasSize) },
                    onFit: { resetViewport() },
                    onActualSize: { setScale(actualSizeScale(imageSize, in: canvasSize), imageSize: imageSize, canvasSize: canvasSize) },
                    onCrop: { withAnimation(.snappy(duration: 0.18)) { cropMode.toggle() } }
                )
                .padding(.trailing, 14)
                .padding(.bottom, 12)
            }
        }
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
        guard s.width > 0, s.height > 0, c.width > 0, c.height > 0 else { return 1 }
        return min(c.width / s.width, c.height / s.height)
    }

    private func fittedImageFrame(for imageSize: NSSize, in canvasSize: CGSize) -> CGRect {
        let fit = fitScale(imageSize, in: canvasSize) * scale
        let width = imageSize.width * fit
        let height = imageSize.height * fit
        return CGRect(
            x: (canvasSize.width - width) / 2 + offset.width,
            y: (canvasSize.height - height) / 2 + offset.height,
            width: width,
            height: height
        )
    }

    private func actualSizeScale(_ imageSize: NSSize, in canvasSize: CGSize) -> CGFloat {
        min(max(1 / fitScale(imageSize, in: canvasSize), minScale), maxScale)
    }

    private func resetViewport(animated: Bool = true) {
        let updates = {
            scale = 1
            lastScale = 1
            offset = .zero
            lastOffset = .zero
        }
        if animated {
            withAnimation(.snappy(duration: 0.18)) { updates() }
        } else {
            updates()
        }
    }

    private func setScale(_ newScale: CGFloat, imageSize: NSSize, canvasSize: CGSize) {
        let clamped = min(max(newScale, minScale), maxScale)
        withAnimation(.snappy(duration: 0.16)) {
            scale = clamped
            lastScale = clamped
            offset = clampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: clamped)
            lastOffset = offset
        }
    }

    private func panGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                guard let imageSize, !cropMode else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, imageSize: imageSize, canvasSize: canvasSize, scale: scale)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func zoomGesture(imageSize: NSSize?, canvasSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard let imageSize else { return }
                let next = min(max(lastScale * value, minScale), maxScale)
                scale = next
                offset = clampedOffset(offset, imageSize: imageSize, canvasSize: canvasSize, scale: next)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    private func clampedOffset(_ proposed: CGSize, imageSize: NSSize, canvasSize: CGSize, scale: CGFloat) -> CGSize {
        let fit = fitScale(imageSize, in: canvasSize) * scale
        let imageWidth = imageSize.width * fit
        let imageHeight = imageSize.height * fit
        let limitX = max(48, (imageWidth - canvasSize.width) / 2 + 96)
        let limitY = max(48, (imageHeight - canvasSize.height) / 2 + 96)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    private func applyCrop() {
        frame.updateTransform {
            $0.cropRect = engineCrop(from: cropRect, existingCrop: $0.cropRect)
        }
        cropMode = false
        resetViewport()
        Task { await model.developFrame(frame) }
    }

    private func resetCrop() {
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        frame.updateTransform { $0.cropRect = nil }
        resetViewport()
        Task { await model.developFrame(frame) }
    }
}

struct CanvasToolHUD: View {
    let zoomText: String
    let cropMode: Bool
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onFit: () -> Void
    let onActualSize: () -> Void
    let onCrop: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            CanvasToolButton(systemName: "minus.magnifyingglass", help: "축소", action: onZoomOut)
            CanvasToolButton(systemName: "plus.magnifyingglass", help: "확대", action: onZoomIn)
            Button(action: onFit) {
                Text(zoomText)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .frame(width: 46, height: 28)
            }
            .buttonStyle(.plain)
            .help("화면에 맞추기")
            CanvasToolButton(systemName: "1.magnifyingglass", help: "원본 크기", action: onActualSize)
            CanvasToolButton(systemName: "crop", help: "크롭", isActive: cropMode, action: onCrop)
        }
        .padding(4)
        .liquidSurface(cornerRadius: 10, interactive: true)
    }
}

struct CanvasToolButton: View {
    let systemName: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private enum CropHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct CropOverlay: View {
    @Binding var cropRect: CGRect
    let imageFrame: CGRect
    let onApply: () -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    @State private var dragStartRect: CGRect?
    @State private var dragStartPoint: CGPoint?

    var body: some View {
        let r = screenRect
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .contentShape(Rectangle())
                .gesture(createGesture)
            Color.black.opacity(0.45)
                .allowsHitTesting(false)
                .mask {
                    GeometryReader { g in
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: g.size))
                            p.addRect(r)
                        }
                        .fill(style: FillStyle(eoFill: true))
                    }
                }
            selectionFrame(r)
                .allowsHitTesting(hasActiveCrop)
            ForEach(handlePoints(r), id: \.0) { handle, pt in
                handleView(for: handle)
                    .position(pt)
                    .gesture(handleGesture(handle))
            }
            cropActionBar(r)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectionFrame(_ r: CGRect) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white, lineWidth: 1.5)
            GeometryReader { g in
                let w = g.size.width / 3
                let h = g.size.height / 3
                Path { p in
                    for i in 1...2 {
                        p.move(to: CGPoint(x: w * CGFloat(i), y: 0))
                        p.addLine(to: CGPoint(x: w * CGFloat(i), y: g.size.height))
                        p.move(to: CGPoint(x: 0, y: h * CGFloat(i)))
                        p.addLine(to: CGPoint(x: g.size.width, y: h * CGFloat(i)))
                    }
                }
                .stroke(Color.white.opacity(0.34), lineWidth: 0.5)
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(Rectangle())
        .position(x: r.midX, y: r.midY)
        .gesture(moveGesture)
    }

    private func handleView(for handle: CropHandle) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(
                width: (handle == .top || handle == .bottom) ? 24 : 14,
                height: (handle == .left || handle == .right) ? 24 : 14
            )
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }

    private func cropActionBar(_ r: CGRect) -> some View {
        HStack(spacing: 6) {
            Button("적용", action: onApply)
                .buttonStyle(.borderedProminent)
            Button("전체", action: onReset)
            Button("취소", action: onCancel)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidSurface(cornerRadius: 8, interactive: true)
        .position(
            x: min(max(r.midX, imageFrame.minX + 86), imageFrame.maxX - 86),
            y: min(max(r.maxY + 30, imageFrame.minY + 28), imageFrame.maxY - 28)
        )
    }

    var screenRect: CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGRect(
            x: imageFrame.minX + cropRect.minX * imageFrame.width,
            y: imageFrame.minY + cropRect.minY * imageFrame.height,
            width: cropRect.width * imageFrame.width,
            height: cropRect.height * imageFrame.height
        )
    }

    var hasActiveCrop: Bool {
        cropRect.width < 0.995 || cropRect.height < 0.995
    }

    private func handlePoints(_ r: CGRect) -> [(CropHandle, CGPoint)] {
        [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.left, CGPoint(x: r.minX, y: r.midY))
        ]
    }

    var createGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartPoint == nil {
                    dragStartPoint = unitPoint(value.startLocation)
                }
                guard let start = dragStartPoint else { return }
                cropRect = unitRect(from: start, to: unitPoint(value.location))
            }
            .onEnded { _ in
                dragStartPoint = nil
            }
    }

    var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect, imageFrame.width > 0, imageFrame.height > 0 else { return }
                let dx = value.translation.width / imageFrame.width
                let dy = value.translation.height / imageFrame.height
                cropRect = movedRect(start.offsetBy(dx: dx, dy: dy))
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func handleGesture(_ handle: CropHandle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(canvasCoordinateSpace))
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect else { return }
                let p = unitPoint(value.location)
                var next = start
                switch handle {
                case .topLeft:
                    next = CGRect(x: p.x, y: p.y, width: start.maxX - p.x, height: start.maxY - p.y)
                case .top:
                    next = CGRect(x: start.minX, y: p.y, width: start.width, height: start.maxY - p.y)
                case .topRight:
                    next = CGRect(x: start.minX, y: p.y, width: p.x - start.minX, height: start.maxY - p.y)
                case .right:
                    next = CGRect(x: start.minX, y: start.minY, width: p.x - start.minX, height: start.height)
                case .bottomRight:
                    next = CGRect(x: start.minX, y: start.minY, width: p.x - start.minX, height: p.y - start.minY)
                case .bottom:
                    next = CGRect(x: start.minX, y: start.minY, width: start.width, height: p.y - start.minY)
                case .bottomLeft:
                    next = CGRect(x: p.x, y: start.minY, width: start.maxX - p.x, height: p.y - start.minY)
                case .left:
                    next = CGRect(x: p.x, y: start.minY, width: start.maxX - p.x, height: start.height)
                }
                cropRect = clampedUnitRect(next)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func unitPoint(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((point.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }

    private func movedRect(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, 0.035), 1)
        let height = min(max(rect.height, 0.035), 1)
        return CGRect(
            x: min(max(rect.minX, 0), 1 - width),
            y: min(max(rect.minY, 0), 1 - height),
            width: width,
            height: height
        )
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
        frame.updateParams { params in
            switch self {
            case .shadow: params.shadow = clamped
            case .density: params.density = clamped
            case .exposure: params.exposure = clamped
            case .highlight: params.highlight = clamped
            }
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
    @State private var sampledImageID: ObjectIdentifier?
    @State private var hoverRegion: HistogramToneRegion?
    @State private var dragRegion: HistogramToneRegion?
    @State private var dragStartValue: Double?

    init(image: NSImage, frame: ScanFrame, onChange: @escaping () -> Void) {
        self.image = image
        self._frame = ObservedObject(wrappedValue: frame)
        self.onChange = onChange
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
        .onAppear { refreshBinsIfNeeded() }
        .onChange(of: ObjectIdentifier(image)) { _, _ in refreshBinsIfNeeded(force: true) }
    }

    func activeBand(_ region: HistogramToneRegion, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: size.width * (region.upperBound - region.lowerBound), height: size.height)
            .offset(x: size.width * region.lowerBound)
    }

    func valueText(for region: HistogramToneRegion) -> String {
        "\(region.title) \(signedControlText(region.value(in: frame)))"
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

    private func refreshBinsIfNeeded(force: Bool = false) {
        let imageID = ObjectIdentifier(image)
        guard force || sampledImageID != imageID else { return }
        sampledImageID = imageID
        bins = HistogramSampler.compute(image)
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
                header(font: .subheadline.weight(.semibold))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header(font: .headline)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func header(font: Font) -> some View {
        HStack(spacing: 8) {
            Label("Scan", systemImage: "scanner")
                .font(font)
            Spacer()
            Text("Frame \(model.frames.count + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(model.activeScannerDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(model.filmType.displayName) · \(resolutionText)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Group {
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
                InspectorControlRow("Bit Depth") {
                    Picker("Bit Depth", selection: $model.bitDepthChoice) {
                        ForEach(bitDepths, id: \.self) { Text("\($0.rawValue)-bit").tag($0) }
                    }
                    .labelsHidden()
                }
                InspectorControlRow("Mode") {
                    Picker("Mode", selection: $model.colorModeChoice) {
                        ForEach(colorModes, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .labelsHidden()
                }
                Toggle("Multi-Sample", isOn: $model.multiExposureEnabled)
                    .font(.caption)
                    .disabled(model.resolutionChoice == .preview)
                Stepper("프레임: \(batchCount)", value: $batchCount, in: 1...12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.isScanning)
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
                        Text(scanButtonTitle)
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

    var scanButtonTitle: String {
        if batchCount > 1 { return "Scan ×\(batchCount)" }
        return model.selectedFrame == nil ? "Scan" : "Scan Next"
    }

    var resolutionText: String {
        model.resolutionChoice == .preview ? "Preview" : "\(model.resolutionChoice.dpi) dpi"
    }

    var resolutions: [Resolution] {
        let fromCap = (model.capabilities?.supportedResolutions ?? [.r900, .r1800, .r3600, .r7200])
            .filter { $0.dpi > 0 }
        return fromCap.isEmpty ? [.r3600, .r7200] : fromCap
    }

    var bitDepths: [BitDepth] {
        let fromCap = model.capabilities?.supportedBitDepths ?? [.eight, .sixteen]
        return fromCap.isEmpty ? [.sixteen] : fromCap
    }

    var colorModes: [ColorMode] {
        let fromCap = model.capabilities?.supportedModes ?? [.color, .gray]
        let visible = fromCap.filter { $0 == .color || $0 == .gray }
        return visible.isEmpty ? [.color] : visible
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
    case curve
    case color
    case calibration
    case detail
}

struct DevelopWorkflowInspector: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool
    @State private var expandedPanel: InspectorPanel? = .tone
    @State private var redevelopTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = displayedImage {
                InteractiveHistogramView(image: image, frame: frame) { scheduleRedevelop(frame) }
                    .disabled(model.isScanning)
            }

            ScanSection(collapsedByDefault: false)

            BaseControlSection(
                frame: frame,
                baseMode: baseModeBinding,
                manualBaseBinding: manualBaseBinding(channel:)
            )
            .disabled(model.isScanning)

            ToolStripSection(frame: frame, cropMode: $cropMode)

            WorkflowSection(
                title: "Basic Tone",
                systemImage: "slider.horizontal.3",
                isExpanded: expandedPanel == .tone,
                toggle: { toggle(.tone) },
                reset: { reset(.tone) },
                contentDisabled: model.isScanning
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
                InspectorSlider("Contrast", value: toneBinding(\.contrast), range: -1...1)
                InspectorSlider("Highlights", value: toneBinding(\.highlight), range: -1...1)
                InspectorSlider("Shadows", value: toneBinding(\.shadow), range: -1...1)
                InspectorSlider("Whites", value: toneBinding(\.whites), range: -1...1)
                InspectorSlider("Blacks", value: toneBinding(\.blacks), range: -1...1)
                InspectorSlider("Density", value: toneBinding(\.density), range: -1...1)
            }

            WorkflowSection(
                title: "Tone Curve",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                isExpanded: expandedPanel == .curve,
                toggle: { toggle(.curve) },
                reset: { reset(.curve) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Highlights", value: toneBinding(\.curveHighlights), range: -1...1)
                InspectorSlider("Lights", value: toneBinding(\.curveLights), range: -1...1)
                InspectorSlider("Darks", value: toneBinding(\.curveDarks), range: -1...1)
                InspectorSlider("Shadows", value: toneBinding(\.curveShadows), range: -1...1)
            }

            WorkflowSection(
                title: "Color",
                systemImage: "eyedropper.halffull",
                isExpanded: expandedPanel == .color,
                toggle: { toggle(.color) },
                reset: { reset(.color) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Warmth", value: toneBinding(\.warmth), range: -1...1)
                InspectorSlider("Tint", value: toneBinding(\.tint), range: -1...1)
                InspectorSlider("Vibrance", value: toneBinding(\.vibrance), range: -1...1)
                InspectorSlider("Saturation", value: toneBinding(\.saturation), range: -1...1)
                InspectorSlider("Color Depth", value: toneBinding(\.colorDepth), range: -1...1)
            }

            WorkflowSection(
                title: "Calibration",
                systemImage: "camera.filters",
                isExpanded: expandedPanel == .calibration,
                toggle: { toggle(.calibration) },
                reset: { reset(.calibration) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Red Primary", value: toneBinding(\.redPrimary), range: -1...1)
                InspectorSlider("Green Primary", value: toneBinding(\.greenPrimary), range: -1...1)
                InspectorSlider("Blue Primary", value: toneBinding(\.bluePrimary), range: -1...1)
            }

            WorkflowSection(
                title: "Detail & Effects",
                systemImage: "camera.macro",
                isExpanded: expandedPanel == .detail,
                toggle: { toggle(.detail) },
                reset: { reset(.detail) },
                contentDisabled: model.isScanning
            ) {
                InspectorSlider("Grain", value: toneBinding(\.grain), range: 0...1)
                InspectorSlider("Sharpness", value: toneBinding(\.sharpness), range: 0...1)
                InspectorSlider("Clarity", value: toneBinding(\.clarity), range: -1...1)
                InspectorSlider("Halation", value: toneBinding(\.halation), range: 0...1)
                InspectorSlider("Vignette", value: toneBinding(\.vignette), range: -1...1)
            }
        }
    }

    var displayedImage: NSImage? {
        frame.showDeveloped ? (frame.developedImage ?? frame.rawPreviewImage)
                            : (frame.rawPreviewImage ?? frame.developedImage)
    }

    func toggle(_ panel: InspectorPanel) {
        withAnimation(.snappy(duration: 0.18)) {
            expandedPanel = expandedPanel == panel ? nil : panel
        }
    }

    func reset(_ panel: InspectorPanel) {
        let defaults = DevelopParameters()
        frame.updateParams { params in
            switch panel {
            case .tone:
                frame.preset = model.presets.first(where: { $0.id == "neutral" })
                params.exposure = defaults.exposure
                params.contrast = defaults.contrast
                params.highlight = defaults.highlight
                params.shadow = defaults.shadow
                params.whites = defaults.whites
                params.blacks = defaults.blacks
                params.density = defaults.density
            case .curve:
                params.curveHighlights = defaults.curveHighlights
                params.curveLights = defaults.curveLights
                params.curveDarks = defaults.curveDarks
                params.curveShadows = defaults.curveShadows
            case .color:
                params.warmth = defaults.warmth
                params.tint = defaults.tint
                params.vibrance = defaults.vibrance
                params.saturation = defaults.saturation
                params.colorDepth = defaults.colorDepth
            case .calibration:
                params.redPrimary = defaults.redPrimary
                params.greenPrimary = defaults.greenPrimary
                params.bluePrimary = defaults.bluePrimary
            case .detail:
                params.grain = defaults.grain
                params.sharpness = defaults.sharpness
                params.clarity = defaults.clarity
                params.halation = defaults.halation
                params.vignette = defaults.vignette
            }
        }
        scheduleRedevelop(frame)
    }

    func toneBinding(_ keyPath: WritableKeyPath<DevelopParameters, Double>) -> Binding<Double> {
        Binding(
            get: { frame.params[keyPath: keyPath] },
            set: { value in
                frame.updateParams { $0[keyPath: keyPath] = value }
                scheduleRedevelop(frame)
            }
        )
    }

    var baseModeBinding: Binding<DevelopParameters.BaseMode> {
        Binding(
            get: { frame.params.baseEstimationMode },
            set: { mode in
                frame.updateParams { params in
                    params.baseEstimationMode = mode
                    if mode == .manual, params.manualBaseRGB == nil {
                        params.manualBaseRGB = frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                    }
                }
                scheduleRedevelop(frame)
            }
        )
    }

    func manualBaseBinding(channel: Int) -> Binding<Double> {
        Binding(
            get: {
                let rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                switch channel {
                case 0: return rgb.x
                case 1: return rgb.y
                default: return rgb.z
                }
            },
            set: { value in
                var rgb = frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
                let clamped = min(max(value, 0), 1)
                switch channel {
                case 0: rgb.x = clamped
                case 1: rgb.y = clamped
                default: rgb.z = clamped
                }
                frame.updateParams {
                    $0.manualBaseRGB = rgb
                    $0.baseEstimationMode = .manual
                }
                scheduleRedevelop(frame)
            }
        )
    }

    func scheduleRedevelop(_ frame: ScanFrame) {
        guard !model.isScanning else { return }
        redevelopTask?.cancel()
        redevelopTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await model.developFrame(frame)
        }
    }
}

struct BaseControlSection: View {
    @ObservedObject var frame: ScanFrame
    let baseMode: Binding<DevelopParameters.BaseMode>
    let manualBaseBinding: (Int) -> Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Base", systemImage: "camera.metering.center.weighted")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Base", selection: baseMode) {
                    Text("Auto").tag(DevelopParameters.BaseMode.auto)
                    Text("Manual").tag(DevelopParameters.BaseMode.manual)
                }
                .labelsHidden()
                .frame(maxWidth: 128)
                .disabled(!frame.filmType.requiresInversion)
            }
            if frame.params.baseEstimationMode == .manual {
                InspectorSlider("Base R", value: manualBaseBinding(0), range: 0...1)
                InspectorSlider("Base G", value: manualBaseBinding(1), range: 0...1)
                InspectorSlider("Base B", value: manualBaseBinding(2), range: 0...1)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ToolStripSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    @Binding var cropMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolRow
            VStack(alignment: .leading, spacing: 2) {
                Text("현재 · \(frame.imageTransform.displayName)")
                Text("다음 스캔 · \(model.nextScanOrientation.displayName)")
            }
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
                model.rotate(frame, clockwise: false)
            }
            ToolIconButton(systemName: "rotate.right", help: "오른쪽으로 회전") {
                model.rotate(frame, clockwise: true)
            }
            ToolIconButton(systemName: "arrow.left.and.right", help: "좌우 반전", isActive: frame.imageTransform.flipHorizontal) {
                model.flipHorizontally(frame)
            }
            ToolIconButton(systemName: "arrow.up.and.down", help: "상하 반전", isActive: frame.imageTransform.flipVertical) {
                model.flipVertically(frame)
            }
            Spacer()
            ToolIconButton(systemName: "arrow.counterclockwise", help: "현재 및 다음 스캔 변형 초기화", isDisabled: frame.imageTransform.isIdentity && model.nextScanOrientation.isIdentity && !cropMode) {
                cropMode = false
                model.resetTransform(frame)
            }
        }
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
    let reset: (() -> Void)?
    let contentDisabled: Bool
    let content: Content

    init(
        title: String,
        systemImage: String,
        isExpanded: Bool,
        toggle: @escaping () -> Void,
        reset: (() -> Void)? = nil,
        contentDisabled: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isExpanded = isExpanded
        self.toggle = toggle
        self.reset = reset
        self.contentDisabled = contentDisabled
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if let reset {
                    Button(action: reset) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .disabled(contentDisabled)
                    .help("\(title) 초기화")
                    .accessibilityLabel("\(title) 초기화")
                }
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .disabled(contentDisabled)
                .opacity(contentDisabled ? 0.55 : 1)
                .transition(.opacity)
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
                Text(signedControlText(value))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

private func signedControlText(_ value: Double) -> String {
    abs(value) < 0.005 ? "0.00" : String(format: "%+.2f", value)
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
                    Text("PNG").tag(ExportFormat.png)
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
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "frame\(frame.scanIndex).\(format.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            model.exportFrame(frame, to: url, format: format, writeSidecar: writeSidecar)
        }
    }
}

private extension ExportFormat {
    var contentType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff16, .rawScanTIFF: return .tiff
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff16, .rawScanTIFF: return "tif"
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
