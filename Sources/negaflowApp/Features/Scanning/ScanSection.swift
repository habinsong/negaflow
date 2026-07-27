import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import Foundation

// MARK: - ScannerControlsSection (스캐너 하드웨어 전용 컨트롤)
//
// "스캐너 불러오기"로 펼쳐지는 하드웨어 스캔 컨트롤(필름 종류/저장 폴더/해상도/비트/모드/
// 프레임수 + Preview/Scan). 현상 프로세스/Target/Profile은 LibrarySourceSection이 공유로 소유한다.
// 스캐너/플러그인이 없으면 상태 + 설치 안내 + 시뮬레이터 토글을 보여준다.
struct ScannerControlsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var batchCount: Int = 1
    @State private var isHardwareScanAreaExpanded = false
    @FocusState private var isFolderNameFocused: Bool

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
            Picker(model.text(AppLocalizedPhrase.scannerLabel), selection: scannerDeviceBinding) {
                ForEach(model.selectableScannerDevices) { device in
                    Text(device.displayName).tag(String?.some(device.id))
                }
            }
            .disabled(model.selectableScannerDevices.isEmpty || model.isScanning)

            Picker(model.text(AppLocalizedPhrase.film), selection: scanFilmTypeBinding) {
                ForEach(FilmType.allCases, id: \.self) { filmType in
                    Text(filmType.displayName(language: model.appLanguage)).tag(filmType)
                }
            }

            LabeledContent(model.text(AppLocalizedPhrase.scanFolderName)) {
                HStack(spacing: 6) {
                    TextField(
                        model.text(AppLocalizedPhrase.untitledFilm),
                        text: scanFolderNameBinding
                    )
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($isFolderNameFocused)
                    .onSubmit(model.commitScanFolderName)
                    .onChange(of: isFolderNameFocused) { _, focused in
                        if !focused {
                            model.commitScanFolderName()
                        }
                    }

                    Button(action: chooseScanStorageRoot) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help(model.text(AppLocalizedPhrase.chooseScanFolder))
                    .accessibilityLabel(model.text(AppLocalizedPhrase.chooseScanFolder))
                }
            }

            HStack(spacing: 8) {
                resolutionMenu
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: "|")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker(model.text(AppLocalizedPhrase.colorMode), selection: $model.colorModeChoice) {
                    ForEach(colorModes, id: \.self) { colorMode in
                        Text(colorMode.rawValue.capitalized).tag(colorMode)
                    }
                }
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // 심도를 보고하지 않는 스캐너는 스캔 자체가 불가능하다(canScan). 빈 Picker만 두면
            // 프리뷰/스캔이 왜 잠겼는지 알 수 없으므로 사유를 대신 보여준다.
            if bitDepths.isEmpty {
                Label(
                    model.text(AppLocalizedPhrase.bitDepthUnavailable),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(model.text(AppLocalizedPhrase.bitDepth), selection: $model.bitDepthChoice) {
                    ForEach(bitDepths, id: \.self) { bitDepth in
                        Text(bitDepthLabel(bitDepth)).tag(bitDepth)
                    }
                }
            }

            if !model.availableScanFrameFormats.isEmpty {
                Picker(
                    model.text(AppLocalizedPhrase.filmFrameFormat),
                    selection: scanFrameFormatBinding
                ) {
                    ForEach(model.availableScanFrameFormats, id: \.self) { frameFormat in
                        Text(verbatim: frameFormat.displayName).tag(frameFormat)
                    }
                }
            }

            if model.demoMode, model.scanFrameFormat.is35mm {
                Toggle(
                    model.text(AppLocalizedPhrase.perforation),
                    isOn: Binding(
                        get: { model.scannerSimulatorIncludesPerforation },
                        set: { model.setScannerSimulatorIncludesPerforation($0) }
                    )
                )
            }

            if model.usesFlatbedRegionWorkflow {
                flatbedRegionControls
            } else {
                hardwareScanAreaControls
                Stepper(model.text(AppLocalizedPhrase.framesFormat, batchCount), value: $batchCount, in: 1...12)
            }

            // IR(적외선) 채널 — 스캐너/플러그인이 실제로 IR 옵션을 노출하는 기기에서만 표시(예: OpticFilm
            // "i" 기종). 먼지/스크래치 제거용 적외선 채널을 함께 스캔한다.
            if model.capabilities?.supportsInfrared == true {
                Toggle(model.text(AppLocalizedPhrase.infrared), isOn: $model.infraredEnabled)
                    .disabled(
                        model.resolutionChoice == .preview
                            || !InfraredFilmCompatibility(
                                filmType: model.scanFilmType
                            ).allowsAutomaticCorrection
                    )
                    .help(infraredHelp)
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.scanSection), systemImage: "scanner")
        }
        .disabled(model.isScanning)

        Section {
            scanButtons
        }
    }

    private var resolutionMenu: some View {
        Picker(model.text(AppLocalizedPhrase.resolution), selection: $model.resolutionChoice) {
            ForEach(resolutions, id: \.self) { resolution in
                Text("\(resolution.dpi) dpi").tag(resolution)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(resolutions.isEmpty)
        .accessibilityLabel(model.text(AppLocalizedPhrase.resolution))
    }

    private var infraredHelp: String {
        if InfraredFilmCompatibility(
            filmType: model.scanFilmType
        ).allowsAutomaticCorrection {
            return model.text(AppLocalizedPhrase.infraredHelp)
        }
        return model.infraredText(.unavailableForFilmHelp)
    }

    var scanButtons: some View {
        HStack(spacing: 8) {
            if model.capabilities?.supportsPreview == true {
                Button {
                    Task { await model.runScan(preview: true) }
                } label: {
                    Text(model.text(AppLocalizedPhrase.preview)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canPreview)
            }

            if model.isScanning {
                Button(role: .destructive) {
                    Task { await model.cancelScan() }
                } label: {
                    Text(model.text(AppLocalizedPhrase.cancel)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    let count = model.usesFlatbedRegionWorkflow
                        ? model.flatbedScanRegions.count
                        : batchCount
                    Task { await model.scanFrames(count: count, preview: false) }
                } label: {
                    Text(scanButtonTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStartFullScan)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
    }

    var scanButtonTitle: String {
        if model.usesFlatbedRegionWorkflow {
            let count = model.flatbedScanRegions.count
            return count > 0
                ? model.text(AppLocalizedPhrase.scanCountFormat, count)
                : model.text(AppLocalizedPhrase.scan)
        }
        if batchCount > 1 { return model.text(AppLocalizedPhrase.scanCountFormat, batchCount) }
        return model.actionableFrame == nil ? model.text(AppLocalizedPhrase.scan) : model.text(AppLocalizedPhrase.scanNext)
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

    private var scanFilmTypeBinding: Binding<FilmType> {
        Binding(
            get: { model.scanFilmType },
            set: { model.selectScanFilmType($0) }
        )
    }

    private var scanFrameFormatBinding: Binding<FilmFrameFormat> {
        Binding(
            get: { model.scanFrameFormat },
            set: { frameFormat in
                Task { await model.selectScanFrameFormat(frameFormat) }
            }
        )
    }

    private var scanFolderNameBinding: Binding<String> {
        Binding(
            get: { model.scanFolderNameText },
            set: { model.updateScanFolderName($0) }
        )
    }

    private func chooseScanStorageRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        panel.directoryURL = DiskStorageStore.ensureDirectory(model.diskStorage.scansURL)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                model.selectScanStorageRoot(folder)
            }
        }
    }

    // MARK: - 스캐너/플러그인 없음
    @ViewBuilder
    var unavailableState: some View {
        Section {
            if !model.scannerPluginsRequiringApproval.isEmpty {
                Label(
                    model.text(AppLocalizedPhrase.scannerPluginApprovalTitle),
                    systemImage: "checkmark.shield"
                )
                .font(.callout.weight(.medium))
                ScannerPluginTrustRows(plugins: model.scannerPluginsRequiringApproval)
            } else if model.hasApprovedScannerPlugin {
                Label(
                    model.text(model.isDetecting ? AppLocalizedPhrase.scannerSearching : AppLocalizedPhrase.scannerWaitingStatus),
                    systemImage: "cable.connector"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.text(AppLocalizedPhrase.scannerPluginMissingTitle), systemImage: "puzzlepiece.extension")
                        .font(.callout.weight(.medium))
                    Text(model.text(AppLocalizedPhrase.scannerPluginMissingBody))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label(model.text(.commandDetectScanners), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.isDetecting)

            Toggle(isOn: Binding(get: { model.demoMode }, set: { model.toggleDemo($0) })) {
                Label(model.text(AppLocalizedPhrase.scannerSimulator), systemImage: "cpu")
            }
            .help(model.text(AppLocalizedPhrase.scannerSimulatorHelp))
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.scanSection), systemImage: "scanner")
        }
    }

    // MARK: - capability 기반 옵션
    var resolutions: [Resolution] {
        (model.capabilities?.supportedResolutions ?? [])
            .filter { $0.dpi > 0 }
    }

    /// 채널당 비트와 픽셀 합산 비트를 함께 표기한다.
    func bitDepthLabel(_ depth: BitDepth) -> String {
        let channels = model.colorModeChoice == .gray ? 1 : 3
        return "\(depth.rawValue)-bit/ch (\(depth.rawValue * channels)-bit)"
    }

    var bitDepths: [BitDepth] {
        model.capabilities?.supportedBitDepths ?? []
    }

    var colorModes: [ColorMode] {
        (model.capabilities?.supportedModes ?? []).filter { $0 == .color || $0 == .gray }
    }

    @ViewBuilder
    var hardwareScanAreaControls: some View {
        if let bounds = model.hardwareScanAreaBounds,
           model.selectedHardwareScanArea != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isHardwareScanAreaExpanded.toggle()
                        }
                    } label: {
                        Text(model.text(AppLocalizedPhrase.hardwareScanArea))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(model.text(AppLocalizedPhrase.full)) {
                        model.resetHardwareScanArea()
                    }
                    .controlSize(.small)

                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            isHardwareScanAreaExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isHardwareScanAreaExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.text(AppLocalizedPhrase.hardwareScanArea))
                }

                if isHardwareScanAreaExpanded {
                    scanAreaDimensionRow(
                        label: .scanAreaWidth,
                        keyPath: \.widthMM,
                        bounds: bounds
                    )
                    scanAreaDimensionRow(
                        label: .scanAreaHeight,
                        keyPath: \.heightMM,
                        bounds: bounds
                    )
                }
            }
        }
    }

    @ViewBuilder
    var flatbedRegionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.text(
                    AppLocalizedPhrase.flatbedFramesFormat,
                    model.flatbedScanRegions.count
                ))
                Spacer()
                if model.selectedFlatbedScanRegionID != nil {
                    Button(role: .destructive) {
                        model.deleteSelectedFlatbedScanRegion()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(model.text(AppLocalizedPhrase.delete))
                }
            }

            Button {
                model.addFlatbedScanRegion()
            } label: {
                Label(model.text(AppLocalizedPhrase.flatbedAddFrame), systemImage: "plus")
            }
            .disabled(model.flatbedPreviewFrame == nil)
        }
    }

    func scanAreaDimensionRow(
        label: AppLocalizedPhrase,
        keyPath: WritableKeyPath<ScanArea, Double>,
        bounds: PhysicalScanAreaBounds
    ) -> some View {
        let binding = scanAreaDimensionBinding(keyPath, bounds: bounds)
        return HStack(spacing: 8) {
            Text(model.text(label))
                .frame(width: 44, alignment: .leading)
            Slider(
                value: binding,
                in: scanAreaDisplayRange(keyPath, bounds: bounds),
                step: bounds.displayUnit == .inch ? 0.01 : 0.1
            )
            ScanAreaDimensionValue(
                value: binding.wrappedValue,
                displayText: scanAreaDisplayText(binding.wrappedValue, unit: bounds.displayUnit),
                unit: bounds.displayUnit,
                range: scanAreaDisplayRange(keyPath, bounds: bounds),
                onCommit: { binding.wrappedValue = $0 },
                onCancel: {
                    let maximumMM = bounds.maximum[keyPath: keyPath]
                    binding.wrappedValue = bounds.displayUnit.displayValue(fromMillimeters: maximumMM)
                        ?? maximumMM
                }
            )
            .accessibilityLabel(model.text(label))
        }
    }

    func scanAreaDimensionBinding(
        _ keyPath: WritableKeyPath<ScanArea, Double>,
        bounds: PhysicalScanAreaBounds
    ) -> Binding<Double> {
        Binding(
            get: {
                let millimeters = model.selectedHardwareScanArea?[keyPath: keyPath]
                    ?? bounds.maximum[keyPath: keyPath]
                return bounds.displayUnit.displayValue(fromMillimeters: millimeters) ?? millimeters
            },
            set: { displayValue in
                guard let millimeters = bounds.displayUnit.millimeters(fromDisplayValue: displayValue) else {
                    return
                }
                var area = model.selectedHardwareScanArea ?? bounds.maximum
                area[keyPath: keyPath] = millimeters
                model.updateHardwareScanArea(area)
            }
        )
    }

    func scanAreaDisplayRange(
        _ keyPath: KeyPath<ScanArea, Double>,
        bounds: PhysicalScanAreaBounds
    ) -> ClosedRange<Double> {
        let minimumMM = bounds.minimum[keyPath: keyPath]
        let maximumMM = bounds.maximum[keyPath: keyPath]
        let minimum = bounds.displayUnit.displayValue(fromMillimeters: minimumMM) ?? minimumMM
        let maximum = bounds.displayUnit.displayValue(fromMillimeters: maximumMM) ?? maximumMM
        return minimum...maximum
    }

    func scanAreaDisplayText(_ value: Double, unit: ScanAreaUnit) -> String {
        let fractionDigits = unit == .inch ? 2 : 1
        let number = value.formatted(.number.precision(.fractionLength(fractionDigits)))
        let separator = String(Character(" "))
        return number + separator + unit.symbol
    }
}

private struct ScanAreaDimensionValue: View {
    let value: Double
    let displayText: String
    let unit: ScanAreaUnit
    let range: ClosedRange<Double>
    let onCommit: (Double) -> Void
    let onCancel: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isInvalid = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(displayText, text: $draft)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isInvalid ? Color.red : Color.primary)
                    .frame(width: 62, alignment: .trailing)
                    .focused($isFocused)
                    .onSubmit(commitDraft)
                    .onExitCommand(perform: cancelToFullValue)
                    .onChange(of: isFocused) { _, focused in
                        if !focused, isEditing {
                            commitDraft()
                        }
                    }
            } else {
                Button(action: beginEditing) {
                    Text(displayText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 62, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func beginEditing() {
        draft = inputText(value)
        isInvalid = false
        isEditing = true
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func commitDraft() {
        let normalized = draft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed.isFinite else {
            isInvalid = true
            NSSound.beep()
            isEditing = false
            isFocused = false
            return
        }
        onCommit(min(max(parsed, range.lowerBound), range.upperBound))
        isInvalid = false
        isEditing = false
        isFocused = false
    }

    private func cancelToFullValue() {
        onCancel()
        isInvalid = false
        isEditing = false
        isFocused = false
    }

    private func inputText(_ value: Double) -> String {
        String(
            format: unit == .inch ? "%.2f" : "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }
}
