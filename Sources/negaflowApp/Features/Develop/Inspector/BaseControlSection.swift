import SwiftUI
import AppKit
import Chromabase

struct BaseControlSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame
    let baseMode: Binding<DevelopParameters.BaseMode>
    let manualBaseBinding: (Int) -> Binding<Double>
    /// 필름 Dmin/Dmax 프리셋 ID 바인딩 (preset 모드에서 사용). nil 가능.
    let filmStockDminID: Binding<String?>
    /// 스캔 광원 프로파일 ID (preset 모드에서 실측 base 폴백 시 Dmin 트림). nil 가능.
    let lightSourceProfileID: Binding<String?>
    /// 캔버스 베이스 스포이드 모드 (manual 모드에서 사용).
    let basePickerMode: Binding<Bool>
    let resetManualBase: () -> Void
    let scannerProfileID: Binding<String?>
    let scannerProfiles: [ScannerProfile]

    private let baseModes: [DevelopParameters.BaseMode] = [.auto, .preset, .manual]
    private let basePresetPickerWidth: CGFloat = 276

    var body: some View {
        InspectorCard {
            InspectorCardHeader(
                title: model.text(AppLocalizedPhrase.baseSection),
                systemImage: "circle.lefthalf.filled",
                trailing: baseReadout
            )

            SegmentedPicker(
                options: baseModes,
                label: { $0.displayName(language: model.appLanguage) },
                selection: baseMode
            )
            .disabled(!frame.filmType.requiresInversion)

            if frame.params.baseEstimationMode == .preset {
                basePresetPickerRow(model.text(AppLocalizedPhrase.filmStock)) {
                    SystemPopupPicker(
                        entries: filmStockPickerEntries,
                        selection: filmStockDminID,
                        accessibilityLabel: model.text(AppLocalizedPhrase.filmStock),
                        isEnabled: frame.filmType.requiresInversion
                    )
                }

                basePresetPickerRow(model.text(AppLocalizedPhrase.lightSource)) {
                    SystemPopupPicker(
                        entries: lightSourcePickerEntries,
                        selection: lightSourceProfileID,
                        accessibilityLabel: model.text(AppLocalizedPhrase.lightSource),
                        isEnabled: frame.filmType.requiresInversion
                    )
                }

                basePresetPickerRow(model.text(AppLocalizedPhrase.profile)) {
                    SystemPopupPicker(
                        entries: scannerProfilePickerEntries,
                        selection: scannerProfileID,
                        accessibilityLabel: model.text(AppLocalizedPhrase.profile),
                        isEnabled: !scannerProfiles.isEmpty
                    )
                }
            }

            if frame.params.baseEstimationMode == .manual {
                InspectorActionPill(
                    title: model.text(AppLocalizedPhrase.pickBase),
                    help: model.text(AppLocalizedPhrase.pickBaseHelp),
                    resetTitle: model.text(AppLocalizedPhrase.reset),
                    isActive: basePickerMode.wrappedValue,
                    action: {
                        withAnimation(.snappy(duration: 0.18)) {
                            basePickerMode.wrappedValue.toggle()
                        }
                    },
                    reset: resetManualBase
                )
                InspectorSlider(model.text(AppLocalizedPhrase.baseRed), value: manualBaseBinding(0), range: 0...1, doubleClickResetValue: nil)
                InspectorSlider(model.text(AppLocalizedPhrase.baseGreen), value: manualBaseBinding(1), range: 0...1, doubleClickResetValue: nil)
                InspectorSlider(model.text(AppLocalizedPhrase.baseBlue), value: manualBaseBinding(2), range: 0...1, doubleClickResetValue: nil)
            }
        }
    }

    private var baseReadout: String? {
        guard let base = frame.baseRGB else { return nil }
        return model.text(AppLocalizedPhrase.baseReadoutFormat, base.x, base.y, base.z)
    }

    private var filmStockPickerEntries: [SystemPopupPicker.Entry] {
        var entries: [SystemPopupPicker.Entry] = [
            .option(id: nil, title: model.text(AppLocalizedPhrase.noSelection))
        ]
        for group in FilmStockDminRegistry.groupedByManufacturer {
            entries.append(.section(group.0))
            entries.append(contentsOf: group.1.map { stock in
                .option(
                    id: stock.id,
                    title: "\(stock.displayName)  · ISO \(stock.iso) · \(stock.process)"
                )
            })
        }
        return entries
    }

    private var lightSourcePickerEntries: [SystemPopupPicker.Entry] {
        [.option(id: nil, title: model.text(AppLocalizedPhrase.noSelection))]
            + LightSourceProfileRegistry.all.map {
                .option(id: $0.id, title: $0.displayName)
            }
    }

    private var scannerProfilePickerEntries: [SystemPopupPicker.Entry] {
        [.option(id: nil, title: model.text(AppLocalizedPhrase.none))]
            + scannerProfiles.map {
                .option(
                    id: $0.id,
                    title: [
                        $0.displayName,
                        $0.validationStatus.displayName(language: model.appLanguage)
                    ].joined(separator: " · ")
                )
            }
    }

    private func basePresetPickerRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(width: 86, alignment: .leading)
            control()
                .frame(width: basePresetPickerWidth)
                .frame(minHeight: 24)
        }
        .frame(maxWidth: .infinity, minHeight: 26)
    }
}

/// SwiftUI의 menu Picker는 고정 프레임 안에서도 선택 문자열의 고유 베젤 폭을 유지한다.
/// Apple 표준 NSPopUpButton을 직접 배치해 세 컨트롤의 실제 베젤 폭을 동일하게 만든다.
private struct SystemPopupPicker: NSViewRepresentable {
    struct Entry: Equatable {
        let id: String?
        let title: String
        let isSection: Bool

        static func option(id: String?, title: String) -> Entry {
            Entry(id: id, title: title, isSection: false)
        }

        static func section(_ title: String) -> Entry {
            Entry(id: nil, title: title, isSection: true)
        }
    }

    let entries: [Entry]
    @Binding var selection: String?
    let accessibilityLabel: String
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.bezelStyle = .automatic
        button.controlSize = .regular
        button.alignment = .center
        button.lineBreakMode = .byTruncatingMiddle
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.entries != entries {
            context.coordinator.entries = entries
            rebuildMenu(of: button)
        }
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(accessibilityLabel)
        selectCurrentItem(in: button)
    }

    private func rebuildMenu(of button: NSPopUpButton) {
        let menu = NSMenu()
        for entry in entries {
            if entry.isSection {
                menu.addItem(.sectionHeader(title: entry.title))
            } else {
                let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
                item.representedObject = entry.id ?? NSNull()
                menu.addItem(item)
            }
        }
        button.menu = menu
    }

    private func selectCurrentItem(in button: NSPopUpButton) {
        guard let items = button.menu?.items else { return }
        let index = items.firstIndex { item in
            if let id = selection {
                return item.representedObject as? String == id
            }
            return item.representedObject is NSNull
        }
        if let index {
            button.selectItem(at: index)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SystemPopupPicker
        var entries: [Entry] = []

        init(parent: SystemPopupPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let representedObject = sender.selectedItem?.representedObject else { return }
            if representedObject is NSNull {
                parent.selection = nil
            } else if let id = representedObject as? String {
                parent.selection = id
            }
        }
    }
}

private extension DevelopParameters.BaseMode {
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .auto:
            return AppLocalization.text(AppLocalizedPhrase.baseModeAuto, language: language)
        case .preset:
            return AppLocalization.text(AppLocalizedPhrase.baseModeFilm, language: language)
        case .manual:
            return AppLocalization.text(AppLocalizedPhrase.baseModeManual, language: language)
        }
    }
}
