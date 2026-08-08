import ScannerKit
import SwiftUI

struct ScannerTruthSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppSettingsSection(
            title: model.text(AppLocalizedPhrase.scannerTruth)
        ) {
            if let capabilities = model.capabilities {
                capabilityRow(
                    model.text(AppLocalizedPhrase.resolution),
                    value: resolutionSummary(capabilities)
                )
                capabilityRow(
                    model.text(AppLocalizedPhrase.bitDepth),
                    value: bitDepthSummary(capabilities)
                )
                capabilityRow(
                    model.text(AppLocalizedPhrase.transparency),
                    value: transparencySummary(capabilities),
                    supported: capabilities.supportsTransparency,
                    reason: capabilities.disabledReason(for: "transparency")
                )
                brightnessControl(capabilities)
                contrastControl(capabilities)
                capabilityRow(
                    model.text(AppLocalizedPhrase.infrared),
                    value: capabilities.supportsInfrared
                        ? model.text(AppLocalizedPhrase.capabilityAvailable)
                        : model.text(AppLocalizedPhrase.capabilityUnavailable),
                    supported: capabilities.supportsInfrared,
                    reason: capabilities.disabledReason(for: "infrared")
                )
            } else {
                AppSettingsHelpText(model.text(AppLocalizedPhrase.capabilityWaiting))
            }
        }

        if !model.installedScannerPlugins.isEmpty {
            AppSettingsSection(
                title: model.text(AppLocalizedPhrase.scannerPluginApprovalTitle)
            ) {
                ScannerPluginTrustRows(plugins: model.installedScannerPlugins)
            }
        }
    }

    @ViewBuilder
    private func brightnessControl(_ capabilities: ScannerCapabilities) -> some View {
        if let range = capabilities.brightnessRange {
            sliderControl(
                model.text(AppLocalizedPhrase.brightness),
                value: rangeBinding(
                    range,
                    get: { model.scannerBrightness },
                    set: { model.scannerBrightness = $0 }
                ),
                range: range
            )
        } else {
            capabilityRow(
                model.text(AppLocalizedPhrase.brightness),
                value: model.text(AppLocalizedPhrase.capabilityUnavailable),
                supported: false,
                reason: capabilities.disabledReason(for: "brightness")
            )
        }
    }

    @ViewBuilder
    private func contrastControl(_ capabilities: ScannerCapabilities) -> some View {
        if let range = capabilities.contrastRange {
            sliderControl(
                model.text(AppLocalizedPhrase.contrast),
                value: rangeBinding(
                    range,
                    get: { model.scannerContrast },
                    set: { model.scannerContrast = $0 }
                ),
                range: range
            )
        } else {
            capabilityRow(
                model.text(AppLocalizedPhrase.contrast),
                value: model.text(AppLocalizedPhrase.capabilityUnavailable),
                supported: false,
                reason: capabilities.disabledReason(for: "contrast")
            )
        }
    }

    private func sliderControl(
        _ label: String,
        value: Binding<Double>,
        range: ScannerOptionRange
    ) -> some View {
        AppSettingsSliderRow(
            label: label,
            value: value,
            range: range.minimum...max(range.minimum + 0.0001, range.maximum),
            step: max(range.step ?? 1, 0.0001),
            valueText: formatNumber(value.wrappedValue)
        )
    }

    private func capabilityRow(
        _ title: String,
        value: String,
        supported: Bool = true,
        reason: String? = nil
    ) -> some View {
        AppSettingsValueRow(
            label: title,
            value: value,
            supported: supported,
            reason: reason
        )
    }

    private func resolutionSummary(_ capabilities: ScannerCapabilities) -> String {
        let values = capabilities.supportedResolutions
            .filter { $0.dpi > 0 }
            .map { "\($0.dpi)" }
        return values.isEmpty
            ? model.text(AppLocalizedPhrase.capabilityUnavailable)
            : "\(values.joined(separator: ", ")) dpi"
    }

    private func bitDepthSummary(_ capabilities: ScannerCapabilities) -> String {
        let values = capabilities.supportedBitDepths
            .map { "\($0.rawValue)-bit/ch" }
        return values.isEmpty
            ? model.text(AppLocalizedPhrase.capabilityUnavailable)
            : values.joined(separator: ", ")
    }

    private func transparencySummary(_ capabilities: ScannerCapabilities) -> String {
        let modes = capabilities.transparencyModes ?? []
        if !modes.isEmpty { return modes.joined(separator: ", ") }
        return capabilities.supportsTransparency
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
