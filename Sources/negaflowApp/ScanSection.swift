import SwiftUI
import Chromabase
import ScannerKit

// MARK: - ScannerControlsSection (스캐너 하드웨어 전용 컨트롤)
//
// "스캐너 불러오기"로 펼쳐지는 하드웨어 스캔 컨트롤(해상도/비트/모드/프레임수/Multi-Sample +
// Preview/Scan). Target/Film/Profile 같은 현상 기본값은 LibrarySourceSection이 공유로 소유한다.
// 스캐너/플러그인이 없으면 상태 + 설치 안내 + 시뮬레이터 토글을 보여준다.
struct ScannerControlsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var batchCount: Int = 1

    var body: some View {
        if model.hasScanner {
            controls
        } else {
            unavailableState
        }
    }

    // MARK: - 스캐너 사용 가능
    @ViewBuilder
    var controls: some View {
        Section {
            Picker("Scanner", selection: scannerDeviceBinding) {
                if model.demoMode {
                    Text(AppModel.mockDisplayName).tag(String?.some(AppModel.mockDeviceID))
                } else {
                    ForEach(model.scannerDevices) { device in
                        Text(device.displayName).tag(String?.some(device.id))
                    }
                }
            }
            .disabled(model.demoMode || model.scannerDevices.isEmpty || model.isScanning)

            Picker("Resolution", selection: $model.resolutionChoice) {
                Text("Preview").tag(Resolution.preview)
                ForEach(resolutions, id: \.self) { resolution in
                    Text("\(resolution.dpi) dpi").tag(resolution)
                }
            }

            Picker("Bit Depth", selection: $model.bitDepthChoice) {
                ForEach(bitDepths, id: \.self) { bitDepth in
                    Text(bitDepthLabel(bitDepth)).tag(bitDepth)
                }
            }

            Picker("Mode", selection: $model.colorModeChoice) {
                ForEach(colorModes, id: \.self) { colorMode in
                    Text(colorMode.rawValue.capitalized).tag(colorMode)
                }
            }

            Stepper("Frames: \(batchCount)", value: $batchCount, in: 1...12)

            Toggle("Multi-Sample", isOn: multiExposureBinding)
                .disabled(!canUseMultiExposure)
                .help(multiExposureHelp)

            // IR(적외선) 채널 — 스캐너/플러그인이 실제로 IR 옵션을 노출하는 기기에서만 표시(예: OpticFilm
            // "i" 기종). 먼지/스크래치 제거용 적외선 채널을 함께 스캔한다.
            if model.capabilities?.supportsInfrared == true {
                Toggle("Infrared (IR)", isOn: $model.infraredEnabled)
                    .disabled(model.resolutionChoice == .preview)
                    .help("적외선 채널로 스캔합니다(먼지·스크래치 감지용). IR 지원 기기에서만 표시됩니다.")
            }
        } header: {
            sectionHeader("Scan", systemImage: "scanner")
        }
        .disabled(model.isScanning)

        Section {
            scanButtons
        }
    }

    var scanButtons: some View {
        HStack(spacing: 8) {
            Button {
                Task { await model.runScan(preview: true) }
            } label: {
                Text("Preview").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canScan || model.isScanning)

            if model.isScanning {
                Button(role: .destructive) {
                    Task { await model.cancelScan() }
                } label: {
                    Text("취소").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await model.scanFrames(count: batchCount, preview: false) }
                } label: {
                    Text(scanButtonTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canScan)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    var scanButtonTitle: String {
        if batchCount > 1 { return "Scan ×\(batchCount)" }
        return model.selectedFrame == nil ? "Scan" : "Scan Next"
    }

    var scannerDeviceBinding: Binding<String?> {
        Binding(
            get: { model.selectedDeviceID },
            set: { deviceID in
                guard model.selectedDeviceID != deviceID else { return }
                model.selectedDeviceID = deviceID
                Task { await model.loadCapabilities() }
            }
        )
    }

    // MARK: - 스캐너/플러그인 없음
    @ViewBuilder
    var unavailableState: some View {
        Section {
            if model.hasScannerPlugin {
                Label("스캐너를 찾는 중 — USB 연결을 확인하세요.", systemImage: "cable.connector")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await model.refreshDevices() }
                } label: {
                    Label("스캐너 다시 찾기", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isDetecting)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("스캐너 플러그인이 설치되지 않았습니다.", systemImage: "puzzlepiece.extension")
                        .font(.callout.weight(.medium))
                    Text("필름 스캐너(SANE)는 라이센스 분리를 위해 별도 플러그인으로 제공됩니다. 설치하면 여기에서 스캔할 수 있습니다. 지금은 이미지 가져오기로 현상을 시작할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: Binding(get: { model.demoMode }, set: { model.toggleDemo($0) })) {
                Label("스캐너 시뮬레이터", systemImage: "wand.and.stars")
            }
            .help("플러그인 없이 스캔 워크플로우를 시연하는 내장 시뮬레이터")
        } header: {
            sectionHeader("Scan", systemImage: "scanner")
        }
    }

    // MARK: - capability 기반 옵션
    var resolutions: [Resolution] {
        let fromCap = (model.capabilities?.supportedResolutions ?? [.r900, .r1800, .r3600, .r7200])
            .filter { $0.dpi > 0 }
        return fromCap.isEmpty ? [.r3600, .r7200] : fromCap
    }

    /// 채널당 비트와 픽셀 합산 비트를 함께 표기한다.
    func bitDepthLabel(_ depth: BitDepth) -> String {
        let channels = model.colorModeChoice == .gray ? 1 : 3
        return "\(depth.rawValue)-bit/ch (\(depth.rawValue * channels)-bit)"
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

    var canUseMultiExposure: Bool {
        model.resolutionChoice != .preview && (model.capabilities?.supportsMultiExposure ?? false)
    }

    var multiExposureHelp: String {
        if model.resolutionChoice == .preview {
            return "Preview 스캔에서는 Multi-Sample을 사용하지 않습니다."
        }
        if model.capabilities?.supportsMultiExposure != true {
            return "현재 백엔드가 실제 하드웨어 노출 제어를 노출하지 않아 비활성화했습니다."
        }
        return "백엔드가 노출 제어를 지원하는 장치에서만 여러 스캔을 결합합니다."
    }

    var multiExposureBinding: Binding<Bool> {
        Binding(
            get: { canUseMultiExposure && model.multiExposureEnabled },
            set: { model.multiExposureEnabled = canUseMultiExposure && $0 }
        )
    }
}
