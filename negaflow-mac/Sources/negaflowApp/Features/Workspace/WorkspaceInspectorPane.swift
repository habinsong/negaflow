import SwiftUI

struct WorkspaceInspectorPane: View {
    @EnvironmentObject private var model: AppModel

    let cropMode: (ScanFrame) -> Binding<Bool>
    let brushMode: (ScanFrame) -> Binding<Bool>
    let regionDefectMode: (ScanFrame) -> Binding<Bool>
    let cloneStampMode: (ScanFrame) -> Binding<Bool>
    let basePickerMode: (ScanFrame) -> Binding<Bool>

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 300
            VStack(spacing: 0) {
                inspectorHeader
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let frame = model.actionableFrame {
                            DevelopWorkflowInspector(
                                frame: frame,
                                cropMode: cropMode(frame),
                                brushMode: brushMode(frame),
                                regionDefectMode: regionDefectMode(frame),
                                cloneStampMode: cloneStampMode(frame),
                                basePickerMode: basePickerMode(frame)
                            )
                        } else {
                            ContentUnavailableView(
                                model.text(.noFrame),
                                systemImage: "slider.horizontal.3"
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
                    .padding(.trailing, compact ? 8 : 20)
                    .padding(.vertical, 14)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            Label(model.text(.menuDevelop), systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if let frame = model.actionableFrame {
                Text(DevelopInspectorHeaderSummary.text(
                    for: frame,
                    language: model.appLanguage
                ))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(model.text(.noFrame))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .adaptivePanelSurface(.bar)
    }
}

enum DevelopInspectorHeaderSummary {
    @MainActor
    static func text(for frame: ScanFrame, language: AppLanguage) -> String {
        switch frame.sourceKind {
        case .scannerTIFF:
            return AppLocalization.format(
                AppLocalizedPhrase.targetFilmSummaryFormat,
                language: language,
                frame.params.developTarget.displayName(language: language),
                frame.filmType.developmentProcessName
            )
        case .importedFile:
            return importedMetadata(frame.sourceMetadata?.exif)
        }
    }

    static func importedMetadata(_ exif: SourceEXIFMetadata?) -> String {
        let iso = exif?.isoSpeedRatings.first.map { "ISO \($0)" } ?? "ISO —"
        let shutter = formatShutter(exif?.exposureTimeSeconds)
        let aperture = exif?.fNumber.map { "f/\(formatNumber($0))" } ?? "f/—"
        let focalLength = exif?.focalLengthMM.map { "\(formatNumber($0)) mm" } ?? "— mm"
        return [iso, shutter, aperture, focalLength].joined(separator: " · ")
    }

    private static func formatShutter(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else {
            return ["—", secondsUnit].joined(separator: " ")
        }
        if seconds < 1 {
            let denominator = max(1, Int((1 / seconds).rounded()))
            let reciprocal = 1 / Double(denominator)
            if abs(reciprocal - seconds) / seconds < 0.08 {
                return ["1/\(denominator)", secondsUnit].joined(separator: " ")
            }
        }
        return [formatNumber(seconds), secondsUnit].joined(separator: " ")
    }

    private static let secondsUnit = "s"

    private static func formatNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.005 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
