import Foundation
import Chromabase

extension ExportFrameWriter {
    static func validateDestinationsAreAvailable(
        _ layout: ExportArtifactLayout,
        protectedSource: URL,
        fileManager: FileManager
    ) throws {
        try ExportDestinationSafety.validateDistinct(
            protectedSources: [protectedSource],
            outputURLs: layout.allURLs,
            fileManager: fileManager
        )
        guard layout.standardizedPaths.count == layout.allURLs.count else {
            throw ChromabaseError.writeFailed("export artifact paths overlap: \(layout.outputURL.path)")
        }
        for url in layout.allURLs where fileManager.fileExists(atPath: url.path) {
            throw ChromabaseError.writeFailed("export destination already exists: \(url.path)")
        }
    }

    static func validateStagedArtifacts(
        _ layout: ExportArtifactLayout,
        fileManager: FileManager
    ) throws {
        for url in layout.allURLs {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size > 0 else {
                throw ChromabaseError.writeFailed("invalid staged export artifact: \(url.path)")
            }
        }
    }

    static func commit(
        transactionID: UUID,
        stagedLayout: ExportArtifactLayout,
        finalLayout: ExportArtifactLayout,
        fileManager: FileManager,
        level: ExportVerificationLevel = .strict
    ) throws {
        for (stagedURL, finalURL) in zip(stagedLayout.allURLs, finalLayout.allURLs) {
            try ExportArtifactCommitJournal.publish(
                transactionID: transactionID,
                stagedURL: stagedURL,
                finalURL: finalURL,
                fileManager: fileManager,
                level: level
            )
        }
    }
}
