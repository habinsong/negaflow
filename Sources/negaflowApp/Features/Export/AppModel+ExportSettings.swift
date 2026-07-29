import Chromabase
import Foundation

extension AppModel {
    var exportFormat: ExportFormat {
        get { exportSettingsStore.exportFormat }
        set {
            exportSettingsStore.exportFormat = newValue
            if newValue == .jpeg || newValue == .rawScanTIFF {
                exportPreserveAlpha = false
            }
            if newValue == .rawScanTIFF {
                exportTIFFCompression = .none
                exportTIFFBitDepth = .sixteen
                exportOutputSharpening = 0
                exportLongEdge = 0
            }
        }
    }

    var exportColorSpace: ExportColorSpace {
        get { exportSettingsStore.exportColorSpace }
        set {
            guard newValue != exportSettingsStore.exportColorSpace else { return }
            exportSettingsStore.exportColorSpace = newValue
            if softProofEnabled { advanceSoftProofConfiguration() }
        }
    }

    var softProofEnabled: Bool {
        get { exportSettingsStore.softProofEnabled }
        set {
            guard newValue != exportSettingsStore.softProofEnabled else { return }
            exportSettingsStore.softProofEnabled = newValue
            advanceSoftProofConfiguration()
        }
    }

    var softProofSimulation: SoftProofSimulation {
        get { exportSettingsStore.softProofSimulation }
        set {
            guard newValue != exportSettingsStore.softProofSimulation else { return }
            exportSettingsStore.softProofSimulation = newValue
            if softProofEnabled { advanceSoftProofConfiguration() }
        }
    }

    var destinationGamutWarningEnabled: Bool {
        get { exportSettingsStore.destinationGamutWarningEnabled }
        set {
            guard newValue != exportSettingsStore.destinationGamutWarningEnabled else { return }
            exportSettingsStore.destinationGamutWarningEnabled = newValue
            if softProofEnabled { advanceSoftProofConfiguration() }
        }
    }

    var destinationGamutWarningAvailable: Bool {
        DestinationGamutWarning.isSupported(
            for: displaySoftProofSettings(for: actionableFrame)
        )
    }

    var softProofICCProfileData: Data? { exportSettingsStore.softProofICCProfileData }
    var softProofICCProfileName: String? { exportSettingsStore.softProofICCProfileName }
    var printerOutputICCProfileData: Data? { exportSettingsStore.printerOutputICCProfileData }
    var printerOutputICCProfileName: String? { exportSettingsStore.printerOutputICCProfileName }

    var selectedPrinterOutputProfile: ICCOutputProfileSnapshot? {
        guard let data = printerOutputICCProfileData else { return nil }
        return ICCOutputProfileSnapshot(
            profileName: printerOutputICCProfileName ?? "Printer ICC",
            iccProfileData: data
        )
    }

    @discardableResult
    func setPrinterOutputICCProfile(data: Data, name: String) -> Bool {
        guard let profile = ICCOutputProfileSnapshot(
            profileName: name,
            iccProfileData: data
        ) else { return false }
        exportSettingsStore.printerOutputICCProfileData = profile.iccProfileData
        exportSettingsStore.printerOutputICCProfileName = profile.profileName
        advanceSoftProofConfiguration()
        return true
    }

    func clearPrinterOutputICCProfile() {
        guard printerOutputICCProfileData != nil || printerOutputICCProfileName != nil else { return }
        exportSettingsStore.printerOutputICCProfileData = nil
        exportSettingsStore.printerOutputICCProfileName = nil
        advanceSoftProofConfiguration()
    }

    @discardableResult
    func setSoftProofICCProfile(data: Data, name: String) -> Bool {
        guard SoftProof.rgbOutputColorSpace(fromICCData: data) != nil else { return false }
        let changed = data != exportSettingsStore.softProofICCProfileData
            || name != exportSettingsStore.softProofICCProfileName
        exportSettingsStore.softProofICCProfileData = data
        exportSettingsStore.softProofICCProfileName = name
        if changed, softProofEnabled { advanceSoftProofConfiguration() }
        return true
    }

    func clearSoftProofICCProfile() {
        guard exportSettingsStore.softProofICCProfileData != nil
                || exportSettingsStore.softProofICCProfileName != nil else { return }
        exportSettingsStore.softProofICCProfileData = nil
        exportSettingsStore.softProofICCProfileName = nil
        if softProofEnabled { advanceSoftProofConfiguration() }
    }

    /// Proof Copy를 다시 선택하면 생성 당시의 정확한 내장 프로파일 또는 임베디드 사용자 ICC를
    /// 복원한다. 해시/ICC 검증에 실패하면 현재 설정으로 조용히 대체하지 않는다.
    @discardableResult
    func restoreProofCopyConfigurationIfNeeded(for frame: ScanFrame) -> Bool {
        guard let configuration = frame.proofCopyConfiguration else { return true }
        guard let settings = configuration.resolvedSoftProofSettings else {
            statusMessage = text(AppLocalizedPhrase.softProofInvalidICC)
            return false
        }
        let customName = configuration.usesCustomProfile ? configuration.profileName : nil
        let changed = exportSettingsStore.softProofEnabled != settings.isEnabled
            || exportSettingsStore.exportColorSpace != settings.colorSpace
            || exportSettingsStore.softProofSimulation != settings.simulation
            || exportSettingsStore.softProofICCProfileData != settings.iccProfileData
            || exportSettingsStore.softProofICCProfileName != customName
        guard changed else { return true }
        exportSettingsStore.exportColorSpace = settings.colorSpace
        exportSettingsStore.softProofSimulation = settings.simulation
        exportSettingsStore.softProofICCProfileData = settings.iccProfileData
        exportSettingsStore.softProofICCProfileName = customName
        exportSettingsStore.softProofEnabled = true
        advanceSoftProofConfiguration()
        return true
    }

    private func advanceSoftProofConfiguration() {
        softProofConfigurationRevision &+= 1
        refreshSoftProofPreviewIfNeeded()
    }

    var exportDPI: Int {
        get { exportSettingsStore.exportDPI }
        set { exportSettingsStore.exportDPI = newValue }
    }

    var exportLongEdge: Int {
        get { exportSettingsStore.exportLongEdge }
        set { exportSettingsStore.exportLongEdge = newValue }
    }

    var exportWriteMainFlatMaster: Bool {
        get { exportSettingsStore.exportWriteMainFlatMaster }
        set { exportSettingsStore.exportWriteMainFlatMaster = newValue }
    }

    var exportWriteOriginalRaw: Bool {
        get { exportSettingsStore.exportWriteOriginalRaw }
        set { exportSettingsStore.exportWriteOriginalRaw = newValue }
    }

    var exportNamingTemplate: String {
        get { exportSettingsStore.exportNamingTemplate }
        set { exportSettingsStore.exportNamingTemplate = ExportNamingTemplate.normalized(newValue) }
    }

    var exportSequenceStart: Int {
        get { exportSettingsStore.exportSequenceStart }
        set { exportSettingsStore.exportSequenceStart = max(1, newValue) }
    }

    var quickExportFormat: ExportFormat {
        get { exportSettingsStore.quickExportFormat }
        set {
            exportSettingsStore.quickExportFormat = newValue == .png ? .png : .jpeg
        }
    }

    var quickExportDPI: Int {
        get { exportSettingsStore.quickExportDPI }
        set { exportSettingsStore.quickExportDPI = newValue }
    }

    var quickExportLongEdge: Int {
        get { exportSettingsStore.quickExportLongEdge }
        set { exportSettingsStore.quickExportLongEdge = max(0, newValue) }
    }

    var exportVerificationLevel: ExportVerificationLevel {
        get { exportSettingsStore.exportVerificationLevel }
        set { exportSettingsStore.exportVerificationLevel = newValue }
    }

    var quickExportFolderPath: String? {
        get { diskStorage.quickExportPath }
        set { diskStorage.quickExportPath = newValue }
    }

    var exportFolderPath: String? {
        get { diskStorage.exportPath }
        set { diskStorage.exportPath = newValue }
    }

    var exportOptions: ExportOptions {
        var options = ExportOptions(
            colorSpace: exportColorSpace,
            dpi: exportDPI,
            longEdge: exportLongEdge > 0 ? exportLongEdge : nil,
            jpegQuality: exportJPEGQuality,
            tiffCompression: exportTIFFCompression,
            tiffBitDepth: exportTIFFBitDepth,
            preserveAlpha: exportPreserveAlpha,
            metadataPolicy: exportMetadataPolicy,
            outputSharpening: exportOutputSharpening,
            outputSharpeningMedium: exportOutputSharpeningMedium
        )
        if exportFormat == .rawScanTIFF {
            options.longEdge = nil
            options.tiffCompression = .none
            options.tiffBitDepth = .sixteen
            options.preserveAlpha = false
            options.outputSharpening = 0
        }
        return options
    }

    var softProofSettings: SoftProofSettings {
        SoftProofSettings(
            isEnabled: softProofEnabled,
            colorSpace: exportColorSpace,
            simulation: softProofSimulation,
            iccProfileData: softProofICCProfileData,
            printerOutputICCProfileData: printerOutputICCProfileData
        )
    }

    var printerSoftProofSettings: SoftProofSettings {
        var settings = softProofSettings
        settings.iccProfileData = printerOutputICCProfileData
        return settings
    }

    /// 최종 출력 계약과 동일한 프루프 대상을 스냅샷에 고정합니다. PRINT workspace의 합성
    /// 출력과 `.print` target은 printer ICC를 쓰고, Proof Copy는 생성 당시의 내장 ICC가 우선합니다.
    func displaySoftProofSettings(for frame: ScanFrame?) -> SoftProofSettings {
        if let configuration = frame?.proofCopyConfiguration,
           let resolved = configuration.resolvedSoftProofSettings {
            return resolved
        }
        if activeWorkspaceModule == .print || frame?.params.developTarget == .print {
            return printerSoftProofSettings
        }
        return softProofSettings
    }

    var quickExportOptions: ExportOptions {
        ExportOptions(
            colorSpace: .sRGB,
            dpi: quickExportDPI,
            longEdge: quickExportLongEdge > 0 ? quickExportLongEdge : nil
        )
    }

    var quickExportFolderURL: URL { diskStorage.quickExportURL }
    var quickExportFolderDisplay: String { quickExportFolderURL.lastPathComponent }
    var exportFolderURL: URL { diskStorage.exportURL }
    var exportFolderDisplay: String { exportFolderURL.lastPathComponent }
}
