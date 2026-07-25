import SwiftUI
import ScannerKit

struct ScannerTruthSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            if let cap = model.capabilities {
                capabilityRow(model.text(AppLocalizedPhrase.resolution), value: resolutionSummary(cap))
                capabilityRow(model.text(AppLocalizedPhrase.bitDepth), value: bitDepthSummary(cap))
                capabilityRow(
                    model.text(AppLocalizedPhrase.transparency),
                    value: transparencySummary(cap),
                    supported: cap.supportsTransparency,
                    reason: cap.disabledReason(for: "transparency")
                )
                brightnessControl(cap)
                contrastControl(cap)
                capabilityRow(
                    model.text(AppLocalizedPhrase.infrared),
                    value: cap.supportsInfrared
                        ? model.text(AppLocalizedPhrase.capabilityAvailable)
                        : model.text(AppLocalizedPhrase.capabilityUnavailable),
                    supported: cap.supportsInfrared,
                    reason: cap.disabledReason(for: "infrared")
                )
            } else {
                Text(model.text(AppLocalizedPhrase.capabilityWaiting))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.scannerTruth), systemImage: "checkmark.shield")
        }

        if !model.installedScannerPlugins.isEmpty {
            Section {
                ScannerPluginTrustRows(plugins: model.installedScannerPlugins)
            } header: {
                sectionHeader(
                    model.text(AppLocalizedPhrase.scannerPluginApprovalTitle),
                    systemImage: "puzzlepiece.extension"
                )
            }
        }
    }

    @ViewBuilder
    private func brightnessControl(_ cap: ScannerCapabilities) -> some View {
        if let range = cap.brightnessRange {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(model.text(AppLocalizedPhrase.brightness)) {
                    Text(formatNumber(model.scannerBrightness))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: rangeBinding(range, get: { model.scannerBrightness }, set: { model.scannerBrightness = $0 }),
                    in: range.minimum...range.maximum,
                    step: max(range.step ?? 1, 0.0001)
                )
            }
        } else {
            capabilityRow(
                model.text(AppLocalizedPhrase.brightness),
                value: model.text(AppLocalizedPhrase.capabilityUnavailable),
                supported: false,
                reason: cap.disabledReason(for: "brightness")
            )
        }
    }

    @ViewBuilder
    private func contrastControl(_ cap: ScannerCapabilities) -> some View {
        if let range = cap.contrastRange {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(model.text(AppLocalizedPhrase.contrast)) {
                    Text(formatNumber(model.scannerContrast))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: rangeBinding(range, get: { model.scannerContrast }, set: { model.scannerContrast = $0 }),
                    in: range.minimum...range.maximum,
                    step: max(range.step ?? 1, 0.0001)
                )
            }
        } else {
            capabilityRow(
                model.text(AppLocalizedPhrase.contrast),
                value: model.text(AppLocalizedPhrase.capabilityUnavailable),
                supported: false,
                reason: cap.disabledReason(for: "contrast")
            )
        }
    }

    @ViewBuilder
    private func capabilityRow(_ title: String, value: String, supported: Bool = true, reason: String? = nil) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundStyle(supported ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                if !supported, let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func resolutionSummary(_ cap: ScannerCapabilities) -> String {
        let values = cap.supportedResolutions
            .filter { $0.dpi > 0 }
            .map { "\($0.dpi)" }
        return values.isEmpty ? model.text(AppLocalizedPhrase.capabilityUnavailable) : "\(values.joined(separator: ", ")) dpi"
    }

    private func bitDepthSummary(_ cap: ScannerCapabilities) -> String {
        let values = cap.supportedBitDepths
            .map { "\($0.rawValue)-bit/ch" }
        return values.isEmpty ? model.text(AppLocalizedPhrase.capabilityUnavailable) : values.joined(separator: ", ")
    }

    private func transparencySummary(_ cap: ScannerCapabilities) -> String {
        let modes = cap.transparencyModes ?? []
        if !modes.isEmpty { return modes.joined(separator: ", ") }
        return cap.supportsTransparency
            ? model.text(AppLocalizedPhrase.capabilityAvailable)
            : model.text(AppLocalizedPhrase.capabilityUnavailable)
    }

    private func formatNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    private func rangeBinding(
        _ range: ScannerOptionRange,
        get: @escaping () -> Double,
        set: @escaping (Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { range.clamped(get()) },
            set: { set(range.clamped($0)) }
        )
    }
}
