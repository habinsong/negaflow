import Foundation

extension ExportArtifactCommitJournal {
    static func markCatalogCommitIntentAsync(transactionID: UUID) async throws {
        try await Task.detached(priority: .userInitiated) {
            try markCatalogCommitIntent(transactionID: transactionID)
        }.value
    }

    static func markCatalogCommitAttemptedAsync(transactionID: UUID) async throws {
        try await Task.detached(priority: .userInitiated) {
            try markCatalogCommitAttempted(transactionID: transactionID)
        }.value
    }

    static func completeAsync(
        transactionID: UUID,
        level: ExportVerificationLevel = .strict
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try complete(transactionID: transactionID, level: level)
        }.value
    }

    static func cancelUncommittedAsync(transactionID: UUID) async {
        await Task.detached(priority: .userInitiated) {
            cancelUncommitted(transactionID: transactionID)
        }.value
    }

    static func cancelCatalogCommitIntentAsync(transactionID: UUID) async {
        await Task.detached(priority: .userInitiated) {
            cancelCatalogCommitIntent(transactionID: transactionID)
        }.value
    }
}
