import AppKit
import Chromabase
import SwiftUI
import UniformTypeIdentifiers

/// 워터마크 레이아웃의 촬영 정보 띠 설정.
struct PrintWatermarkInspectorControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore

    private var watermark: Binding<PrintWatermarkSettings> { $settingsStore.watermark }
    private var settings: PrintWatermarkSettings { settingsStore.watermark }

    var body: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            appearanceRows
            Divider().opacity(0.4)
            shotRows
            Divider().opacity(0.4)
            extraRows
        }
    }

    // MARK: - 배경·여백

    @ViewBuilder
    private var appearanceRows: some View {
        PrintInspectorStackedField(text(.background)) {
            PrintInspectorSegmentedPicker(
                options: PrintWatermarkBackground.allCases,
                label: backgroundTitle,
                selection: watermark.background
            )
        }
        .accessibilityIdentifier("negaflow.print.watermark.background")

        if settings.background == .blur {
            PrintInspectorStackedField(text(.textColor)) {
                inkPicker(watermark.blurTextInk)
            }
            .accessibilityIdentifier("negaflow.print.watermark.text-ink")
        }

        PrintInspectorBooleanSegmentedField(
            label: text(.topBand),
            isOn: watermark.addsTopBand
        )
        .accessibilityIdentifier("negaflow.print.watermark.top-band")

        PrintInspectorSliderRow(
            label: text(.bandHeight),
            value: bandHeightPercent,
            range: percentRange,
            step: 1,
            valueText: "\(Int(bandHeightPercent.wrappedValue.rounded()))%",
            inputFractionDigits: 0
        )
    }

    // MARK: - 카메라·렌즈·로고·노출·일시

    @ViewBuilder
    private var shotRows: some View {
        textRow(.camera, \.cameraName)
        textRow(.lens, \.lensName)
        logoRow
        // 노출 값(초점거리·조리개·셔터·ISO)은 오른쪽 정렬한다.
        PrintInspectorPairedInlineFields(
            leadingTitle: text(.focalLength),
            leadingControl: { field(\.focalLength, alignment: .trailing) },
            trailingTitle: text(.aperture),
            trailingControl: { field(\.aperture, alignment: .trailing) }
        )
        PrintInspectorPairedInlineFields(
            leadingTitle: text(.shutter),
            leadingControl: { field(\.shutterSpeed, alignment: .trailing) },
            trailingTitle: text(.iso),
            trailingControl: { field(\.iso, alignment: .trailing) }
        )
        textRow(.captureDate, \.captureDate)
    }

    /// 로고를 켜고 파일을 고르지 않으면 negaflow 로고가 들어간다. 고른 파일이 지워졌으면 로고만 빠지고
    /// 그 사실은 하단 상태 점·진단에 남는다(여기에는 띄우지 않는다).
    @ViewBuilder
    private var logoRow: some View {
        PrintInspectorBooleanSegmentedField(label: text(.logo), isOn: watermark.showsLogo)
            .accessibilityIdentifier("negaflow.print.watermark.logo-enabled")
        if settings.showsLogo {
            PrintInspectorInlineField(text(.logoFile)) {
                HStack(spacing: 6) {
                    if let data = PrintWatermarkLogoLoader.logo(for: settings), let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 48, maxHeight: 22)
                            .accessibilityHidden(true)
                    }
                    Text(settings.logoSourcePath.isEmpty
                         ? "negaflow"
                         : URL(fileURLWithPath: settings.logoSourcePath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.logoSourcePath)
                    Spacer(minLength: 0)
                    Button(action: chooseLogo) {
                        Text(text(.chooseLogo))
                            .lineLimit(1)
                    }
                    .buttonStyle(PrintInspectorTransientButtonStyle())
                    .accessibilityIdentifier("negaflow.print.watermark.logo")
                    if !settings.logoSourcePath.isEmpty {
                        Button {
                            settingsStore.watermark.logoSourcePath = ""
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(PrintInspectorTransientButtonStyle(horizontalPadding: 9))
                        .help(text(.removeLogo))
                        .accessibilityLabel(text(.removeLogo))
                    }
                }
            }
        }
    }

    // MARK: - 히스토그램·이름

    @ViewBuilder
    private var extraRows: some View {
        PrintInspectorBooleanSegmentedField(
            label: text(.histogram),
            isOn: watermark.showsHistogram
        )
        .accessibilityIdentifier("negaflow.print.watermark.histogram")

        if settings.showsHistogram {
            if settings.background == .blur {
                PrintInspectorStackedField(text(.histogramColor)) {
                    inkPicker(watermark.blurHistogramInk)
                }
            }
            if settings.addsTopBand {
                placementPicker(watermark.histogramPlacement)
            }
        }

        textRow(.userName, \.userName, alignment: .center)
        placementPicker(Binding(
            get: { settings.effectivePlacement(settings.userNamePlacement) },
            set: { placement in
                settingsStore.watermark.userNamePlacement = placement
                if placement != .bottomCenter { settingsStore.watermark.addsTopBand = true }
            }
        ))
    }

    // MARK: - 도우미

    private func textRow(
        _ title: PrintWatermarkLocalizedText,
        _ keyPath: WritableKeyPath<PrintWatermarkSettings, String>,
        alignment: TextAlignment = .leading
    ) -> some View {
        PrintInspectorInlineField(text(title)) {
            field(keyPath, alignment: alignment)
        }
    }

    /// 빈 칸은 음영 칸만 보인다. 라벨이 바로 옆에 있으므로 칸 안에 이름이나 예시 값(날짜·숫자)을 넣지 않는다.
    private func field(
        _ keyPath: WritableKeyPath<PrintWatermarkSettings, String>,
        alignment: TextAlignment = .leading
    ) -> some View {
        PrintInspectorTextField(
            prompt: "",
            text: Binding(
                get: { settingsStore.watermark[keyPath: keyPath] },
                set: { value in
                    settingsStore.watermark[keyPath: keyPath] = String(
                        value.prefix(PrintWatermarkSettings.maximumTextLength)
                    )
                }
            )
        )
        .multilineTextAlignment(alignment)
    }

    private func inkPicker(_ selection: Binding<PrintWatermarkInk>) -> some View {
        PrintInspectorSegmentedPicker(
            options: PrintWatermarkInk.allCases,
            label: { $0 == .black ? text(.black) : text(.white) },
            selection: selection
        )
    }

    /// 자리는 넷(아래 가운데·위 왼쪽·위 가운데·위 오른쪽)이라 분할 버튼이 비좁다. 팝업으로 고른다.
    private func placementPicker(_ selection: Binding<PrintWatermarkPlacement>) -> some View {
        PrintInspectorInlineField(text(.placement)) {
            PrintInspectorPopupPicker(
                selection: selection,
                options: PrintWatermarkPlacement.allCases.map { .init($0, title: placementTitle($0)) },
                accessibilityLabel: text(.placement)
            )
        }
    }

    private var percentRange: ClosedRange<Double> {
        PrintWatermarkSettings.bandHeightRange.lowerBound * 100
            ... PrintWatermarkSettings.bandHeightRange.upperBound * 100
    }

    private var bandHeightPercent: Binding<Double> {
        Binding(
            get: { settingsStore.watermark.bandHeightRatio * 100 },
            set: { value in
                let ratio = (value / 100).rounded(toPlaces: 2)
                settingsStore.watermark.bandHeightRatio = min(
                    max(ratio, PrintWatermarkSettings.bandHeightRange.lowerBound),
                    PrintWatermarkSettings.bandHeightRange.upperBound
                )
            }
        )
    }

    private func backgroundTitle(_ background: PrintWatermarkBackground) -> String {
        switch background {
        case .white: text(.white)
        case .black: text(.black)
        case .blur: text(.blur)
        }
    }

    private func placementTitle(_ placement: PrintWatermarkPlacement) -> String {
        switch placement {
        case .bottomCenter: text(.bottomCenter)
        case .topLeading: text(.topLeading)
        case .topCenter: text(.topCenter)
        case .topTrailing: text(.topTrailing)
        }
    }

    private func text(_ phrase: PrintWatermarkLocalizedText) -> String {
        phrase.resolved(language: model.appLanguage)
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let path = url.path(percentEncoded: false)
                guard path.utf8.count <= PrintWatermarkSettings.maximumPathBytes,
                      PrintWatermarkLogoLoader.png(at: path) != nil else {
                    // 열 수 없는 그림이면 고르지 않는다. 하단 상태 점·진단의 오류 기록에 남긴다.
                    model.statusMessage = text(.logoUnreadable)
                    model.errorLog.record(text(.logoUnreadable) + " " + url.lastPathComponent)
                    return
                }
                // 설정·템플릿에는 경로를 담고, 그릴 때마다 그 경로에서 읽는다.
                settingsStore.watermark.logoSourcePath = path
            }
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
