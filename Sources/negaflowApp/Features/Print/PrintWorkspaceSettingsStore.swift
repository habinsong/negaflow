import Chromabase
import Combine
import Foundation

enum PrintWorkspaceLayoutMode: String, CaseIterable, Codable, Sendable {
    case singleImage
    case contactSheet
    case picturePackage
    case customPackage
    case cyanotype
    case glassPlate
    case gelatin

    var packageMode: PrintPackageLayoutMode? {
        switch self {
        case .singleImage, .cyanotype, .glassPlate, .gelatin: nil
        case .contactSheet: .contactSheet
        case .picturePackage: .picturePackage
        case .customPackage: .customPackage
        }
    }

    var usesIndividualPages: Bool {
        packageMode == nil
    }

    func usesVerticalPageStack(sourceCount: Int) -> Bool {
        usesIndividualPages && sourceCount > 1
    }

    var presentationStyle: PrintPresentationStyle {
        switch self {
        case .singleImage, .contactSheet, .picturePackage, .customPackage:
            .standard
        case .cyanotype:
            .cyanotype
        case .glassPlate:
            .glassPlate
        case .gelatin:
            .gelatinSilver
        }
    }
}

enum PrintOutputProcess: String, CaseIterable, Codable, Sendable {
    case standard
    case cPrint
}

enum PrintPaperSurface: String, CaseIterable, Codable, Sendable {
    case glossy
    case matte
    case lustre
    case silk
}

@MainActor
final class PrintWorkspaceSettingsStore: ObservableObject {
    private enum Keys {
        static let paperSize = "print.paperSize"
        static let orientation = "print.orientation"
        static let marginMM = "print.marginMM"
        static let perforationStyle = "print.perforationStyle"
        static let layoutMode = "print.layoutMode"
        static let packageSettings = "print.packageSettings"
        static let outputProcess = "print.outputProcess"
        static let cPrintLabName = "print.cPrint.labName"
        static let cPrintPaperName = "print.cPrint.paperName"
        static let cPrintPaperSurface = "print.cPrint.paperSurface"
        static let cPrintProofICCProfileData = "print.cPrint.proofICCProfileData"
        static let cPrintProofICCProfileName = "print.cPrint.proofICCProfileName"
        static let cPrintPreviewEnabled = "print.cPrint.previewEnabled"
        static let cPrintPaperSimulationEnabled = "print.cPrint.paperSimulationEnabled"
    }

    private let defaults: UserDefaults
    private var isNormalizingContactSheetGeometry = false

    @Published var paperSize: PrintPaperSize {
        didSet {
            defaults.set(paperSize.rawValue, forKey: Keys.paperSize)
            normalizeContactSheetGeometry()
        }
    }

    @Published var orientation: PrintPaperOrientation {
        didSet {
            defaults.set(orientation.rawValue, forKey: Keys.orientation)
            normalizeContactSheetGeometry()
        }
    }

    @Published var marginMM: Double {
        didSet {
            let normalized = Self.normalizedMargin(marginMM)
            if normalized != marginMM {
                marginMM = normalized
            } else {
                defaults.set(normalized, forKey: Keys.marginMM)
                normalizeContactSheetGeometry()
            }
        }
    }

    @Published var perforationStyle: PrintPerforationStyle {
        didSet { defaults.set(perforationStyle.rawValue, forKey: Keys.perforationStyle) }
    }

    @Published var layoutMode: PrintWorkspaceLayoutMode {
        didSet {
            defaults.set(layoutMode.rawValue, forKey: Keys.layoutMode)
            normalizeContactSheetGeometry()
        }
    }

    @Published var packageSettings: PrintPackageSettings {
        didSet {
            normalizeContactSheetGeometry()
            guard packageSettings.isValid,
                  let data = try? JSONEncoder().encode(packageSettings) else { return }
            defaults.set(data, forKey: Keys.packageSettings)
        }
    }

    @Published var outputProcess: PrintOutputProcess {
        didSet { defaults.set(outputProcess.rawValue, forKey: Keys.outputProcess) }
    }

    @Published var cPrintLabName: String {
        didSet { defaults.set(cPrintLabName, forKey: Keys.cPrintLabName) }
    }

    @Published var cPrintPaperName: String {
        didSet { defaults.set(cPrintPaperName, forKey: Keys.cPrintPaperName) }
    }

    @Published var cPrintPaperSurface: PrintPaperSurface {
        didSet { defaults.set(cPrintPaperSurface.rawValue, forKey: Keys.cPrintPaperSurface) }
    }

    @Published var cPrintProofICCProfileData: Data? {
        didSet {
            if let cPrintProofICCProfileData {
                defaults.set(cPrintProofICCProfileData, forKey: Keys.cPrintProofICCProfileData)
            } else {
                defaults.removeObject(forKey: Keys.cPrintProofICCProfileData)
            }
        }
    }

    @Published var cPrintProofICCProfileName: String? {
        didSet {
            if let cPrintProofICCProfileName {
                defaults.set(cPrintProofICCProfileName, forKey: Keys.cPrintProofICCProfileName)
            } else {
                defaults.removeObject(forKey: Keys.cPrintProofICCProfileName)
            }
        }
    }

    @Published var cPrintPreviewEnabled: Bool {
        didSet { defaults.set(cPrintPreviewEnabled, forKey: Keys.cPrintPreviewEnabled) }
    }

    @Published var cPrintPaperSimulationEnabled: Bool {
        didSet {
            defaults.set(
                cPrintPaperSimulationEnabled,
                forKey: Keys.cPrintPaperSimulationEnabled
            )
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        paperSize = defaults.string(forKey: Keys.paperSize)
            .flatMap(PrintPaperSize.init(rawValue:)) ?? .a4
        orientation = defaults.string(forKey: Keys.orientation)
            .flatMap(PrintPaperOrientation.init(rawValue:)) ?? .automatic
        let storedMargin = defaults.object(forKey: Keys.marginMM) as? Double
        marginMM = Self.normalizedMargin(storedMargin ?? 10)
        perforationStyle = defaults.string(forKey: Keys.perforationStyle)
            .flatMap(PrintPerforationStyle.init(rawValue:)) ?? .none
        layoutMode = defaults.string(forKey: Keys.layoutMode)
            .flatMap(PrintWorkspaceLayoutMode.init(rawValue:)) ?? .singleImage
        if let data = defaults.data(forKey: Keys.packageSettings),
           var decoded = try? JSONDecoder().decode(PrintPackageSettings.self, from: data),
           decoded.isValid {
            // "사진 한 장씩 반복"은 기억하지 않는다. 켜져 있으면 콘택트 시트가 선택한 나머지를
            // 버리고 첫 장만 채우는데, 다음 실행에서 그대로 살아나면 다중 선택이 사라진 것처럼
            // 보인다. 시작은 언제나 꺼진 상태이고, 필요하면 그 자리에서 켠다.
            decoded.repeatOnePhotoPerPage = false
            packageSettings = decoded
        } else {
            packageSettings = PrintPackageSettings()
        }
        // 출력 방식은 기억하지 않는다. C-Print 는 랩에 넘길 때만 켜는 특수 경로인데, 한 번 켠
        // 뒤 다음 실행에서도 켜져 있으면 일반 출력인 줄 알고 프루프가 걸린 결과를 받게 된다.
        outputProcess = .standard
        cPrintLabName = defaults.string(forKey: Keys.cPrintLabName) ?? ""
        cPrintPaperName = defaults.string(forKey: Keys.cPrintPaperName) ?? ""
        cPrintPaperSurface = defaults.string(forKey: Keys.cPrintPaperSurface)
            .flatMap(PrintPaperSurface.init(rawValue:)) ?? .glossy
        let storedCPrintProofData = defaults.data(forKey: Keys.cPrintProofICCProfileData)
        let storedCPrintProofName = defaults.string(forKey: Keys.cPrintProofICCProfileName)
        let validCPrintProofData: Data?
        if let data = storedCPrintProofData,
           SoftProof.rgbOutputColorSpace(fromICCData: data) != nil {
            validCPrintProofData = data
            cPrintProofICCProfileData = data
            cPrintProofICCProfileName = storedCPrintProofName
        } else {
            validCPrintProofData = nil
            cPrintProofICCProfileData = nil
            cPrintProofICCProfileName = nil
        }
        cPrintPreviewEnabled = validCPrintProofData != nil
            && defaults.bool(forKey: Keys.cPrintPreviewEnabled)
        cPrintPaperSimulationEnabled = defaults.bool(
            forKey: Keys.cPrintPaperSimulationEnabled
        )
        normalizeContactSheetGeometry()
    }

    /// `photoAspectRatio` 는 "사진 비율" 용지가 따라갈 가로세로비다. 다른 용지에서는 무시된다.
    func compositionSettings(
        dpi: Int,
        photoAspectRatio: Double? = nil
    ) -> PrintCompositionSettings {
        PrintCompositionSettings(
            paperSize: paperSize,
            orientation: orientation,
            marginMM: marginMM,
            dpi: dpi > 0 ? dpi : 300,
            perforationStyle: perforationStyle,
            photoAspectRatio: photoAspectRatio,
            presentationStyle: layoutMode.presentationStyle
        )
    }

    func effectivePackageSettings(sourceCount: Int? = nil) -> PrintPackageSettings? {
        guard let mode = layoutMode.packageMode else { return nil }
        var result = packageSettings
        result.mode = mode
        if mode == .customPackage, let sourceCount, sourceCount > 0 {
            let maximumSourceIndex = sourceCount - 1
            for index in result.customItems.indices {
                result.customItems[index].sourceIndex = min(
                    result.customItems[index].sourceIndex,
                    maximumSourceIndex
                )
            }
        }
        return result.isValid ? result : nil
    }

    func prepareDefaultCustomPackage(sourceCount: Int) {
        guard layoutMode == .customPackage,
              sourceCount > 1,
              sourceCount <= PrintPackageSettings.maximumCustomItemCount,
              packageSettings.customItems.count == 1,
              let defaultItem = packageSettings.customItems.first,
              defaultItem.sourceIndex == 0,
              defaultItem.pageIndex == 0,
              defaultItem.normalizedRect == CGRect(x: 0, y: 0, width: 1, height: 1),
              defaultItem.contentMode == .fit,
              !defaultItem.rotateToFit,
              defaultItem.zIndex == 0 else { return }

        let columns = Int(ceil(sqrt(Double(sourceCount))))
        let rows = (sourceCount + columns - 1) / columns
        let cellWidth = 1 / CGFloat(columns)
        let cellHeight = 1 / CGFloat(rows)
        var package = packageSettings
        package.customItems = (0..<sourceCount).map { sourceIndex in
            let row = sourceIndex / columns
            let column = sourceIndex % columns
            return PrintCustomPackageItem(
                sourceIndex: sourceIndex,
                normalizedRect: CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: 1 - CGFloat(row + 1) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                ),
                zIndex: sourceIndex
            )
        }
        packageSettings = package
    }

    func apply(_ settings: PrintLayoutTemplateSettings) {
        guard settings.isValid else { return }
        paperSize = settings.paperSize
        orientation = settings.orientation
        marginMM = settings.marginMM
        perforationStyle = settings.perforationStyle
        layoutMode = settings.layoutMode
        packageSettings = settings.packageSettings
    }

    func templateSettings() -> PrintLayoutTemplateSettings {
        PrintLayoutTemplateSettings(
            paperSize: paperSize,
            orientation: orientation,
            marginMM: marginMM,
            perforationStyle: perforationStyle,
            layoutMode: layoutMode,
            packageSettings: packageSettings
        )
    }

    private static func normalizedMargin(_ value: Double) -> Double {
        guard value.isFinite else { return 10 }
        return min(max(value, 0), 50)
    }

    private func normalizeContactSheetGeometry() {
        guard !isNormalizingContactSheetGeometry,
              layoutMode == .contactSheet,
              packageSettings.isValid else { return }
        isNormalizingContactSheetGeometry = true
        defer { isNormalizingContactSheetGeometry = false }

        var package = packageSettings
        let page = contactSheetPageDimensionsMM(package: package)
        let minimumCellWidthMM = 0.5
        let usesPerImageCaption = package.captionMode != .none
            && package.captionMode != .customText
        if usesPerImageCaption {
            let maximumCaptionHeight = max(
                0,
                page.height / Double(package.contactRows) - 0.5
            )
            package.captionHeightMM = min(package.captionHeightMM, maximumCaptionHeight)
        }
        let minimumCellHeightMM = usesPerImageCaption
            ? package.captionHeightMM + 0.5
            : 0.5
        let maximumMargin = max(
            0,
            min(
                50,
                (page.width - Double(package.contactColumns) * minimumCellWidthMM) / 2,
                (page.height - Double(package.contactRows) * minimumCellHeightMM) / 2
            )
        )
        let normalizedMargin = min(Self.normalizedMargin(marginMM), maximumMargin)
        let availableGapWidth = max(
            0,
            page.width
                - 2 * normalizedMargin
                - Double(package.contactColumns) * minimumCellWidthMM
        )
        let availableGapHeight = max(
            0,
            page.height
                - 2 * normalizedMargin
                - Double(package.contactRows) * minimumCellHeightMM
        )
        let maximumHorizontalSpacing = package.contactColumns > 1
            ? availableGapWidth / Double(package.contactColumns - 1)
            : 25
        let maximumVerticalSpacing = package.contactRows > 1
            ? availableGapHeight / Double(package.contactRows - 1)
            : 25
        package.horizontalSpacingMM = min(
            package.horizontalSpacingMM,
            maximumHorizontalSpacing,
            25
        )
        package.verticalSpacingMM = min(
            package.verticalSpacingMM,
            maximumVerticalSpacing,
            25
        )

        if marginMM != normalizedMargin {
            marginMM = normalizedMargin
        }
        if packageSettings != package {
            packageSettings = package
        }
    }

    private func contactSheetPageDimensionsMM(package: PrintPackageSettings) -> CGSize {
        let base = paperSize.dimensionsMM
        let isLandscape: Bool
        switch orientation {
        case .automatic:
            isLandscape = package.contactColumns >= package.contactRows
        case .portrait:
            isLandscape = false
        case .landscape:
            isLandscape = true
        }
        return isLandscape
            ? CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
            : CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
    }
}
