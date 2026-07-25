import CryptoKit
import Foundation

private struct ExportRecipeIdentityConfiguration: Encodable {
    let settings: ExportRecipeSettings
    let outputProfileSHA256: String
}

extension AppModel {
    var exportRecipes: [ExportRecipe] { exportRecipeStore.recipes }

    var currentExportRecipeSettings: ExportRecipeSettings {
        ExportRecipeSettings(
            format: exportFormat,
            options: exportOptions,
            writeSidecar: exportWriteSidecar,
            writeMainFlatMaster: exportWriteMainFlatMaster,
            writeOriginalRaw: exportWriteOriginalRaw,
            filenameTemplate: exportNamingTemplate
        )
    }

    func currentExportRecipeIdentity(
        outputProfileSHA256: String? = nil
    ) -> ExportRecipeIdentity? {
        let settings = currentExportRecipeSettings
        guard let hash = exportRecipeConfigurationSHA256(
            settings: settings,
            outputProfileSHA256: outputProfileSHA256
        ) else { return nil }
        let matchedPreset = selectedExportRecipeID.flatMap { selectedID in
            exportRecipes.first { $0.id == selectedID && $0.settings == settings }
        }
        return ExportRecipeIdentity(
            presetID: matchedPreset?.id,
            presetName: matchedPreset?.name,
            configurationSHA256: hash
        )
    }

    func quickExportRecipeIdentity(
        outputProfileSHA256: String? = nil
    ) -> ExportRecipeIdentity? {
        let settings = ExportRecipeSettings(
            format: quickExportFormat,
            options: quickExportOptions,
            writeSidecar: false,
            writeMainFlatMaster: false,
            writeOriginalRaw: false,
            filenameTemplate: ExportNamingTemplate.defaultPattern
        )
        guard let hash = exportRecipeConfigurationSHA256(
            settings: settings,
            outputProfileSHA256: outputProfileSHA256
        ) else { return nil }
        return ExportRecipeIdentity(
            presetID: nil,
            presetName: nil,
            configurationSHA256: hash
        )
    }

    func nextExportRecipeName() -> String {
        var index = exportRecipes.count + 1
        while exportRecipes.contains(where: {
            $0.name.caseInsensitiveCompare(localizedExportRecipe(.defaultName(index))) == .orderedSame
        }) {
            index += 1
        }
        return localizedExportRecipe(.defaultName(index))
    }

    func canSaveExportRecipeName(_ name: String, excluding id: UUID? = nil) -> Bool {
        let normalized = ExportRecipe.normalizedName(name)
        return exportRecipeStore.canModify && !normalized.isEmpty && !exportRecipes.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(normalized) == .orderedSame
        }
    }

    @discardableResult
    func saveCurrentExportRecipe(name: String) -> UUID? {
        guard let recipe = exportRecipeStore.add(
            name: name,
            settings: currentExportRecipeSettings
        ) else { return nil }
        selectedExportRecipeID = recipe.id
        statusMessage = localizedExportRecipe(.saved(recipe.name))
        return recipe.id
    }

    func applyExportRecipe(_ recipe: ExportRecipe) {
        exportFormat = recipe.settings.format
        exportColorSpace = recipe.settings.options.colorSpace
        exportDPI = recipe.settings.options.dpi
        exportLongEdge = recipe.settings.options.longEdge ?? 0
        exportJPEGQuality = recipe.settings.options.jpegQuality
        exportTIFFCompression = recipe.settings.options.tiffCompression
        exportTIFFBitDepth = recipe.settings.options.tiffBitDepth
        exportPreserveAlpha = recipe.settings.options.preserveAlpha
        exportMetadataPolicy = recipe.settings.options.metadataPolicy
        exportOutputSharpening = recipe.settings.options.outputSharpening
        exportOutputSharpeningMedium = recipe.settings.options.outputSharpeningMedium
        exportWriteSidecar = recipe.settings.writeSidecar
        exportWriteMainFlatMaster = recipe.settings.writeMainFlatMaster
        exportWriteOriginalRaw = recipe.settings.writeOriginalRaw
        exportNamingTemplate = recipe.settings.filenameTemplate
        selectedExportRecipeID = recipe.id
        statusMessage = localizedExportRecipe(.applied(recipe.name))
    }

    func renameExportRecipe(_ recipe: ExportRecipe, to name: String) -> Bool {
        exportRecipeStore.rename(id: recipe.id, to: name)
    }

    func deleteExportRecipe(_ recipe: ExportRecipe) {
        exportRecipeStore.delete(id: recipe.id)
        if selectedExportRecipeID == recipe.id {
            selectedExportRecipeID = nil
        }
        statusMessage = localizedExportRecipe(.deleted(recipe.name))
    }

    func localizedExportRecipe(_ text: ExportRecipeLocalizedText) -> String {
        text.resolved(language: appLanguage)
    }

    private func exportRecipeConfigurationSHA256(
        settings: ExportRecipeSettings,
        outputProfileSHA256: String?
    ) -> String? {
        guard let outputProfileSHA256 else {
            return try? settings.configurationSHA256()
        }
        let configuration = ExportRecipeIdentityConfiguration(
            settings: settings,
            outputProfileSHA256: outputProfileSHA256
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(configuration) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
