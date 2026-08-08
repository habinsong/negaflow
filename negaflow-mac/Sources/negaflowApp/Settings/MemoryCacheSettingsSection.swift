import SwiftUI

struct MemoryCacheSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store: FrameCacheResidencyStore

    init(store: FrameCacheResidencyStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        AppSettingsSection(
            title: model.text(AppLocalizedPhrase.settingsMemoryCacheSection)
        ) {
            AppSettingsRow(model.text(AppLocalizedPhrase.settingsMemoryCacheSection)) {
                Picker(String(), selection: $store.mode) {
                    Text(model.text(AppLocalizedPhrase.settingsMemoryCacheModeAutomatic))
                        .tag(FrameCacheResidencyStore.Mode.automatic)
                    Text(model.text(AppLocalizedPhrase.settingsMemoryCacheModeManual))
                        .tag(FrameCacheResidencyStore.Mode.manual)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if store.mode == .manual {
                countSlider(
                    title: model.text(AppLocalizedPhrase.settingsMemoryCacheCleanedRawLabel),
                    value: $store.manualCleanedRaw,
                    range: FrameCacheBudget.minimumCleanedRaw...store.manualMaximumLimits.cleanedRaw
                )
                countSlider(
                    title: model.text(AppLocalizedPhrase.settingsMemoryCacheDevelopedLabel),
                    value: $store.manualDeveloped,
                    range: FrameCacheBudget.minimumDeveloped...store.manualMaximumLimits.developed
                )
                Button(model.text(AppLocalizedPhrase.settingsMemoryCacheResetToAutomatic)) {
                    store.resetManualToAutomatic()
                }
                .buttonStyle(.bordered)
            } else {
                AppSettingsValueRow(
                    label: model.text(AppLocalizedPhrase.settingsMemoryCacheCleanedRawLabel),
                    value: frameCount(store.automaticLimits.cleanedRaw)
                )
                AppSettingsValueRow(
                    label: model.text(AppLocalizedPhrase.settingsMemoryCacheDevelopedLabel),
                    value: frameCount(store.automaticLimits.developed)
                )
            }

            AppSettingsHelpText(
                [installedMemoryText, estimateText, helpText].joined(separator: "\n")
            )
        }
    }

    private func countSlider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        let lowerBound = Double(range.lowerBound)
        let upperBound = Double(max(range.lowerBound + 1, range.upperBound))
        return AppSettingsSliderRow(
            label: title,
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ),
            range: lowerBound...upperBound,
            step: 1,
            valueText: frameCount(value.wrappedValue)
        )
    }

    private func frameCount(_ count: Int) -> String {
        model.text(AppLocalizedPhrase.settingsMemoryCacheFramesFormat, count)
    }

    private var installedMemoryText: String {
        model.text(
            AppLocalizedPhrase.settingsMemoryCacheInstalledMemoryFormat,
            Self.byteFormatter.string(fromByteCount: Int64(store.physicalMemoryBytes))
        )
    }

    private var estimateText: String {
        let megabytes = store.estimatedResidentMegabytes
        let bytes = Int64(megabytes * 1_024 * 1_024)
        return model.text(
            AppLocalizedPhrase.settingsMemoryCacheEstimateFormat,
            Self.byteFormatter.string(fromByteCount: bytes),
            Int((store.estimatedResidentFraction * 100).rounded())
        )
    }

    private var helpText: String {
        store.mode == .automatic
            ? model.text(AppLocalizedPhrase.settingsMemoryCacheAutomaticHelp)
            : model.text(AppLocalizedPhrase.settingsMemoryCacheManualHelp)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()
}
