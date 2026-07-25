import Foundation
import Chromabase

enum ExportTrackingEventFactory {
    static func makeEvent(
        trackingIdentity: ExportFrameTrackingIdentity,
        sourceIdentity: RenderManifest.SourceIdentity,
        result: ExportFrameResult,
        expectedLayout: ExportArtifactLayout,
        format: ExportFormat,
        exportRecipeIdentity: ExportRecipeIdentity? = nil,
        completedAt: Date = Date(),
        fileManager: FileManager = .default
    ) -> LibraryExportEvent? {
        let actualURLs = result.artifactURLs.map(\.standardizedFileURL)
        let actualPaths = actualURLs.map(\.path)
        let expectedPaths = expectedLayout.allURLs.map { $0.standardizedFileURL.path }
        let persistedCompletedAt = Date(
            timeIntervalSince1970: floor(completedAt.timeIntervalSince1970)
        )
        guard actualPaths == expectedPaths,
              Set(actualPaths).count == actualPaths.count,
              actualPaths.contains(expectedLayout.outputURL.standardizedFileURL.path),
              persistedCompletedAt.timeIntervalSinceReferenceDate.isFinite else {
            return nil
        }
        for url in actualURLs {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ), values.isRegularFile == true,
               let fileSize = values.fileSize,
               fileSize > 0,
               fileManager.fileExists(atPath: url.path) else {
                return nil
            }
        }
        return LibraryExportEvent(
            id: result.commitTransactionID,
            completedAt: persistedCompletedAt,
            primaryOutputPath: expectedLayout.outputURL.standardizedFileURL.path,
            artifactPaths: actualPaths,
            formatRawValue: format.rawValue,
            renderKind: trackingIdentity.renderKind,
            developRecipeSHA256: trackingIdentity.renderKind == .developed
                ? trackingIdentity.developRecipeSHA256
                : nil,
            defectRecipeSHA256: trackingIdentity.renderKind == .developed
                ? trackingIdentity.defectRecipeIdentity?.recipeSHA256
                : nil,
            sourceIdentity: sourceIdentity,
            exportRecipePresetID: exportRecipeIdentity?.presetID,
            exportRecipeSHA256: exportRecipeIdentity?.configurationSHA256
        )
    }
}
