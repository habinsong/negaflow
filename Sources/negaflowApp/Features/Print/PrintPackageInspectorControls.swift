import Chromabase
import SwiftUI

struct PrintPackageInspectorControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore

    var body: some View {
        Group {
            switch settingsStore.layoutMode {
            case .singleImage:
                EmptyView()
            case .contactSheet:
                contactSheetControls
            case .picturePackage:
                picturePackageControls
            case .customPackage:
                customPackageControls
            }
            commonControls
        }
    }

    private var contactSheetControls: some View {
        Group {
            HStack(spacing: 10) {
                Stepper(
                    model.text(.printRows),
                    value: packageBinding(\.contactRows),
                    in: 1...12
                )
                Text(verbatim: "\(settingsStore.packageSettings.contactRows)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 22, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Stepper(
                    model.text(.printColumns),
                    value: packageBinding(\.contactColumns),
                    in: 1...12
                )
                Text(verbatim: "\(settingsStore.packageSettings.contactColumns)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 22, alignment: .trailing)
            }
            spacingControl(
                title: model.text(.printHorizontalSpacing),
                value: packageBinding(\.horizontalSpacingMM)
            )
            spacingControl(
                title: model.text(.printVerticalSpacing),
                value: packageBinding(\.verticalSpacingMM)
            )
            Toggle(
                model.text(.printRepeatOnePhoto),
                isOn: packageBinding(\.repeatOnePhotoPerPage)
            )
        }
    }

    private var picturePackageControls: some View {
        Group {
            Picker(
                model.text(.printPictureTemplate),
                selection: packageBinding(\.pictureTemplate)
            ) {
                Text(model.text(.printOneLargeTwoSmall))
                    .tag(PrintPicturePackageTemplate.oneLargeTwoSmall)
                Text(model.text(.printTwoUp))
                    .tag(PrintPicturePackageTemplate.twoUp)
                Text(model.text(.printFourUp))
                    .tag(PrintPicturePackageTemplate.fourUp)
            }
            spacingControl(
                title: model.text(.printHorizontalSpacing),
                value: packageBinding(\.horizontalSpacingMM)
            )
            spacingControl(
                title: model.text(.printVerticalSpacing),
                value: packageBinding(\.verticalSpacingMM)
            )
        }
    }

    private var customPackageControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(settingsStore.packageSettings.customItems.indices), id: \.self) { index in
                DisclosureGroup("\(model.text(.printCell)) \(index + 1)") {
                    customItemControls(index: index)
                        .padding(.top, 6)
                }
            }

            Button {
                addCustomItem()
            } label: {
                Label(model.text(.printAddCell), systemImage: "plus")
            }
            .buttonStyle(.plain)
            .disabled(
                settingsStore.packageSettings.customItems.count
                    >= PrintPackageSettings.maximumCustomItemCount
            )
        }
    }

    private func customItemControls(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                model.text(.printSourcePhoto),
                selection: customSourceBinding(index: index)
            ) {
                if model.actionableSelectedFrames.isEmpty {
                    Text(model.text(.noFrame)).tag(0)
                } else {
                    ForEach(Array(model.actionableSelectedFrames.enumerated()), id: \.element.id) {
                        sourceIndex, frame in
                        Text(frame.compactDisplayName(language: model.appLanguage))
                            .tag(sourceIndex)
                    }
                }
            }
            .disabled(model.actionableSelectedFrames.isEmpty)
            HStack(spacing: 8) {
                Stepper(
                    model.text(.printPage),
                    value: customPageBinding(index: index),
                    in: 0...(PrintPackageSettings.maximumPageCount - 1)
                )
                Text(verbatim: "\((customItem(index: index)?.pageIndex ?? 0) + 1)")
                    .font(.caption.monospacedDigit())
                    .frame(width: 22, alignment: .trailing)
            }
            Picker(
                model.text(.printImageFit),
                selection: customContentModeBinding(index: index)
            ) {
                Text(model.text(.printFit)).tag(PrintPackageContentMode.fit)
                Text(model.text(.printFill)).tag(PrintPackageContentMode.fill)
            }
            Toggle(
                model.text(.printRotateToFit),
                isOn: customBoolBinding(index: index, keyPath: \.rotateToFit)
            )
            normalizedControl(
                title: model.text(.printPositionX),
                value: customRectBinding(index: index, component: .x)
            )
            normalizedControl(
                title: model.text(.printPositionY),
                value: customRectBinding(index: index, component: .y)
            )
            normalizedControl(
                title: model.text(.printWidth),
                value: customRectBinding(index: index, component: .width)
            )
            normalizedControl(
                title: model.text(.printHeight),
                value: customRectBinding(index: index, component: .height)
            )
            HStack(spacing: 12) {
                Button {
                    moveCustomItem(index: index, forward: false)
                } label: {
                    Image(systemName: "square.2.layers.3d.bottom.filled")
                }
                .buttonStyle(.plain)
                .help(model.accessibilityText(.moveDown))
                .accessibilityLabel(model.accessibilityText(.moveDown))
                Button {
                    moveCustomItem(index: index, forward: true)
                } label: {
                    Image(systemName: "square.2.layers.3d.top.filled")
                }
                .buttonStyle(.plain)
                .help(model.accessibilityText(.moveUp))
                .accessibilityLabel(model.accessibilityText(.moveUp))
                Button {
                    duplicateCustomItem(at: index)
                } label: {
                    Label(model.text(.printDuplicateCell), systemImage: "plus.square.on.square")
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    deleteCustomItem(at: index)
                } label: {
                    Label(model.text(.printDeleteCell), systemImage: "trash")
                }
                .buttonStyle(.plain)
                .disabled(settingsStore.packageSettings.customItems.count <= 1)
            }
        }
    }

    private var commonControls: some View {
        Group {
            if settingsStore.layoutMode != .customPackage {
                Picker(
                    model.text(.printImageFit),
                    selection: packageBinding(\.contentMode)
                ) {
                    Text(model.text(.printFit)).tag(PrintPackageContentMode.fit)
                    Text(model.text(.printFill)).tag(PrintPackageContentMode.fill)
                }
                Toggle(
                    model.text(.printRotateToFit),
                    isOn: packageBinding(\.rotateToFit)
                )
            }

            Picker(model.text(.printCaption), selection: packageBinding(\.captionMode)) {
                Text(model.text(.noLook)).tag(PrintPackageCaptionMode.none)
                Text(model.text(.printCaptionFileName)).tag(PrintPackageCaptionMode.fileName)
                Text(model.text(.printCaptionFrameNumber)).tag(PrintPackageCaptionMode.frameNumber)
                Text(model.text(.printCaptionRating)).tag(PrintPackageCaptionMode.rating)
            }
            Toggle(model.text(.printCropMarks), isOn: packageBinding(\.showsCropMarks))
        }
    }

    private func spacingControl(title: String, value: Binding<Double>) -> some View {
        let displayValue = String(format: "%.1f mm", value.wrappedValue)
        return HStack(spacing: 10) {
            Text(title)
            Slider(value: value, in: 0...25, step: 0.5)
                .accessibilityLabel(title)
                .accessibilityValue(Text(verbatim: displayValue))
            Text(verbatim: displayValue)
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func normalizedControl(title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
            Slider(value: value, in: 0...1, step: 0.01)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int((value.wrappedValue * 100).rounded()))%")
            Text("\(Int((value.wrappedValue * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func packageBinding<Value>(
        _ keyPath: WritableKeyPath<PrintPackageSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settingsStore.packageSettings[keyPath: keyPath] },
            set: { value in
                var package = settingsStore.packageSettings
                package[keyPath: keyPath] = value
                settingsStore.packageSettings = package
            }
        )
    }

    private func customItem(index: Int) -> PrintCustomPackageItem? {
        guard settingsStore.packageSettings.customItems.indices.contains(index) else { return nil }
        return settingsStore.packageSettings.customItems[index]
    }

    private func updateCustomItem(index: Int, _ update: (inout PrintCustomPackageItem) -> Void) {
        var package = settingsStore.packageSettings
        guard package.customItems.indices.contains(index) else { return }
        update(&package.customItems[index])
        settingsStore.packageSettings = package
    }

    private func customSourceBinding(index: Int) -> Binding<Int> {
        Binding(
            get: {
                min(
                    customItem(index: index)?.sourceIndex ?? 0,
                    max(0, model.actionableSelectedFrames.count - 1)
                )
            },
            set: { value in
                updateCustomItem(index: index) { $0.sourceIndex = value }
            }
        )
    }

    private func customPageBinding(index: Int) -> Binding<Int> {
        Binding(
            get: { customItem(index: index)?.pageIndex ?? 0 },
            set: { value in
                var package = settingsStore.packageSettings
                guard package.customItems.indices.contains(index) else { return }
                package.customItems[index].pageIndex = value
                normalizeCustomPageIndices(&package)
                settingsStore.packageSettings = package
            }
        )
    }

    private func customBoolBinding(
        index: Int,
        keyPath: WritableKeyPath<PrintCustomPackageItem, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { customItem(index: index)?[keyPath: keyPath] ?? false },
            set: { value in
                updateCustomItem(index: index) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func customContentModeBinding(index: Int) -> Binding<PrintPackageContentMode> {
        Binding(
            get: { customItem(index: index)?.contentMode ?? .fit },
            set: { value in
                updateCustomItem(index: index) { $0.contentMode = value }
            }
        )
    }

    private enum RectComponent { case x, y, width, height }

    private func customRectBinding(index: Int, component: RectComponent) -> Binding<Double> {
        Binding(
            get: {
                guard let rect = customItem(index: index)?.normalizedRect else { return 0 }
                switch component {
                case .x: return Double(rect.minX)
                case .y: return Double(rect.minY)
                case .width: return Double(rect.width)
                case .height: return Double(rect.height)
                }
            },
            set: { rawValue in
                updateCustomItem(index: index) { item in
                    var rect = item.normalizedRect
                    let value = CGFloat(min(max(rawValue, 0), 1))
                    switch component {
                    case .x:
                        rect.origin.x = min(value, 1 - rect.width)
                    case .y:
                        rect.origin.y = min(value, 1 - rect.height)
                    case .width:
                        rect.size.width = max(0.01, min(value, 1 - rect.minX))
                    case .height:
                        rect.size.height = max(0.01, min(value, 1 - rect.minY))
                    }
                    item.normalizedRect = rect
                }
            }
        )
    }

    private func addCustomItem() {
        var package = settingsStore.packageSettings
        let count = package.customItems.count
        let offset = CGFloat((count % 5)) * 0.05
        package.customItems.append(PrintCustomPackageItem(
            sourceIndex: min(count, max(0, model.actionableSelectedFrames.count - 1)),
            normalizedRect: CGRect(
                x: min(0.55, 0.08 + offset),
                y: min(0.55, 0.08 + offset),
                width: 0.4,
                height: 0.4
            ),
            zIndex: (package.customItems.map(\.zIndex).max() ?? -1) + 1
        ))
        settingsStore.packageSettings = package
    }

    private func duplicateCustomItem(at index: Int) {
        var package = settingsStore.packageSettings
        guard package.customItems.indices.contains(index),
              package.customItems.count < PrintPackageSettings.maximumCustomItemCount else { return }
        var copy = package.customItems[index]
        copy.zIndex = (package.customItems.map(\.zIndex).max() ?? -1) + 1
        copy.normalizedRect.origin.x = min(1 - copy.normalizedRect.width, copy.normalizedRect.minX + 0.03)
        copy.normalizedRect.origin.y = min(1 - copy.normalizedRect.height, copy.normalizedRect.minY + 0.03)
        package.customItems.append(copy)
        settingsStore.packageSettings = package
    }

    private func deleteCustomItem(at index: Int) {
        var package = settingsStore.packageSettings
        guard package.customItems.count > 1, package.customItems.indices.contains(index) else { return }
        package.customItems.remove(at: index)
        normalizeCustomPageIndices(&package)
        settingsStore.packageSettings = package
    }

    private func moveCustomItem(index: Int, forward: Bool) {
        var package = settingsStore.packageSettings
        guard package.customItems.indices.contains(index) else { return }
        let pageIndex = package.customItems[index].pageIndex
        var ordered = package.customItems.indices
            .filter { package.customItems[$0].pageIndex == pageIndex }
            .sorted { lhs, rhs in
                let left = package.customItems[lhs]
                let right = package.customItems[rhs]
                return left.zIndex == right.zIndex ? lhs < rhs : left.zIndex < right.zIndex
            }
        guard let position = ordered.firstIndex(of: index) else { return }
        let target = forward ? position + 1 : position - 1
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(position, target)
        for (zIndex, itemIndex) in ordered.enumerated() {
            package.customItems[itemIndex].zIndex = zIndex
        }
        settingsStore.packageSettings = package
    }

    private func normalizeCustomPageIndices(_ package: inout PrintPackageSettings) {
        let orderedPages = Array(Set(package.customItems.map(\.pageIndex))).sorted()
        let normalized = Dictionary(uniqueKeysWithValues: orderedPages.enumerated().map {
            ($0.element, $0.offset)
        })
        for index in package.customItems.indices {
            package.customItems[index].pageIndex = normalized[package.customItems[index].pageIndex] ?? 0
        }
    }
}
