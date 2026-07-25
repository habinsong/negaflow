import Foundation
import Chromabase

extension AppModel {
    func exportBaseName(
        for frame: ScanFrame,
        namingTemplate: String,
        sequence: Int,
        date: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        recipeIdentity: ExportRecipeIdentity?
    ) -> String {
        let frameName = FrameStorageNaming.sanitizeComponent(
            frame.displayName(language: appLanguage)
        )
        let fallback = frameName.isEmpty ? "frame\(frame.scanIndex)" : frameName
        let context = ExportNamingContext(
            date: date,
            timeZone: timeZone,
            roll: exportRollName(for: frame),
            frameIndex: frame.presentationIndex,
            frameName: fallback,
            preset: recipeIdentity?.presetName ?? frame.preset?.id ?? "manual",
            sequence: sequence
        )
        return ExportNamingTemplate.render(namingTemplate, context: context) ?? fallback
    }

    func exportNamingPreview(for frame: ScanFrame? = nil) -> String? {
        guard let frame = frame ?? actionableFrame else { return nil }
        let outputProfileSHA256 = frame.params.developTarget == .print
            ? selectedPrinterOutputProfile?.profileSHA256
            : nil
        return exportNamingPreview(
            for: frame,
            namingTemplate: exportNamingTemplate,
            sequence: exportSequenceStart,
            format: exportFormat,
            recipeIdentity: currentExportRecipeIdentity(
                outputProfileSHA256: outputProfileSHA256
            )
        )
    }

    func quickExportNamingPreview(for frame: ScanFrame? = nil) -> String? {
        guard let frame = frame ?? actionableFrame else { return nil }
        let outputProfileSHA256 = frame.params.developTarget == .print
            ? selectedPrinterOutputProfile?.profileSHA256
            : nil
        return exportNamingPreview(
            for: frame,
            namingTemplate: ExportNamingTemplate.defaultPattern,
            sequence: 1,
            format: quickExportFormat,
            recipeIdentity: quickExportRecipeIdentity(
                outputProfileSHA256: outputProfileSHA256
            )
        )
    }

    private func exportNamingPreview(
        for frame: ScanFrame,
        namingTemplate: String,
        sequence: Int,
        format: ExportFormat,
        recipeIdentity: ExportRecipeIdentity?
    ) -> String? {
        guard ExportNamingTemplate.isValid(namingTemplate) else { return nil }
        let name = exportBaseName(
            for: frame,
            namingTemplate: namingTemplate,
            sequence: sequence,
            date: Date(),
            recipeIdentity: recipeIdentity
        )
        return URL(fileURLWithPath: name)
            .appendingPathExtension(format.fileExtension)
            .lastPathComponent
    }

    private func exportRollName(for frame: ScanFrame) -> String {
        let memberships = rolls.filter { $0.frameIDs.contains(frame.id) }
        if memberships.count == 1,
           let name = memberships[0].name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return frame.storageGroupName ?? "unassigned"
    }
}
