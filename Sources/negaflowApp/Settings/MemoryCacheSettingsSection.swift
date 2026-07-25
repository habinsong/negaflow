import SwiftUI

/// 설정 · 일반 — 상주 프레임 한도.
///
/// 자동은 설치 메모리에서 예산을 잡고, 수동은 슬라이더로 직접 정한다. 어떤 모드든 지금 설정이
/// 최악의 경우 얼마나 상주하는지 함께 보여 준다. 순정 Form 컨트롤만 쓴다 — 별도 배경/그림자 없음.
struct MemoryCacheSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store: FrameCacheResidencyStore

    init(store: FrameCacheResidencyStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        Section {
            Picker(model.text(AppLocalizedPhrase.settingsMemoryCacheSection), selection: $store.mode) {
                Text(model.text(AppLocalizedPhrase.settingsMemoryCacheModeAutomatic))
                    .tag(FrameCacheResidencyStore.Mode.automatic)
                Text(model.text(AppLocalizedPhrase.settingsMemoryCacheModeManual))
                    .tag(FrameCacheResidencyStore.Mode.manual)
            }
            .pickerStyle(.segmented)

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
            } else {
                LabeledContent(model.text(AppLocalizedPhrase.settingsMemoryCacheCleanedRawLabel)) {
                    Text(frameCount(store.automaticLimits.cleanedRaw))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                LabeledContent(model.text(AppLocalizedPhrase.settingsMemoryCacheDevelopedLabel)) {
                    Text(frameCount(store.automaticLimits.developed))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text(model.text(AppLocalizedPhrase.settingsMemoryCacheSection))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(installedMemoryText)
                Text(estimateText)
                Text(helpText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countSlider(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { Double(value.wrappedValue) },
                        set: { value.wrappedValue = Int($0.rounded()) }
                    ),
                    in: Double(range.lowerBound)...Double(max(range.lowerBound + 1, range.upperBound)),
                    step: 1
                )
                Text(frameCount(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
        }
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
