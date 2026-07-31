import AppKit
import Chromabase
import SwiftUI

enum PrintPackageInspectorControlScope {
    case layout
    case content
}

struct PrintPackageInspectorControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    let scope: PrintPackageInspectorControlScope
    /// 셀/캡션은 한 번에 하나만 펼친다 — 전부 펼치면 패널이 끝없이 길어진다.
    @State private var expandedItemIndex: Int?
    @State private var expandedCaptionIndex: Int?

    private static let captionFontNames: [String] = {
        let names = Set(NSFontManager.shared.availableFontFamilies + ["Helvetica"])
        return names.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }()

    var body: some View {
        switch scope {
        case .layout:
            Group {
                switch settingsStore.layoutMode {
                case .singleImage, .cyanotype, .glassPlate, .gelatin:
                    EmptyView()
                case .contactSheet:
                    contactSheetControls
                case .picturePackage:
                    picturePackageControls
                case .customPackage:
                    customPackageControls
                }
            }
        case .content:
            commonControls
        }
    }

    private var contactSheetControls: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            PrintInspectorPairedSteppers(
                leadingTitle: model.text(.printRows),
                leadingValue: packageBinding(\.contactRows),
                trailingTitle: model.text(.printColumns),
                trailingValue: packageBinding(\.contactColumns),
                range: 1...12
            )

            Divider()
                .opacity(0.4)

            spacingControl(
                title: model.text(.printHorizontalSpacing),
                value: packageBinding(\.horizontalSpacingMM)
            )
            spacingControl(
                title: model.text(.printVerticalSpacing),
                value: packageBinding(\.verticalSpacingMM)
            )

            Divider()
                .opacity(0.4)

            PrintInspectorBooleanSegmentedField(
                label: model.text(.printRepeatOnePhoto),
                isOn: packageBinding(\.repeatOnePhotoPerPage)
            )

            normalizeOrientationField
        }
    }

    /// 시트에 올라간 사진을 스캔 기본 방향으로 통일해 배치한다. 프레임 자체의 방향은 그대로다.
    private var normalizeOrientationField: some View {
        PrintInspectorBooleanSegmentedField(
            label: model.text(.printNormalizeOrientation),
            isOn: packageBinding(\.normalizesSourceOrientation)
        )
    }

    private var picturePackageControls: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            PrintInspectorInlineField(model.text(.printPictureTemplate)) {
                PrintInspectorPopupPicker(
                    selection: packageBinding(\.pictureTemplate),
                    options: PrintPicturePackageTemplate.allCases.map {
                        .init($0, title: pictureTemplateTitle($0))
                    },
                    accessibilityLabel: model.text(.printPictureTemplate)
                )
            }

            Divider()
                .opacity(0.4)

            spacingControl(
                title: model.text(.printHorizontalSpacing),
                value: packageBinding(\.horizontalSpacingMM)
            )
            spacingControl(
                title: model.text(.printVerticalSpacing),
                value: packageBinding(\.verticalSpacingMM)
            )

            Divider()
                .opacity(0.4)

            normalizeOrientationField
        }
    }

    private var customPackageControls: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            normalizeOrientationField

            Divider()
                .opacity(0.4)

            ForEach(Array(settingsStore.packageSettings.customItems.indices), id: \.self) { index in
                if index > 0 { Divider() }
                PrintInspectorDisclosure(
                    isExpanded: expansionBinding(for: index, in: $expandedItemIndex),
                    accessibilityLabel: "\(model.text(.printCell)) \(index + 1)"
                ) {
                    HStack(spacing: 8) {
                        Text("\(model.text(.printCell)) \(index + 1)")
                            .font(.callout.weight(.medium))
                        Spacer(minLength: 8)
                        Text(
                            "\(model.text(.printPage)) "
                                + "\((customItem(index: index)?.pageIndex ?? 0) + 1)"
                        )
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                } content: {
                    customItemControls(index: index)
                }
            }

            Button {
                addCustomItem()
            } label: {
                Label(model.text(.printAddCell), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrintInspectorTransientButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.leading, 1)
            .disabled(
                settingsStore.packageSettings.customItems.count
                    >= PrintPackageSettings.maximumCustomItemCount
            )
        }
    }

    private func customItemControls(index: Int) -> some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            PrintInspectorStackedField(model.text(.printSourcePhoto)) {
                PrintInspectorPopupPicker(
                    selection: customSourceBinding(index: index),
                    options: customSourceOptions,
                    accessibilityLabel: model.text(.printSourcePhoto),
                    isEnabled: !model.actionableSelectedFrames.isEmpty
                )
            }

            PrintInspectorStepperRow(
                label: model.text(.printPage),
                value: customPageBinding(index: index),
                range: 0...(PrintPackageSettings.maximumPageCount - 1),
                displayedValue: (customItem(index: index)?.pageIndex ?? 0) + 1
            )

            Divider()
                .opacity(0.4)

            PrintInspectorStackedField(model.text(.printImageFit)) {
                PrintInspectorSegmentedPicker(
                    options: PrintPackageContentMode.allCases,
                    label: contentModeTitle,
                    selection: customContentModeBinding(index: index)
                )
            }

            PrintInspectorBooleanSegmentedField(
                label: model.text(.printRotateToFit),
                isOn: customBoolBinding(index: index, keyPath: \.rotateToFit)
            )

            Divider()
                .opacity(0.4)

            layoutNormalizedControl(
                title: model.text(.printPositionX),
                value: customRectBinding(index: index, component: .x)
            )
            layoutNormalizedControl(
                title: model.text(.printPositionY),
                value: customRectBinding(index: index, component: .y)
            )
            layoutNormalizedControl(
                title: model.text(.printWidth),
                value: customRectBinding(index: index, component: .width)
            )
            layoutNormalizedControl(
                title: model.text(.printHeight),
                value: customRectBinding(index: index, component: .height)
            )

            HStack(spacing: 6) {
                PrintInspectorIconButton(
                    systemImage: "square.2.layers.3d.bottom.filled",
                    accessibilityLabel: model.accessibilityText(.moveDown)
                ) {
                    moveCustomItem(index: index, forward: false)
                }
                PrintInspectorIconButton(
                    systemImage: "square.2.layers.3d.top.filled",
                    accessibilityLabel: model.accessibilityText(.moveUp)
                ) {
                    moveCustomItem(index: index, forward: true)
                }
                PrintInspectorIconButton(
                    systemImage: "plus.square.on.square",
                    accessibilityLabel: model.text(.printDuplicateCell)
                ) {
                    duplicateCustomItem(at: index)
                }
                PrintInspectorIconButton(
                    systemImage: "trash",
                    accessibilityLabel: model.text(.printDeleteCell),
                    role: .destructive,
                    isDisabled: settingsStore.packageSettings.customItems.count <= 1
                ) {
                    deleteCustomItem(at: index)
                }
            }
        }
    }

    private var commonControls: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            if settingsStore.layoutMode != .customPackage {
                PrintInspectorStackedField(model.text(.printImageFit)) {
                    PrintInspectorSegmentedPicker(
                        options: PrintPackageContentMode.allCases,
                        label: contentModeTitle,
                        selection: packageBinding(\.contentMode)
                    )
                }

                PrintInspectorBooleanSegmentedField(
                    label: model.text(.printRotateToFit),
                    isOn: packageBinding(\.rotateToFit)
                )

                Divider()
                    .opacity(0.4)
            }

            PrintInspectorInlineField(model.text(.printCaption)) {
                PrintInspectorPopupPicker(
                    selection: packageBinding(\.captionMode),
                    options: PrintPackageCaptionMode.allCases.map {
                        .init($0, title: captionModeTitle($0))
                    },
                    accessibilityLabel: model.text(.printCaption)
                )
            }

            if settingsStore.packageSettings.captionMode != .none {
                Divider()
                    .opacity(0.4)

                PrintInspectorInlineField(model.text(.printCaptionFont)) {
                    PrintInspectorPopupPicker(
                        selection: packageBinding(\.captionFontName),
                        options: Self.captionFontNames.map {
                            .init($0, title: $0)
                        },
                        accessibilityLabel: model.text(.printCaptionFont)
                    )
                }

                if settingsStore.packageSettings.captionMode == .customText {
                    Divider()
                        .opacity(0.4)
                    customCaptionControls
                } else {
                    Divider()
                        .opacity(0.4)
                    captionAlignmentControl(selection: packageBinding(\.captionAlignment))
                }
            }

            Divider()
                .opacity(0.4)

            PrintInspectorBooleanSegmentedField(
                label: model.text(.printCropMarks),
                isOn: packageBinding(\.showsCropMarks)
            )
        }
    }

    private var customCaptionControls: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            ForEach(
                Array(settingsStore.packageSettings.customCaptions.indices),
                id: \.self
            ) { index in
                if index > 0 { Divider() }
                PrintInspectorDisclosure(
                    isExpanded: expansionBinding(for: index, in: $expandedCaptionIndex),
                    accessibilityLabel: "\(model.text(.printCustomCaption)) \(index + 1)"
                ) {
                    Text("\(model.text(.printCustomCaption)) \(index + 1)")
                        .font(.callout.weight(.medium))
                } content: {
                    customCaptionFields(index: index)
                }
            }

            Button {
                addCustomCaption()
            } label: {
                Label(model.text(.printAddCaption), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrintInspectorTransientButtonStyle())
            .disabled(
                settingsStore.packageSettings.customCaptions.count
                    >= PrintPackageSettings.maximumCustomCaptionCount
            )
        }
    }

    private func customCaptionFields(index: Int) -> some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            PrintInspectorStackedField(model.text(.printCaptionText)) {
                PrintInspectorTextField(
                    prompt: model.text(.printCaptionText),
                    text: customCaptionTextBinding(index: index)
                )
            }

            captionAlignmentControl(
                selection: customCaptionAlignmentBinding(index: index)
            )

            normalizedControl(
                title: model.text(.printPositionX),
                value: customCaptionRectBinding(index: index, component: .x)
            )
            normalizedControl(
                title: model.text(.printPositionY),
                value: customCaptionRectBinding(index: index, component: .y)
            )
            normalizedControl(
                title: model.text(.printWidth),
                value: customCaptionRectBinding(index: index, component: .width)
            )
            normalizedControl(
                title: model.text(.printHeight),
                value: customCaptionRectBinding(index: index, component: .height)
            )

            Button(role: .destructive) {
                deleteCustomCaption(at: index)
            } label: {
                Label(model.text(.printDeleteCaption), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PrintInspectorTransientButtonStyle(foregroundStyle: .red)
            )
            .disabled(settingsStore.packageSettings.customCaptions.count <= 1)
        }
    }

    private var customSourceOptions: [PrintInspectorPopupPicker<Int>.Option] {
        guard !model.actionableSelectedFrames.isEmpty else {
            return [.init(0, title: model.text(.noFrame))]
        }
        return model.actionableSelectedFrames.enumerated().map { sourceIndex, frame in
            .init(
                sourceIndex,
                title: frame.compactDisplayName(language: model.appLanguage)
            )
        }
    }

    private func pictureTemplateTitle(_ template: PrintPicturePackageTemplate) -> String {
        switch template {
        case .oneLargeTwoSmall: model.text(.printOneLargeTwoSmall)
        case .twoUp: model.text(.printTwoUp)
        case .fourUp: model.text(.printFourUp)
        }
    }

    private func contentModeTitle(_ mode: PrintPackageContentMode) -> String {
        switch mode {
        case .fit: model.text(.printFit)
        case .fill: model.text(.printFill)
        }
    }

    private func captionModeTitle(_ mode: PrintPackageCaptionMode) -> String {
        switch mode {
        case .none: model.text(.noLook)
        case .fileName: model.text(.printCaptionFileName)
        case .frameNumber: model.text(.printCaptionFrameNumber)
        case .sequenceNumber: model.text(.printCaptionSequenceNumber)
        case .rating: model.text(.printCaptionRating)
        case .customText: model.text(.printCaptionCustomText)
        }
    }

    private func captionAlignmentTitle(_ alignment: PrintPackageCaptionAlignment) -> String {
        switch alignment {
        case .leading: model.text(.printCaptionAlignLeft)
        case .center: model.text(.printCaptionAlignCenter)
        case .trailing: model.text(.printCaptionAlignRight)
        }
    }

    private func captionAlignmentControl(
        selection: Binding<PrintPackageCaptionAlignment>
    ) -> some View {
        PrintInspectorStackedField(model.text(.printCaptionAlignment)) {
            PrintInspectorSegmentedPicker(
                options: PrintPackageCaptionAlignment.allCases,
                label: captionAlignmentTitle,
                selection: selection
            )
        }
    }

    /// 아코디언 한 칸의 열림 상태. 새로 열면 이전 칸은 자동으로 닫힌다.
    private func expansionBinding(
        for index: Int,
        in state: Binding<Int?>
    ) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue == index },
            set: { isExpanded in state.wrappedValue = isExpanded ? index : nil }
        )
    }

    private func spacingControl(title: String, value: Binding<Double>) -> some View {
        let displayValue = String(format: "%.1f mm", value.wrappedValue)
        return PrintInspectorSliderRow(
            label: title,
            value: value,
            range: 0...25,
            step: 0.5,
            valueText: displayValue,
            inputFractionDigits: 1
        )
    }

    private func layoutNormalizedControl(
        title: String,
        value: Binding<Double>
    ) -> some View {
        PrintInspectorSliderRow(
            label: title,
            value: value,
            range: 0...1,
            step: 0.01,
            valueText: "\(Int((value.wrappedValue * 100).rounded()))%",
            inputScale: 100,
            inputFractionDigits: 0
        )
    }

    private func normalizedControl(title: String, value: Binding<Double>) -> some View {
        PrintInspectorSliderRow(
            label: title,
            value: value,
            range: 0...1,
            step: 0.01,
            valueText: "\(Int((value.wrappedValue * 100).rounded()))%",
            inputScale: 100,
            inputFractionDigits: 0
        )
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

    private func customCaptionTextBinding(index: Int) -> Binding<String> {
        Binding(
            get: {
                guard settingsStore.packageSettings.customCaptions.indices.contains(index) else {
                    return String()
                }
                return settingsStore.packageSettings.customCaptions[index].text
            },
            set: { value in
                updateCustomCaption(index: index) { caption in
                    var text = value
                    while text.utf8.count > 512 { text.removeLast() }
                    caption.text = text
                }
            }
        )
    }

    private func customCaptionAlignmentBinding(
        index: Int
    ) -> Binding<PrintPackageCaptionAlignment> {
        Binding(
            get: {
                guard settingsStore.packageSettings.customCaptions.indices.contains(index) else {
                    return .leading
                }
                return settingsStore.packageSettings.customCaptions[index].alignment
            },
            set: { value in
                updateCustomCaption(index: index) { $0.alignment = value }
            }
        )
    }

    private func customCaptionRectBinding(
        index: Int,
        component: RectComponent
    ) -> Binding<Double> {
        Binding(
            get: {
                guard settingsStore.packageSettings.customCaptions.indices.contains(index) else {
                    return 0
                }
                let rect = settingsStore.packageSettings.customCaptions[index].normalizedRect
                switch component {
                case .x: return Double(rect.minX)
                case .y: return Double(rect.minY)
                case .width: return Double(rect.width)
                case .height: return Double(rect.height)
                }
            },
            set: { rawValue in
                updateCustomCaption(index: index) { caption in
                    var rect = caption.normalizedRect
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
                    caption.normalizedRect = rect
                }
            }
        )
    }

    private func updateCustomCaption(
        index: Int,
        _ update: (inout PrintPackageCustomCaption) -> Void
    ) {
        var package = settingsStore.packageSettings
        guard package.customCaptions.indices.contains(index) else { return }
        update(&package.customCaptions[index])
        settingsStore.packageSettings = package
    }

    private func addCustomCaption() {
        var package = settingsStore.packageSettings
        guard package.customCaptions.count < PrintPackageSettings.maximumCustomCaptionCount else {
            return
        }
        let offset = CGFloat(package.customCaptions.count % 8) * 0.04
        package.customCaptions.append(PrintPackageCustomCaption(
            text: "",
            normalizedRect: CGRect(
                x: min(0.55, 0.05 + offset),
                y: min(0.85, 0.02 + offset),
                width: 0.4,
                height: 0.05
            )
        ))
        settingsStore.packageSettings = package
    }

    private func deleteCustomCaption(at index: Int) {
        var package = settingsStore.packageSettings
        guard package.customCaptions.count > 1,
              package.customCaptions.indices.contains(index) else { return }
        package.customCaptions.remove(at: index)
        settingsStore.packageSettings = package
        expandedCaptionIndex = nil
    }

    /// 셀 위치·크기 슬라이더.
    ///
    /// 세로 위치는 화면과 같게 **위에서부터** 센다. 저장 값은 Quartz(아래가 0)라 그대로 노출하면
    /// 0% 가 아래를 뜻해 조작이 거꾸로 느껴진다.
    ///
    /// 크기를 키울 때는 원점을 밀어 준다. 예전에는 `너비 ≤ 1 - x` 로 잘라내서, x 가 조금이라도
    /// 있으면 100% 를 줘도 그 값에 닿지 못하고 "용지 전체"가 되지 않았다.
    private func customRectBinding(index: Int, component: RectComponent) -> Binding<Double> {
        Binding(
            get: {
                guard let rect = customItem(index: index)?.normalizedRect else { return 0 }
                switch component {
                case .x: return Double(rect.minX)
                case .y: return Double(1 - rect.maxY)
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
                        // 위에서 잰 값 → 아래가 0 인 원점.
                        rect.origin.y = max(0, min(1 - value - rect.height, 1 - rect.height))
                    case .width:
                        rect.size.width = min(max(value, 0.02), 1)
                        rect.origin.x = min(rect.origin.x, 1 - rect.width)
                    case .height:
                        let topInset = 1 - rect.maxY
                        rect.size.height = min(max(value, 0.02), 1)
                        // 위 여백을 유지한 채 아래로 자란다 — 화면에서 본 대로 움직인다.
                        rect.origin.y = max(0, min(1 - topInset - rect.height, 1 - rect.height))
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
        expandedItemIndex = package.customItems.count - 1
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
        expandedItemIndex = nil
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
