import SwiftUI
import Chromabase
import ScannerKit

struct ScanSection: View {
    @EnvironmentObject var model: AppModel
    @State private var batchCount: Int = 1

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Target")
                SegmentedPicker(
                    options: scanTargets,
                    label: { $0.displayName },
                    selection: targetBinding
                )
            }

            Picker("Film Profile", selection: scannerProfileBinding) {
                if filteredScannerProfiles.isEmpty {
                    Text(scannerProfilePlaceholder).tag(String?.none)
                } else {
                    ForEach(filteredScannerProfiles) { profile in
                        Text(profile.filmKey.capitalized).tag(profile.id as String?)
                    }
                }
            }
            .disabled(filteredScannerProfiles.isEmpty)

            Picker("Film", selection: filmTypeBinding) {
                ForEach(FilmType.allCases, id: \.self) { filmType in
                    Text(filmType.displayName).tag(filmType)
                }
            }

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
        } header: {
            sectionHeader("Scan", systemImage: "scanner", trailing: "Frame \(model.frames.count + 1)")
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
                Text("Preview")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!model.canScan || model.isScanning)

            if model.isScanning {
                Button(role: .destructive) {
                    Task { await model.cancelScan() }
                } label: {
                    Text("취소")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    var scanButtonTitle: String {
        if batchCount > 1 { return "Scan ×\(batchCount)" }
        return model.selectedFrame == nil ? "Scan" : "Scan Next"
    }

    var scanTargets: [DevelopTarget] {
        [.main, .noritsu, .sp3000]
    }

    var activeDevelopTarget: DevelopTarget {
        model.selectedFrame?.params.developTarget ?? model.developTarget
    }

    var activeFilmType: FilmType {
        model.selectedFrame?.filmType ?? model.filmType
    }

    var scannerProfileSummary: String {
        guard let selected = selectedScannerProfile else { return "profile 없음" }
        return selected.filmKey
    }

    var scannerProfilePlaceholder: String {
        activeDevelopTarget == .main ? "main" : "수동 선택"
    }

    var selectedScannerProfile: ScannerProfile? {
        guard let id = model.selectedFrame?.params.scannerProfileID ?? model.scannerProfileID else { return nil }
        return model.scannerProfiles.first(where: { $0.id == id })
    }

    var filteredScannerProfiles: [ScannerProfile] {
        ScannerProfileMatcher.matchingProfiles(
            target: activeDevelopTarget,
            filmType: activeFilmType,
            profiles: model.scannerProfiles
        )
    }

    var targetBinding: Binding<DevelopTarget> {
        Binding(
            get: { activeDevelopTarget },
            set: { target in
                applyDevelopTarget(target)
            }
        )
    }

    var filmTypeBinding: Binding<FilmType> {
        Binding(
            get: { activeFilmType },
            set: { filmType in
                applyFilmType(filmType)
            }
        )
    }

    var scannerProfileBinding: Binding<String?> {
        Binding(
            get: { model.selectedFrame?.params.scannerProfileID ?? model.scannerProfileID },
            set: { profileID in
                model.scannerProfileID = profileID
                guard let frame = model.selectedFrame else { return }
                frame.updateParams { $0.scannerProfileID = profileID }
                Task { await model.developFrame(frame) }
            }
        )
    }

    var resolutions: [Resolution] {
        let fromCap = (model.capabilities?.supportedResolutions ?? [.r900, .r1800, .r3600, .r7200])
            .filter { $0.dpi > 0 }
        return fromCap.isEmpty ? [.r3600, .r7200] : fromCap
    }

    /// 채널당 비트와 픽셀 합산 비트를 함께 표기한다. SANE의 depth는 채널당 값이라
    /// "16-bit"가 곧 48-bit 컬러임을 분명히 한다(흑백은 채널 1개).
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

    func applyDevelopTarget(_ target: DevelopTarget) {
        model.developTarget = target
        let profileID = compatibleManualScannerProfileID(target: target, filmType: activeFilmType)
        model.scannerProfileID = profileID
        guard let frame = model.selectedFrame else { return }
        frame.updateParams {
            $0.developTarget = target
            $0.scannerProfileID = profileID
        }
        Task { await model.developFrame(frame) }
    }

    func applyFilmType(_ filmType: FilmType) {
        model.filmType = filmType
        let profileID = compatibleManualScannerProfileID(target: activeDevelopTarget, filmType: filmType)
        model.scannerProfileID = profileID
        guard let frame = model.selectedFrame else { return }
        frame.filmType = filmType
        frame.updateParams {
            $0.filmType = filmType
            $0.scannerProfileID = profileID
        }
        Task { await model.developFrame(frame) }
    }

    func compatibleManualScannerProfileID(target: DevelopTarget, filmType: FilmType) -> String? {
        let currentID = model.selectedFrame?.params.scannerProfileID ?? model.scannerProfileID
        guard let currentID else { return nil }
        let matches = ScannerProfileMatcher.matchingProfiles(
            target: target,
            filmType: filmType,
            profiles: model.scannerProfiles
        )
        return matches.contains(where: { $0.id == currentID }) ? currentID : nil
    }
}

