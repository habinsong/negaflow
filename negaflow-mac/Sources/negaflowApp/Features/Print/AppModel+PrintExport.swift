import Chromabase
import CryptoKit
import Foundation

private struct PrintExportRecipeConfiguration: Encodable {
    let export: ExportRecipeSettings
    let composition: PrintCompositionSettings
    let package: PrintPackageSettings?
    let outputProfileSHA256: String?
    let cPrint: CPrintExportRecipeConfiguration?
}

private struct CPrintExportRecipeConfiguration: Encodable {
    let labName: String?
    let paperName: String?
    let surface: PrintPaperSurface
    let proofProfileSHA256: String?
}

extension AppModel {
    var printExportOutputCount: Int {
        let sourceCount = exportSelection.count
        guard let package = printWorkspaceSettingsStore.effectivePackageSettings(
            sourceCount: sourceCount
        ) else {
            return sourceCount
        }
        return PrintPackageLayout.expectedPageCount(
            sourceCount: sourceCount,
            package: package
        ) ?? sourceCount
    }

    func exportSelectionToFolder(for module: WorkspaceModule) {
        if module == .print, exportFormat != .rawScanTIFF {
            exportPrintSelectionToFolder(
                settings: printCompositionSettings(dpi: exportDPI)
            )
        } else {
            exportSelectionToFolder()
        }
    }

    func canExportSelection(for module: WorkspaceModule) -> Bool {
        module == .print && exportFormat != .rawScanTIFF
            ? canExportPrintSelection
            : canExportSelection
    }

    func canQuickExportSelection(for module: WorkspaceModule) -> Bool {
        module == .print && quickExportFormat != .rawScanTIFF
            ? canQuickExportPrintSelection
            : canQuickExportSelection
    }

    func quickExportSelection(for module: WorkspaceModule) {
        if module == .print, quickExportFormat != .rawScanTIFF {
            quickExportPrintSelection(
                settings: printCompositionSettings(dpi: quickExportDPI)
            )
        } else {
            quickExportSelection()
        }
    }

    func exportPrintSelectionToFolder(settings: PrintCompositionSettings) {
        guard canExportPrintSelection, settings.isValid else { return }
        if exportFormat == .rawScanTIFF {
            exportSelectionToFolder()
            return
        }
        let options = printExportOptions(exportOptions, dpi: settings.dpi)
        let requiresPrinterOutputProfile = exportSelection.contains {
            $0.params.developTarget == .print
        }
        let printerOutputProfile = selectedPrintWorkspaceOutputProfile(
            requiresPrinterOutputProfile: requiresPrinterOutputProfile
        )
        guard !hasInvalidStoredCPrintOutputProfile else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        guard !requiresPrinterOutputProfile || printerOutputProfile != nil else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        if let package = printWorkspaceSettingsStore.effectivePackageSettings(
            sourceCount: exportSelection.count
        ) {
            let packageOptions = printPackageExportOptions(options, dpi: settings.dpi)
            startPrintPackageExport(
                root: exportFolderURL,
                format: exportFormat,
                options: packageOptions,
                namingTemplate: exportNamingTemplate,
                sequenceStart: exportSequenceStart,
                printerOutputProfile: printerOutputProfile,
                composition: settings,
                package: package,
                recipeIdentity: printExportRecipeIdentity(
                    settings: settings,
                    package: package,
                    format: exportFormat,
                    options: packageOptions,
                    writeSidecar: false,
                    writeMainFlatMaster: false,
                    writeOriginalRaw: false,
                    namingTemplate: exportNamingTemplate,
                    outputProfileSHA256: printerOutputProfile?.profileSHA256
                )
            )
            return
        }
        startExportBatch(
            root: exportFolderURL,
            format: exportFormat,
            writeSidecar: exportWriteSidecar,
            writeMainFlatMaster: exportWriteMainFlatMaster,
            writeOriginalRaw: exportWriteOriginalRaw,
            options: options,
            printerOutputProfile: printerOutputProfile,
            namingTemplate: exportNamingTemplate,
            sequenceStart: exportSequenceStart,
            printComposition: settings,
            recipeIdentity: printExportRecipeIdentity(
                settings: settings,
                format: exportFormat,
                options: options,
                writeSidecar: exportWriteSidecar,
                writeMainFlatMaster: exportWriteMainFlatMaster,
                writeOriginalRaw: exportWriteOriginalRaw,
                namingTemplate: exportNamingTemplate,
                outputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        )
    }

    func quickExportPrintSelection(settings: PrintCompositionSettings) {
        guard canQuickExportPrintSelection, settings.isValid else { return }
        if quickExportFormat == .rawScanTIFF {
            quickExportSelection()
            return
        }
        let options = printExportOptions(quickExportOptions, dpi: settings.dpi)
        let requiresPrinterOutputProfile = exportSelection.contains {
            $0.params.developTarget == .print
        }
        let printerOutputProfile = selectedPrintWorkspaceOutputProfile(
            requiresPrinterOutputProfile: requiresPrinterOutputProfile
        )
        guard !hasInvalidStoredCPrintOutputProfile else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        guard !requiresPrinterOutputProfile || printerOutputProfile != nil else {
            statusMessage = text(.printOutputProfileRequired)
            return
        }
        if let package = printWorkspaceSettingsStore.effectivePackageSettings(
            sourceCount: exportSelection.count
        ) {
            let packageOptions = printPackageExportOptions(options, dpi: settings.dpi)
            startPrintPackageExport(
                root: quickExportFolderURL,
                format: quickExportFormat,
                options: packageOptions,
                namingTemplate: ExportNamingTemplate.defaultPattern,
                printerOutputProfile: printerOutputProfile,
                composition: settings,
                package: package,
                recipeIdentity: printExportRecipeIdentity(
                    settings: settings,
                    package: package,
                    format: quickExportFormat,
                    options: packageOptions,
                    writeSidecar: false,
                    writeMainFlatMaster: false,
                    writeOriginalRaw: false,
                    namingTemplate: ExportNamingTemplate.defaultPattern,
                    outputProfileSHA256: printerOutputProfile?.profileSHA256
                )
            )
            return
        }
        startExportBatch(
            root: quickExportFolderURL,
            format: quickExportFormat,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            options: options,
            printerOutputProfile: printerOutputProfile,
            namingTemplate: ExportNamingTemplate.defaultPattern,
            printComposition: settings,
            recipeIdentity: printExportRecipeIdentity(
                settings: settings,
                format: quickExportFormat,
                options: options,
                writeSidecar: false,
                writeMainFlatMaster: false,
                writeOriginalRaw: false,
                namingTemplate: ExportNamingTemplate.defaultPattern,
                outputProfileSHA256: printerOutputProfile?.profileSHA256
            )
        )
    }

    func printExportOptions(_ options: ExportOptions, dpi: Int) -> ExportOptions {
        var result = options
        result.dpi = dpi > 0 ? dpi : 300
        result.longEdge = nil
        return result
    }

    func printPackageExportOptions(_ options: ExportOptions, dpi: Int) -> ExportOptions {
        var result = printExportOptions(options, dpi: dpi)
        // 여러 source를 한 page로 합성하므로 어느 한 source의 metadata도 대표할 수 없습니다.
        result.metadataPolicy = .minimal
        return result
    }

    func printExportRecipeIdentity(
        settings: PrintCompositionSettings,
        package: PrintPackageSettings? = nil,
        format: ExportFormat,
        options: ExportOptions,
        writeSidecar: Bool,
        writeMainFlatMaster: Bool,
        writeOriginalRaw: Bool,
        namingTemplate: String,
        outputProfileSHA256: String? = nil
    ) -> ExportRecipeIdentity? {
        let export = ExportRecipeSettings(
            format: format,
            options: options,
            writeSidecar: writeSidecar,
            writeMainFlatMaster: writeMainFlatMaster,
            writeOriginalRaw: writeOriginalRaw,
            filenameTemplate: namingTemplate
        )
        var effectiveSettings = settings
        if package != nil { effectiveSettings.perforationStyle = .none }
        let configuration = PrintExportRecipeConfiguration(
            export: export,
            composition: effectiveSettings,
            package: package,
            outputProfileSHA256: outputProfileSHA256,
            cPrint: cPrintExportRecipeConfiguration
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(configuration) else { return nil }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ExportRecipeIdentity(
            presetID: nil,
            presetName: nil,
            configurationSHA256: hash
        )
    }

    private var cPrintExportRecipeConfiguration: CPrintExportRecipeConfiguration? {
        guard printWorkspaceSettingsStore.outputProcess == .cPrint else { return nil }
        let labName = printWorkspaceSettingsStore.cPrintLabName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let paperName = printWorkspaceSettingsStore.cPrintPaperName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CPrintExportRecipeConfiguration(
            labName: labName.isEmpty ? nil : labName,
            paperName: paperName.isEmpty ? nil : paperName,
            surface: printWorkspaceSettingsStore.paperSurface,
            proofProfileSHA256: cPrintProofICCProfileData.map(ICCOutputProfileSnapshot.sha256)
        )
    }

    private func selectedPrintWorkspaceOutputProfile(
        requiresPrinterOutputProfile: Bool
    ) -> ICCOutputProfileSnapshot? {
        if printWorkspaceSettingsStore.outputProcess == .cPrint,
           let cPrintProfile = selectedCPrintOutputProfile {
            return cPrintProfile
        }
        return requiresPrinterOutputProfile ? selectedPrinterOutputProfile : nil
    }

    private var hasInvalidStoredCPrintOutputProfile: Bool {
        printWorkspaceSettingsStore.outputProcess == .cPrint
            && cPrintProofICCProfileData != nil
            && selectedCPrintOutputProfile == nil
    }
}
