import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

// MARK: - ContentView (명시적 3칼럼 — 겹침 없는 순정 레이아웃)
//
// NavigationSplitView 의 .inspector 겹침 버그를 피하기 위해 분리.
// 툴바는 캔버스 위에만. 인스펙터는 오른쪽 독립 패널.
struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("workspace.leftPanelVisible") private var isSidebarVisible = true
    @AppStorage("workspace.rightPanelVisible") private var isInspectorVisible = true
    @AppStorage("workspace.bottomStripVisible") private var isFilmstripVisible = true
    @State private var showDiagnostics = false
    @State private var cropFrameID: UUID?
    @State private var brushFrameID: UUID?
    @State private var regionICEFrameID: UUID?
    @State private var selectedSidebarTab: WorkflowSidebarTab = .library

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                if isSidebarVisible {
                    WorkflowSidebar(
                        selectedTab: $selectedSidebarTab,
                        frame: model.selectedFrame
                    )
                    .frame(width: 400)
                }
                centerPane
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                if isInspectorVisible {
                    inspectorPane
                        .frame(width: 360)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.refreshDevices() }
    }

    var toolbar: some View {
        HStack(spacing: 10) {
            devicePicker

            scanQuickControls

            if model.isDetecting || model.isScanning {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 12)

            panelVisibilityControls

            appearancePicker

            utilityMenu

            exportQuickControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .focusEffectDisabled()
    }

    /// 스캐너명 우측 — 좌측탭 Library의 Preview / Scan Next 와 동일 동작(Scan 설정 그대로 사용).
    var scanQuickControls: some View {
        HStack(spacing: 2) {
            ToolbarActionButton(
                systemName: "eye",
                help: "Preview 스캔 (Library 설정 사용)",
                isDisabled: !model.canScan
            ) {
                Task { await model.runScan(preview: true) }
            }
            ToolbarActionButton(
                systemName: "viewfinder",
                help: model.selectedFrame == nil ? "Scan" : "Scan Next",
                isDisabled: !model.canScan
            ) {
                Task { await model.scanFrames(count: 1, preview: false) }
            }
        }
        .padding(1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    /// 우측 끝 — Quick Export(사전 설정 포맷/DPI 즉시 저장) + Export(저장 패널, Output탭과 동일).
    var exportQuickControls: some View {
        HStack(spacing: 2) {
            ToolbarActionButton(
                systemName: "bolt.badge.checkmark",
                help: "Quick Export — \(model.quickExportFormat.uiLabel) · \(model.quickExportDPI) dpi → \(model.quickExportFolderDisplay)",
                isDisabled: !(model.selectedFrame?.hasDevelopedOnce ?? false)
            ) {
                if let frame = model.selectedFrame { model.quickExport(frame) }
            }
            ToolbarActionButton(
                systemName: "square.and.arrow.up",
                help: "Export… (저장 위치 선택)",
                isDisabled: !(model.selectedFrame?.hasDevelopedOnce ?? false)
            ) {
                if let frame = model.selectedFrame { model.exportWithPanel(frame) }
            }
        }
        .padding(1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    var panelVisibilityControls: some View {
        HStack(spacing: 2) {
            PanelToggleButton(
                systemName: "sidebar.left",
                isOn: isSidebarVisible,
                help: isSidebarVisible ? "좌측 패널 닫기" : "좌측 패널 열기"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isSidebarVisible.toggle() }
            }

            PanelToggleButton(
                systemName: "rectangle.bottomthird.inset.filled",
                isOn: isFilmstripVisible,
                help: isFilmstripVisible ? "하단 필름스트립 닫기" : "하단 필름스트립 열기"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isFilmstripVisible.toggle() }
            }

            PanelToggleButton(
                systemName: "sidebar.right",
                isOn: isInspectorVisible,
                help: isInspectorVisible ? "우측 패널 닫기" : "우측 패널 열기"
            ) {
                withAnimation(.snappy(duration: 0.18)) { isInspectorVisible.toggle() }
            }
        }
        .padding(1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
        .help("좌측, 하단, 우측 패널 표시")
    }

    var appearancePicker: some View {
        Menu {
            ForEach(AppAppearanceMode.allCases) { mode in
                Button {
                    model.appearanceMode = mode
                } label: {
                    Label(mode.displayName, systemImage: mode.systemImage)
                }
            }
        } label: {
            Image(systemName: model.appearanceMode.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .help("시스템 자동, 다크, 라이트 모드")
        .accessibilityLabel("화면 모드")
    }

    var utilityMenu: some View {
        Menu {
            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label("스캐너 다시 찾기", systemImage: "arrow.clockwise")
            }
            .disabled(model.isDetecting)

            Toggle(isOn: Binding(get: { model.demoMode }, set: { model.toggleDemo($0) })) {
                Label("스캐너 시뮬레이터", systemImage: "scanner")
            }

            Divider()

            Button {
                Task { await model.runDiagnostics() }
                showDiagnostics = true
            } label: {
                Label("진단 보기", systemImage: "waveform.path.ecg")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .help("작업 옵션")
        .accessibilityLabel("작업 옵션")
        .popover(isPresented: $showDiagnostics) {
            Text(model.diagnostics.isEmpty ? "진단 정보 없음" : model.diagnostics)
                .font(.system(.body, design: .monospaced))
                .padding()
                .frame(minWidth: 320, maxWidth: 440)
                .textSelection(.enabled)
        }
    }

    var devicePicker: some View {
        Menu {
            if model.hasSANE {
                ForEach(model.saneDevices) { device in
                    Button(device.displayName) {
                        model.selectedDeviceID = device.id
                        Task { await model.loadCapabilities() }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scanner")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.activeScannerDisplayName)
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    @ViewBuilder
    var filmstrip: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollViewReader { proxy in
                HStack(spacing: 0) {
                    FrameStepButton(
                        systemName: "chevron.left",
                        help: "이전 프레임",
                        isDisabled: !canSelectPreviousFrame
                    ) {
                        selectAdjacentFrame(-1)
                    }

                    if model.frames.isEmpty {
                        ContentUnavailableView(
                            "스캔 없음",
                            systemImage: "film"
                        )
                        .frame(maxWidth: .infinity, minHeight: 106)
                        .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 10) {
                                ForEach(model.frames) { frame in
                                    FrameStripItemView(
                                        frame: frame,
                                        isSelected: model.selectedFrameID == frame.id,
                                        onSelect: { model.selectedFrameID = frame.id }
                                    )
                                    .id(frame.id)
                                    .contextMenu {
                                        Menu("Rating") {
                                            Button("Clear Rating") { frame.setRating(0) }
                                            ForEach(1...5, id: \.self) { value in
                                                Button("\(value) star") { frame.setRating(value) }
                                            }
                                        }
                                        Button(frame.pickState == .picked ? "Clear Pick" : "Pick") {
                                            frame.pickState = frame.pickState == .picked ? .unflagged : .picked
                                        }
                                        Button(frame.pickState == .rejected ? "Clear Reject" : "Reject") {
                                            frame.pickState = frame.pickState == .rejected ? .unflagged : .rejected
                                        }
                                        Divider()
                                        Button("Virtual Copy") { model.createVirtualCopy(from: frame) }
                                        Button("삭제", role: .destructive) { model.deleteFrame(frame) }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }

                    FrameStepButton(
                        systemName: "chevron.right",
                        help: "다음 프레임",
                        isDisabled: !canSelectNextFrame
                    ) {
                        selectAdjacentFrame(1)
                    }
                }
                .onChange(of: model.frames.count) { _, _ in
                    guard let id = model.frames.last?.id else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .trailing)
                    }
                }
                .onChange(of: model.selectedFrameID) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 152)
        .background(.bar)
    }

    var selectedFrameIndex: Int? {
        guard let id = model.selectedFrameID else { return nil }
        return model.frames.firstIndex { $0.id == id }
    }

    var canSelectPreviousFrame: Bool {
        guard let index = selectedFrameIndex else { return false }
        return index > 0
    }

    var canSelectNextFrame: Bool {
        guard let index = selectedFrameIndex else { return false }
        return index < model.frames.count - 1
    }

    func selectAdjacentFrame(_ offset: Int) {
        guard let index = selectedFrameIndex else { return }
        let nextIndex = min(max(index + offset, 0), model.frames.count - 1)
        guard model.frames.indices.contains(nextIndex) else { return }
        model.selectedFrameID = model.frames[nextIndex].id
    }

    // MARK: center pane — 캔버스 + 상태바
    @ViewBuilder
    var centerPane: some View {
        VStack(spacing: 0) {
            ZStack {
                model.canvasBackground.color
                if model.isDetecting {
                    DetectingView()
                } else if let frame = model.selectedFrame {
                    CanvasView(
                        frame: frame,
                        cropMode: cropModeBinding(for: frame),
                        brushMode: brushModeBinding(for: frame),
                        regionICEMode: regionICEModeBinding(for: frame)
                    )
                        .id(frame.id)
                } else {
                    ContentUnavailableView("프레임 없음", systemImage: "photo.on.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isFilmstripVisible {
                filmstrip
            }
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
            } else if model.processingActive, !model.processingDetail.isEmpty {
                // 현상 처리(슬라이더/선택/배치 후처리)는 텍스트만 표시한다 — 스피너(프로그래스바)가
                // 계속 도는 인상을 주지 않게 한다. 끝나면 processingActive=false 로 즉시 사라진다.
                Text(model.processingDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(model.statusMessage)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
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
        VStack(spacing: 0) {
            inspectorHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let frame = model.selectedFrame {
                        DevelopWorkflowInspector(
                            frame: frame,
                            cropMode: cropModeBinding(for: frame),
                            brushMode: brushModeBinding(for: frame),
                            regionICEMode: regionICEModeBinding(for: frame)
                        )
                    } else {
                        ContentUnavailableView(
                            "프레임 없음",
                            systemImage: "slider.horizontal.3"
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipped()
    }

    var inspectorHeader: some View {
        HStack(spacing: 8) {
            Label("Develop", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(model.selectedFrame?.compactDisplayName ?? "No Frame")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                if let frame = model.selectedFrame {
                    Text("\(frame.params.developTarget.displayName) · \(frame.filmType.displayName)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    func cropModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { cropFrameID == frame.id },
            set: { isOn in
                cropFrameID = isOn ? frame.id : nil
                if isOn { brushFrameID = nil; regionICEFrameID = nil }
            }
        )
    }

    func brushModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { brushFrameID == frame.id },
            set: { isOn in
                brushFrameID = isOn ? frame.id : nil
                if isOn { cropFrameID = nil; regionICEFrameID = nil }
            }
        )
    }

    func regionICEModeBinding(for frame: ScanFrame) -> Binding<Bool> {
        Binding(
            get: { regionICEFrameID == frame.id },
            set: { isOn in
                regionICEFrameID = isOn ? frame.id : nil
                if isOn { cropFrameID = nil; brushFrameID = nil }
                else { model.cancelRegionICE(frame) }   // 모드 종료 시 진행 중 세션 정리
            }
        )
    }
}

private struct PanelToggleButton: View {
    let systemName: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(isOn ? Color.primary : Color.secondary.opacity(0.7))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.primary.opacity(0.06) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ToolbarActionButton: View {
    let systemName: String
    let help: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.5) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct FrameStepButton: View {
    let systemName: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 106)
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45) : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isDisabled ? 0.025 : 0.055))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.horizontal, 8)
        .help(help)
        .accessibilityLabel(help)
    }
}
