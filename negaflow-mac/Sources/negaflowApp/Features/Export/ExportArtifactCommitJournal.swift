import Foundation
import Chromabase

struct ExportArtifactCommitReconciliationReport: Equatable, Sendable {
    var completedTransactionIDs: [UUID] = []
    var unresolvedTransactionIDs: [UUID] = []
    /// Catalog가 성공 event를 소유하지만 journal 산출물 무결성을 확인하지 못한 transaction.
    /// 정리만 남은 미커밋 transaction과 달리 library를 계속 열면 안 된다.
    var blockingTransactionIDs: [UUID] = []
    /// Catalog write가 실제로 시도됐지만 현재 catalog에서 성공 event를 찾지 못해
    /// 자동 보존/삭제를 결정할 수 없는 transaction이다.
    var ambiguousTransactionIDs: [UUID] = []
    /// Catalog 성공 증거가 있거나 commit 결과가 불명확해, final을 건드리지 않고 journal만
    /// 종료하는 사용자 복구를 제공할 수 있는 transaction이다.
    var preservableTransactionIDs: [UUID] = []
}

/// 다중 산출물 publish와 catalog event commit 사이의 crash window를 복구하는 중앙 journal.
/// 미커밋 산출물은 기록된 byte identity와 일치할 때만 제거한다.
enum ExportArtifactCommitJournal {
    private static let currentVersion = 2
    private static let supportedVersions = 1...currentVersion
    private static let maximumJournalBytes = 1_048_576
    private static let maximumPreparationBytes = 4_096
    private static let maximumArtifactCount = PrintPackageSettings.maximumPageCount
    private static let stagingOwnerFilename = ".negaflow-staging-owner"

    private enum TransactionState: String, Codable, Sendable {
        case published
        case catalogCommitIntent
        case catalogCommitAttempted
        case preserveArtifacts
        case rollbackIntent
        case committed
    }

    private enum RollbackQuarantineResolution {
        case ownedArtifactRemoved
        case externalArtifactRestored
        case unresolved
    }

    private enum StagingQuarantineResolution {
        case ownedDirectoryRemoved
        case externalDirectoryRestored
        case unresolved
    }

    private struct PreparationRecord: Codable, Equatable, Sendable {
        let version: Int
        let transactionID: UUID
        let stagingDirectoryPath: String
        let stagingOwnerIdentity: RenderManifest.SourceIdentity
    }

    private struct Artifact: Codable, Equatable, Sendable {
        let stagedPath: String
        let finalPath: String
        let identity: RenderManifest.SourceIdentity
        /// Staging과 final이 같은 볼륨 안에서 rename되었다는 소유권 증거다.
        /// nil은 구버전 journal이며, 이 경우 uncommitted final을 자동 삭제하지 않는다.
        let stagedFileIdentity: ExportArtifactFileIdentity?
    }

    private struct Record: Codable, Equatable, Sendable {
        let version: Int
        let transactionID: UUID
        let stagingDirectoryPath: String
        let stagingOwnerIdentity: RenderManifest.SourceIdentity?
        let artifacts: [Artifact]
        let state: TransactionState?

        var effectiveState: TransactionState { state ?? .published }
    }

    static func defaultDirectoryURL(
        fileManager: FileManager = .default,
        launchConfiguration: AppLaunchConfiguration? = .current
    ) -> URL {
        // UI 테스트는 실행마다 임시 루트를 새로 잡고 끝나면 지운다. 저널만 사용자
        // Application Support 에 남으면, 앞 테스트가 종료로 끊은 export transaction 이
        // 산출물 없는 상태로 남아 다음 실행을 복구 화면으로 막는다 — 루트 안에 둔다.
        if let uiTestRoot = launchConfiguration?.uiTestRoot {
            return uiTestRoot.appendingPathComponent("Library/ExportJournals", isDirectory: true)
        }
        return AppStorageRoot.applicationSupport(fileManager: fileManager)
            .appendingPathComponent("negaflow", isDirectory: true)
            .appendingPathComponent("export-journals", isDirectory: true)
    }

    /// 렌더 시작 전에 staging 소유권을 durable하게 남긴다. 비정상 종료 시 final 경로는
    /// 건드리지 않고 이 transaction의 임시 디렉터리만 정리한다.
    static func beginPreparation(
        transactionID: UUID,
        stagingDirectory: URL,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let standardizedStaging = stagingDirectory.standardizedFileURL
        guard validateStagingDirectory(
            standardizedStaging,
            transactionID: transactionID,
            requiresEmptyDirectory: true,
            fileManager: fileManager
        ) else {
            throw ChromabaseError.writeFailed("invalid export preparation directory")
        }
        let ownerURL = stagingOwnerURL(in: standardizedStaging)
        let ownerData = Data(UUID().uuidString.utf8)
        guard !fileManager.fileExists(atPath: ownerURL.path) else {
            throw ChromabaseError.writeFailed("duplicate export staging owner")
        }
        try ownerData.write(to: ownerURL, options: .atomic)
        let ownerIdentity = try RenderManifest.sourceIdentity(for: ownerURL)
        let record = PreparationRecord(
            version: currentVersion,
            transactionID: transactionID,
            stagingDirectoryPath: standardizedStaging.path,
            stagingOwnerIdentity: ownerIdentity
        )
        do {
            guard validate(record) else {
                throw ChromabaseError.writeFailed("invalid export preparation journal")
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = preparationURL(for: transactionID, in: directory)
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw ChromabaseError.writeFailed("duplicate export preparation transaction")
            }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(record)
            guard data.count <= maximumPreparationBytes else {
                throw ChromabaseError.writeFailed("export preparation journal is too large")
            }
            try data.write(to: destination, options: .atomic)
        } catch {
            _ = removePreparationStaging(record, fileManager: fileManager)
            throw error
        }
    }

    static func completePreparation(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let markerURL = preparationURL(for: transactionID, in: directory)
        guard fileManager.fileExists(atPath: markerURL.path) else { return }
        guard fileManager.fileExists(atPath: url(for: transactionID, in: directory).path) else {
            throw ChromabaseError.writeFailed("export preparation has not been promoted")
        }
        try fileManager.removeItem(at: markerURL)
    }

    static func cancelPreparation(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        let markerURL = preparationURL(for: transactionID, in: directory)
        guard !fileManager.fileExists(atPath: url(for: transactionID, in: directory).path) else {
            return
        }
        guard let record = loadValidPreparationRecord(
            at: markerURL,
            fileManager: fileManager
        ), removePreparationStaging(record, fileManager: fileManager) else { return }
        try? fileManager.removeItem(at: markerURL)
    }

    static func begin(
        transactionID: UUID,
        stagingDirectory: URL,
        stagedLayout: ExportArtifactLayout,
        finalLayout: ExportArtifactLayout,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        try begin(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedURLs: stagedLayout.allURLs,
            finalURLs: finalLayout.allURLs,
            in: directory,
            fileManager: fileManager
        )
    }

    static func begin(
        transactionID: UUID,
        stagingDirectory: URL,
        stagedURLs: [URL],
        finalURLs: [URL],
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let standardizedStaging = stagingDirectory.standardizedFileURL
        let usesOwnedStagingName = standardizedStaging.lastPathComponent
            == ".negaflow-export-\(transactionID.uuidString).tmp"
        guard !usesOwnedStagingName else {
            throw ChromabaseError.writeFailed("export preparation must be promoted")
        }
        let record = Record(
            version: currentVersion,
            transactionID: transactionID,
            stagingDirectoryPath: standardizedStaging.path,
            stagingOwnerIdentity: stagingOwnerIdentity(
                in: standardizedStaging,
                fileManager: fileManager
            ),
            artifacts: try makeArtifacts(stagedURLs: stagedURLs, finalURLs: finalURLs),
            state: .published
        )
        try write(record, in: directory, fileManager: fileManager)
    }

    static func promotePreparation(
        transactionID: UUID,
        stagingDirectory: URL,
        stagedLayout: ExportArtifactLayout,
        finalLayout: ExportArtifactLayout,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        try promotePreparation(
            transactionID: transactionID,
            stagingDirectory: stagingDirectory,
            stagedURLs: stagedLayout.allURLs,
            finalURLs: finalLayout.allURLs,
            in: directory,
            fileManager: fileManager
        )
    }

    static func promotePreparation(
        transactionID: UUID,
        stagingDirectory: URL,
        stagedURLs: [URL],
        finalURLs: [URL],
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let standardizedStaging = stagingDirectory.standardizedFileURL
        let markerURL = preparationURL(for: transactionID, in: directory)
        guard let preparation = loadValidPreparationRecord(
            at: markerURL,
            fileManager: fileManager
        ), preparation.stagingDirectoryPath == standardizedStaging.path,
              validateStagingDirectory(
                standardizedStaging,
                transactionID: transactionID,
                requiresEmptyDirectory: false,
                fileManager: fileManager
              ),
              stagingOwnerIdentity(in: standardizedStaging, fileManager: fileManager)
                == preparation.stagingOwnerIdentity else {
            throw ChromabaseError.writeFailed("export staging ownership changed")
        }
        let artifacts = try makeArtifacts(stagedURLs: stagedURLs, finalURLs: finalURLs)
        guard validateStagingDirectory(
            standardizedStaging,
            transactionID: transactionID,
            requiresEmptyDirectory: false,
            fileManager: fileManager
        ), stagingOwnerIdentity(in: standardizedStaging, fileManager: fileManager)
                == preparation.stagingOwnerIdentity else {
            throw ChromabaseError.writeFailed("export staging ownership changed")
        }
        let record = Record(
            version: currentVersion,
            transactionID: transactionID,
            stagingDirectoryPath: preparation.stagingDirectoryPath,
            stagingOwnerIdentity: preparation.stagingOwnerIdentity,
            artifacts: artifacts,
            state: .published
        )
        try write(record, in: directory, fileManager: fileManager)
        try? fileManager.removeItem(at: markerURL)
    }

    /// Catalog commit 직전에 출력 소유권을 다시 확인하고, crash 시 보존할 intent를 남긴다.
    static func markCatalogCommitIntent(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        afterArtifactIdentityRead: ((URL) throws -> Void)? = nil
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              record.effectiveState == .published,
              committedArtifactsAreIntact(
                record,
                fileManager: fileManager,
                afterInitialIdentityRead: afterArtifactIdentityRead
              ) else {
            throw ChromabaseError.writeFailed("export artifacts changed before catalog commit")
        }
        try replace(
            recordWithState(record, state: .catalogCommitIntent),
            at: journalURL,
            fileManager: fileManager
        )
    }

    /// 실제 catalog write 호출 직전에만 남긴다. 이 상태에서 crash가 나면 write가 반영됐을
    /// 가능성을 배제할 수 없으므로 catalog membership이 없어도 산출물을 자동 삭제하지 않는다.
    static func markCatalogCommitAttempted(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              record.effectiveState == .catalogCommitIntent,
              committedArtifactsAreIntact(record, fileManager: fileManager) else {
            throw ChromabaseError.writeFailed("export artifacts changed before catalog write")
        }
        try replace(
            recordWithState(record, state: .catalogCommitAttempted),
            at: journalURL,
            fileManager: fileManager
        )
    }

    /// Catalog event가 durable commit된 뒤 committed 상태를 먼저 durable하게 남기고 journal을
    /// 제거한다. 삭제가 실패해도 다음 복구는 catalog membership과 무관하게 산출물을 보존한다.
    static func complete(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        level: ExportVerificationLevel = .strict
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        try markCatalogCommitted(
            transactionID: transactionID,
            in: directory,
            fileManager: fileManager
        )
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              record.effectiveState == .committed,
              level.rehashesOnRecheck
                ? committedArtifactsAreIntact(record, fileManager: fileManager)
                : committedArtifactOwnershipIsIntact(record) else {
            throw ChromabaseError.writeFailed("committed export artifacts changed")
        }
        try fileManager.removeItem(at: journalURL)
    }

    static func markCatalogCommitted(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              [.catalogCommitIntent, .catalogCommitAttempted, .committed]
                .contains(record.effectiveState),
              committedArtifactOwnershipIsIntact(record) else {
            throw ChromabaseError.writeFailed("committed export artifacts changed")
        }
        if record.effectiveState != .committed {
            try replace(
                recordWithState(record, state: .committed),
                at: journalURL,
                fileManager: fileManager
            )
        }
    }

    /// Writer가 throw한 현재 transaction만 재정리한다. identity가 다른 경로는 삭제하지 않고
    /// journal을 남겨 다음 시작 시에도 fail-closed 상태를 보존한다.
    static func cancelUncommitted(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              record.effectiveState == .published,
              removeUncommittedArtifacts(record, fileManager: fileManager) else {
            return
        }
        try? fileManager.removeItem(at: journalURL)
    }

    /// Catalog commit이 명시적으로 실패한 intent transaction만 되돌린다.
    static func cancelCatalogCommitIntent(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        beforeRollback: (() throws -> Void)? = nil
    ) {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              [.catalogCommitIntent, .catalogCommitAttempted]
                .contains(record.effectiveState) else { return }
        do {
            try replace(
                recordWithState(record, state: .rollbackIntent),
                at: journalURL,
                fileManager: fileManager
            )
            try beforeRollback?()
        } catch {
            return
        }
        guard let rollbackRecord = loadValidRecord(at: journalURL, fileManager: fileManager),
              rollbackRecord.effectiveState == .rollbackIntent,
              removeUncommittedArtifacts(rollbackRecord, fileManager: fileManager) else { return }
        try? fileManager.removeItem(at: journalURL)
    }

    /// Journal에 기록된 staging 파일만 destination이 없을 때 원자적 no-clobber rename한다.
    static func publish(
        transactionID: UUID,
        stagedURL: URL,
        finalURL: URL,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        level: ExportVerificationLevel = .strict
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        // `artifact.identity` 는 promotePreparation 이 실제 해시로 남긴 durable 기록이다.
        // standard 는 그 기록을 만든 뒤 파일이 바뀌지 않았음을 stat identity(dev/inode/birthtime)로
        // 확인하고, strict 는 여기서도 전체 바이트를 다시 해시한다.
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager),
              record.effectiveState == .published,
              let artifact = record.artifacts.first(where: {
                  $0.stagedPath == stagedURL.standardizedFileURL.path
                      && $0.finalPath == finalURL.standardizedFileURL.path
              }),
              let expectedFileIdentity = artifact.stagedFileIdentity,
              ExportArtifactFileIdentityInspector.regularFile(at: stagedURL)
                == expectedFileIdentity,
              !level.rehashesOnRecheck
                || (try? RenderManifest.sourceIdentity(for: stagedURL)) == artifact.identity,
              !ExportArtifactFileIdentityInspector.entryExists(at: finalURL) else {
            throw ChromabaseError.writeFailed("export artifact ownership changed before publish")
        }
        try ExportArtifactFileOperations.moveExclusively(from: stagedURL, to: finalURL)
        guard ExportArtifactFileIdentityInspector.regularFile(at: finalURL)
                == expectedFileIdentity,
              !level.rehashesOnRecheck
                || (try? RenderManifest.sourceIdentity(for: finalURL)) == artifact.identity else {
            throw ChromabaseError.writeFailed("export artifact ownership changed during publish")
        }
    }

    static func reconcile(
        committedTransactionIDs: Set<UUID>,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        beforeRollbackClaim: ((URL) throws -> Void)? = nil,
        beforeStagingCleanupClaim: ((URL) throws -> Void)? = nil
    ) -> ExportArtifactCommitReconciliationReport {
        guard let journalURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ExportArtifactCommitReconciliationReport()
        }
        var report = ExportArtifactCommitReconciliationReport()
        // Promotion writes the publish journal before removing the preparation marker. Process
        // publish journals first so a crash in that overlap cannot delete staged artifacts early.
        for journalURL in journalURLs where journalURL.pathExtension == "plist" {
            guard let record = loadValidRecord(at: journalURL, fileManager: fileManager) else {
                continue
            }
            let resolved: Bool
            let catalogContainsTransaction = committedTransactionIDs.contains(record.transactionID)
            let blocksLibraryIfUnresolved: Bool
            let offersPreserveRecovery: Bool
            switch record.effectiveState {
            case .committed:
                blocksLibraryIfUnresolved = true
                offersPreserveRecovery = true
                resolved = committedArtifactsAreIntact(record, fileManager: fileManager)
                    && removeStagingDirectory(
                        record,
                        fileManager: fileManager,
                        beforeClaim: beforeStagingCleanupClaim
                    )
            case .catalogCommitIntent:
                blocksLibraryIfUnresolved = catalogContainsTransaction
                offersPreserveRecovery = catalogContainsTransaction
                if catalogContainsTransaction {
                    resolved = committedArtifactsAreIntact(record, fileManager: fileManager)
                        && removeStagingDirectory(
                            record,
                            fileManager: fileManager,
                            beforeClaim: beforeStagingCleanupClaim
                        )
                } else {
                    resolved = resumeRollback(
                        record,
                        journalURL: journalURL,
                        fileManager: fileManager,
                        beforeRollbackClaim: beforeRollbackClaim,
                        beforeStagingCleanupClaim: beforeStagingCleanupClaim
                    )
                }
            case .catalogCommitAttempted:
                offersPreserveRecovery = true
                if catalogContainsTransaction {
                    blocksLibraryIfUnresolved = true
                    resolved = committedArtifactsAreIntact(record, fileManager: fileManager)
                        && removeStagingDirectory(
                            record,
                            fileManager: fileManager,
                            beforeClaim: beforeStagingCleanupClaim
                        )
                } else {
                    // Catalog commit 결과가 indeterminate인 상태다. 이전 backup이 열린 경우도
                    // membership이 없을 수 있으므로 사용자 선택 없이 산출물을 삭제하지 않는다.
                    blocksLibraryIfUnresolved = true
                    resolved = false
                    appendUnique(record.transactionID, to: &report.ambiguousTransactionIDs)
                }
            case .preserveArtifacts:
                // 사용자가 final 파일 보존을 선택한 durable 상태다. final의 현재 byte나
                // ownership은 더 이상 판단하지 않고 app-owned staging만 정리한다.
                blocksLibraryIfUnresolved = false
                offersPreserveRecovery = false
                resolved = removeStagingDirectory(
                    record,
                    fileManager: fileManager,
                    beforeClaim: beforeStagingCleanupClaim
                )
            case .rollbackIntent:
                blocksLibraryIfUnresolved = false
                offersPreserveRecovery = false
                resolved = removeUncommittedArtifacts(
                    record,
                    fileManager: fileManager,
                    beforeRollbackClaim: beforeRollbackClaim,
                    beforeStagingCleanupClaim: beforeStagingCleanupClaim
                )
            case .published:
                blocksLibraryIfUnresolved = catalogContainsTransaction
                offersPreserveRecovery = catalogContainsTransaction
                if catalogContainsTransaction {
                    resolved = committedArtifactsAreIntact(record, fileManager: fileManager)
                        && removeStagingDirectory(
                            record,
                            fileManager: fileManager,
                            beforeClaim: beforeStagingCleanupClaim
                        )
                } else {
                    resolved = removeUncommittedArtifacts(
                        record,
                        fileManager: fileManager,
                        beforeRollbackClaim: beforeRollbackClaim,
                        beforeStagingCleanupClaim: beforeStagingCleanupClaim
                    )
                }
            }
            if resolved {
                do {
                    try fileManager.removeItem(at: journalURL)
                    appendUnique(record.transactionID, to: &report.completedTransactionIDs)
                } catch {
                    appendUnique(record.transactionID, to: &report.unresolvedTransactionIDs)
                    if offersPreserveRecovery {
                        appendUnique(record.transactionID, to: &report.preservableTransactionIDs)
                    }
                }
            } else {
                appendUnique(record.transactionID, to: &report.unresolvedTransactionIDs)
                if offersPreserveRecovery {
                    appendUnique(record.transactionID, to: &report.preservableTransactionIDs)
                }
                if blocksLibraryIfUnresolved {
                    appendUnique(record.transactionID, to: &report.blockingTransactionIDs)
                }
            }
        }
        for markerURL in journalURLs where markerURL.pathExtension == "prep" {
            guard let record = loadValidPreparationRecord(
                at: markerURL,
                fileManager: fileManager
            ) else { continue }
            guard !fileManager.fileExists(
                atPath: url(for: record.transactionID, in: directory).path
            ) else {
                appendUnique(record.transactionID, to: &report.unresolvedTransactionIDs)
                continue
            }
            if removePreparationStaging(
                record,
                fileManager: fileManager,
                beforeClaim: beforeStagingCleanupClaim
            ) {
                do {
                    try fileManager.removeItem(at: markerURL)
                    appendUnique(record.transactionID, to: &report.completedTransactionIDs)
                } catch {
                    appendUnique(record.transactionID, to: &report.unresolvedTransactionIDs)
                }
            } else {
                appendUnique(record.transactionID, to: &report.unresolvedTransactionIDs)
            }
        }
        return report
    }

    /// Indeterminate catalog commit의 산출물을 보존하기로 사용자가 선택했을 때 final은
    /// 더 이상 검증하거나 건드리지 않는 durable 상태를 먼저 남긴 뒤 journal을 종료한다.
    static func resolveAmbiguousCommitPreservingArtifacts(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        afterPreserveIntent: (() throws -> Void)? = nil
    ) throws {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager) else {
            throw ChromabaseError.writeFailed("ambiguous export transaction changed")
        }
        let preserveRecord: Record
        switch record.effectiveState {
        case .published, .catalogCommitIntent, .catalogCommitAttempted, .committed:
            preserveRecord = recordWithState(record, state: .preserveArtifacts)
            try replace(preserveRecord, at: journalURL, fileManager: fileManager)
            try afterPreserveIntent?()
        case .preserveArtifacts:
            preserveRecord = record
        case .rollbackIntent:
            throw ChromabaseError.writeFailed("ambiguous export transaction changed")
        }
        guard removeStagingDirectory(preserveRecord, fileManager: fileManager) else {
            throw ChromabaseError.writeFailed("ambiguous export staging cleanup failed")
        }
        try fileManager.removeItem(at: journalURL)
    }

    /// Indeterminate catalog commit의 산출물을 삭제하기로 사용자가 선택했을 때 journal이
    /// 소유한 inode와 byte identity가 일치하는 파일만 rollback한다.
    @discardableResult
    static func resolveAmbiguousCommitDeletingOwnedArtifacts(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default,
        beforeRollback: (() throws -> Void)? = nil
    ) -> Bool {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager) else {
            return false
        }
        let rollbackRecord: Record
        switch record.effectiveState {
        case .catalogCommitAttempted:
            rollbackRecord = recordWithState(record, state: .rollbackIntent)
            do {
                try replace(rollbackRecord, at: journalURL, fileManager: fileManager)
                try beforeRollback?()
            } catch {
                return false
            }
        case .rollbackIntent:
            rollbackRecord = record
        case .published, .catalogCommitIntent, .preserveArtifacts, .committed:
            return false
        }
        guard removeUncommittedArtifacts(rollbackRecord, fileManager: fileManager) else {
            return false
        }
        do {
            try fileManager.removeItem(at: journalURL)
            return true
        } catch {
            return false
        }
    }

    private static func resumeRollback(
        _ record: Record,
        journalURL: URL,
        fileManager: FileManager,
        beforeRollbackClaim: ((URL) throws -> Void)?,
        beforeStagingCleanupClaim: ((URL) throws -> Void)?
    ) -> Bool {
        let rollbackRecord = recordWithState(record, state: .rollbackIntent)
        do {
            try replace(rollbackRecord, at: journalURL, fileManager: fileManager)
        } catch {
            return false
        }
        return removeUncommittedArtifacts(
            rollbackRecord,
            fileManager: fileManager,
            beforeRollbackClaim: beforeRollbackClaim,
            beforeStagingCleanupClaim: beforeStagingCleanupClaim
        )
    }

    static func journalExists(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: url(for: transactionID, in: directory).path)
    }

    static func preparationExists(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: preparationURL(for: transactionID, in: directory).path)
    }

    @discardableResult
    static func cleanupOwnedStaging(
        transactionID: UUID,
        in directory: URL = defaultDirectoryURL(),
        fileManager: FileManager = .default
    ) -> Bool {
        let journalURL = url(for: transactionID, in: directory)
        guard let record = loadValidRecord(at: journalURL, fileManager: fileManager) else {
            return false
        }
        return removeStagingDirectory(record, fileManager: fileManager)
    }

    private static func url(for transactionID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(transactionID.uuidString).plist")
    }

    private static func preparationURL(for transactionID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(transactionID.uuidString).prep")
    }

    private static func loadValidPreparationRecord(
        at url: URL,
        fileManager: FileManager
    ) -> PreparationRecord? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumPreparationBytes,
              let transactionID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= maximumPreparationBytes,
              let record = try? PropertyListDecoder().decode(PreparationRecord.self, from: data),
              record.transactionID == transactionID,
              validate(record) else { return nil }
        return record
    }

    private static func loadValidRecord(
        at url: URL,
        fileManager: FileManager
    ) -> Record? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumJournalBytes,
              let transactionID = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              data.count <= maximumJournalBytes,
              let record = try? PropertyListDecoder().decode(Record.self, from: data),
              record.transactionID == transactionID,
              validate(record) else {
            return nil
        }
        return record
    }

    private static func makeArtifacts(
        stagedURLs: [URL],
        finalURLs: [URL]
    ) throws -> [Artifact] {
        guard !stagedURLs.isEmpty,
              stagedURLs.count == finalURLs.count,
              stagedURLs.count <= maximumArtifactCount else {
            throw ChromabaseError.writeFailed("invalid export journal artifact count")
        }
        return try zip(stagedURLs, finalURLs).map { stagedURL, finalURL in
            guard let fileIdentityBefore = ExportArtifactFileIdentityInspector.regularFile(
                at: stagedURL
            ) else {
                throw ChromabaseError.writeFailed("invalid staged export artifact")
            }
            let identity = try RenderManifest.sourceIdentity(for: stagedURL)
            guard ExportArtifactFileIdentityInspector.regularFile(at: stagedURL)
                    == fileIdentityBefore else {
                throw ChromabaseError.writeFailed("staged export artifact changed")
            }
            return Artifact(
                stagedPath: stagedURL.standardizedFileURL.path,
                finalPath: finalURL.standardizedFileURL.path,
                identity: identity,
                stagedFileIdentity: fileIdentityBefore
            )
        }
    }

    private static func write(
        _ record: Record,
        in directory: URL,
        fileManager: FileManager
    ) throws {
        guard validate(record) else {
            throw ChromabaseError.writeFailed("invalid export journal layout")
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = url(for: record.transactionID, in: directory)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ChromabaseError.writeFailed("duplicate export journal transaction")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        guard data.count <= maximumJournalBytes else {
            throw ChromabaseError.writeFailed("export journal is too large")
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func replace(
        _ record: Record,
        at destination: URL,
        fileManager: FileManager
    ) throws {
        guard validate(record), fileManager.fileExists(atPath: destination.path) else {
            throw ChromabaseError.writeFailed("invalid export journal transition")
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(record)
        guard data.count <= maximumJournalBytes else {
            throw ChromabaseError.writeFailed("export journal is too large")
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func recordWithState(
        _ record: Record,
        state: TransactionState
    ) -> Record {
        Record(
            version: record.version,
            transactionID: record.transactionID,
            stagingDirectoryPath: record.stagingDirectoryPath,
            stagingOwnerIdentity: record.stagingOwnerIdentity,
            artifacts: record.artifacts,
            state: state
        )
    }

    private static func validate(_ record: Record) -> Bool {
        let stagingDirectory = URL(fileURLWithPath: record.stagingDirectoryPath, isDirectory: true)
            .standardizedFileURL
        let stagingName = stagingDirectory.lastPathComponent
        guard supportedVersions.contains(record.version),
              stagingDirectory.path.hasPrefix("/"),
              stagingName.hasPrefix(".negaflow-export-"),
              stagingName.hasSuffix(".tmp"),
              (stagingName != ".negaflow-export-\(record.transactionID.uuidString).tmp"
                || record.stagingOwnerIdentity != nil),
              (record.stagingOwnerIdentity.map { valid(identity: $0) } ?? true),
              !record.artifacts.isEmpty,
              record.artifacts.count <= maximumArtifactCount else {
            return false
        }
        var stagedPaths = Set<String>()
        var finalPaths = Set<String>()
        for artifact in record.artifacts {
            let stagedURL = URL(fileURLWithPath: artifact.stagedPath).standardizedFileURL
            let finalURL = URL(fileURLWithPath: artifact.finalPath).standardizedFileURL
            guard stagedURL.deletingLastPathComponent() == stagingDirectory,
                  finalURL.deletingLastPathComponent() == stagingDirectory.deletingLastPathComponent(),
                  stagedURL.lastPathComponent == finalURL.lastPathComponent,
                  stagedPaths.insert(stagedURL.path).inserted,
                  finalPaths.insert(finalURL.path).inserted,
                  valid(identity: artifact.identity),
                  artifact.stagedFileIdentity.map(\.isValid) ?? true else {
                return false
            }
        }
        return true
    }

    private static func validate(_ record: PreparationRecord) -> Bool {
        let stagingDirectory = URL(fileURLWithPath: record.stagingDirectoryPath, isDirectory: true)
            .standardizedFileURL
        return supportedVersions.contains(record.version)
            && stagingDirectory.path.hasPrefix("/")
            && stagingDirectory.lastPathComponent
                == ".negaflow-export-\(record.transactionID.uuidString).tmp"
            && stagingDirectory.deletingLastPathComponent().path != "/"
            && valid(identity: record.stagingOwnerIdentity)
    }

    private static func valid(identity: RenderManifest.SourceIdentity) -> Bool {
        identity.byteCount > 0
            && identity.sha256.utf8.count == 64
            && identity.sha256.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
    }

    private static func committedArtifactsAreIntact(
        _ record: Record,
        fileManager: FileManager,
        afterInitialIdentityRead: ((URL) throws -> Void)? = nil
    ) -> Bool {
        record.artifacts.allSatisfy { artifact in
            let finalURL = URL(fileURLWithPath: artifact.finalPath)
            guard let fileIdentityBefore = ExportArtifactFileIdentityInspector.regularFile(
                at: finalURL
            ), artifact.stagedFileIdentity.map({ $0 == fileIdentityBefore }) ?? true else {
                return false
            }
            do {
                try afterInitialIdentityRead?(finalURL)
            } catch {
                return false
            }
            guard let identity = try? RenderManifest.sourceIdentity(for: finalURL),
                  identity == artifact.identity,
                  let fileIdentityAfter = ExportArtifactFileIdentityInspector.regularFile(
                    at: finalURL
                  ) else { return false }
            return fileIdentityAfter == fileIdentityBefore
                && (artifact.stagedFileIdentity.map { $0 == fileIdentityAfter } ?? true)
        }
    }

    /// Catalog commit 성공 직후 MainActor에서 yield 없이 committed 상태를 남길 때 사용하는
    /// 빠른 소유권 확인이다. 전체 byte hash는 이어지는 complete/reconcile에서 다시 검증한다.
    private static func committedArtifactOwnershipIsIntact(_ record: Record) -> Bool {
        record.artifacts.allSatisfy { artifact in
            guard let expectedFileIdentity = artifact.stagedFileIdentity else { return false }
            return ExportArtifactFileIdentityInspector.regularFile(
                at: URL(fileURLWithPath: artifact.finalPath)
            ) == expectedFileIdentity
        }
    }

    private static func removeUncommittedArtifacts(
        _ record: Record,
        fileManager: FileManager,
        beforeRollbackClaim: ((URL) throws -> Void)? = nil,
        beforeStagingCleanupClaim: ((URL) throws -> Void)? = nil
    ) -> Bool {
        var succeeded = true
        for artifactIndex in record.artifacts.indices.reversed() {
            if !removeUncommittedArtifact(
                record.artifacts[artifactIndex],
                artifactIndex: artifactIndex,
                transactionID: record.transactionID,
                beforeRollbackClaim: beforeRollbackClaim
            ) {
                succeeded = false
            }
        }
        return removeStagingDirectory(
            record,
            fileManager: fileManager,
            beforeClaim: beforeStagingCleanupClaim
        ) && succeeded
    }

    /// 최종 경로를 직접 unlink하지 않는다. 검증한 directory entry를 transaction별 격리
    /// 경로로 원자 이동한 뒤 inode와 byte identity를 다시 확인해 외부 교체 파일을 보존한다.
    private static func removeUncommittedArtifact(
        _ artifact: Artifact,
        artifactIndex: Int,
        transactionID: UUID,
        beforeRollbackClaim: ((URL) throws -> Void)?
    ) -> Bool {
        guard let expectedFileIdentity = artifact.stagedFileIdentity else { return false }
        let stagedURL = URL(fileURLWithPath: artifact.stagedPath)
        let finalURL = URL(fileURLWithPath: artifact.finalPath)
        let quarantineURL = rollbackQuarantineURL(
            for: finalURL,
            transactionID: transactionID,
            artifactIndex: artifactIndex
        )
        guard ExportArtifactFileIdentityInspector.entryExists(at: finalURL)
                || ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL) else {
            return true
        }
        guard !ExportArtifactFileIdentityInspector.entryExists(at: stagedURL) else { return false }

        if ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL) {
            switch resolveRollbackQuarantine(
                quarantineURL,
                finalURL: finalURL,
                artifact: artifact,
                expectedFileIdentity: expectedFileIdentity
            ) {
            case .ownedArtifactRemoved:
                guard ExportArtifactFileIdentityInspector.entryExists(at: finalURL) else {
                    return true
                }
                guard artifactIsIntact(
                    at: finalURL,
                    artifact: artifact,
                    expectedFileIdentity: expectedFileIdentity
                ) else {
                    return true
                }
            case .externalArtifactRestored, .unresolved:
                return false
            }
        }

        guard ExportArtifactFileIdentityInspector.entryExists(at: finalURL) else { return true }
        guard artifactIsIntact(
            at: finalURL,
            artifact: artifact,
            expectedFileIdentity: expectedFileIdentity
        ) else { return false }
        do {
            try beforeRollbackClaim?(finalURL)
            try ExportArtifactFileOperations.moveExclusively(
                from: finalURL,
                to: quarantineURL
            )
        } catch {
            return false
        }
        return resolveRollbackQuarantine(
            quarantineURL,
            finalURL: finalURL,
            artifact: artifact,
            expectedFileIdentity: expectedFileIdentity
        ) == .ownedArtifactRemoved
    }

    private static func resolveRollbackQuarantine(
        _ quarantineURL: URL,
        finalURL: URL,
        artifact: Artifact,
        expectedFileIdentity: ExportArtifactFileIdentity
    ) -> RollbackQuarantineResolution {
        guard ExportArtifactFileIdentityInspector.regularFile(at: quarantineURL) != nil else {
            return .unresolved
        }
        if artifactIsIntact(
            at: quarantineURL,
            artifact: artifact,
            expectedFileIdentity: expectedFileIdentity
        ) {
            do {
                try ExportArtifactFileOperations.unlinkFile(at: quarantineURL)
                return ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL)
                    ? .unresolved
                    : .ownedArtifactRemoved
            } catch {
                return .unresolved
            }
        }
        guard !ExportArtifactFileIdentityInspector.entryExists(at: finalURL) else {
            return .unresolved
        }
        do {
            try ExportArtifactFileOperations.moveExclusively(
                from: quarantineURL,
                to: finalURL
            )
            return .externalArtifactRestored
        } catch {
            return .unresolved
        }
    }

    private static func artifactIsIntact(
        at url: URL,
        artifact: Artifact,
        expectedFileIdentity: ExportArtifactFileIdentity
    ) -> Bool {
        guard ExportArtifactFileIdentityInspector.regularFile(at: url)
                == expectedFileIdentity,
              let identity = try? RenderManifest.sourceIdentity(for: url),
              identity == artifact.identity else { return false }
        return ExportArtifactFileIdentityInspector.regularFile(at: url)
            == expectedFileIdentity
    }

    private static func rollbackQuarantineURL(
        for finalURL: URL,
        transactionID: UUID,
        artifactIndex: Int
    ) -> URL {
        finalURL.deletingLastPathComponent().appendingPathComponent(
            ".negaflow-rollback-\(transactionID.uuidString)-\(artifactIndex).tmp",
            isDirectory: false
        )
    }

    private static func removeStagingDirectory(
        _ record: Record,
        fileManager: FileManager,
        beforeClaim: ((URL) throws -> Void)? = nil
    ) -> Bool {
        let stagingURL = URL(fileURLWithPath: record.stagingDirectoryPath, isDirectory: true)
        guard let expectedOwner = record.stagingOwnerIdentity,
              validStagingPath(stagingURL, transactionID: record.transactionID) else { return false }
        return removeOwnedStagingDirectory(
            stagingURL,
            transactionID: record.transactionID,
            expectedOwner: expectedOwner,
            fileManager: fileManager,
            beforeClaim: beforeClaim
        )
    }

    private static func removePreparationStaging(
        _ record: PreparationRecord,
        fileManager: FileManager,
        beforeClaim: ((URL) throws -> Void)? = nil
    ) -> Bool {
        let stagingURL = URL(fileURLWithPath: record.stagingDirectoryPath, isDirectory: true)
        guard validStagingPath(stagingURL, transactionID: record.transactionID) else { return false }
        return removeOwnedStagingDirectory(
            stagingURL,
            transactionID: record.transactionID,
            expectedOwner: record.stagingOwnerIdentity,
            fileManager: fileManager,
            beforeClaim: beforeClaim
        )
    }

    /// 검증한 staging 경로를 곧바로 재귀 삭제하지 않고 먼저 transaction별 격리 경로로
    /// 원자 이동한다. 경로가 교체됐으면 원래 위치로 no-clobber 복원하고 journal을 남긴다.
    private static func removeOwnedStagingDirectory(
        _ stagingURL: URL,
        transactionID: UUID,
        expectedOwner: RenderManifest.SourceIdentity,
        fileManager: FileManager,
        beforeClaim: ((URL) throws -> Void)?
    ) -> Bool {
        let quarantineURL = stagingCleanupQuarantineURL(
            for: stagingURL,
            transactionID: transactionID
        )
        if ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL) {
            switch resolveStagingQuarantine(
                quarantineURL,
                stagingURL: stagingURL,
                expectedOwner: expectedOwner,
                fileManager: fileManager
            ) {
            case .ownedDirectoryRemoved:
                guard ExportArtifactFileIdentityInspector.entryExists(at: stagingURL) else {
                    return true
                }
                guard ownedStagingDirectoryIsIntact(
                    stagingURL,
                    expectedOwner: expectedOwner,
                    fileManager: fileManager
                ) else {
                    return true
                }
            case .externalDirectoryRestored, .unresolved:
                return false
            }
        }

        guard ExportArtifactFileIdentityInspector.entryExists(at: stagingURL) else { return true }
        guard ownedStagingDirectoryIsIntact(
            stagingURL,
            expectedOwner: expectedOwner,
            fileManager: fileManager
        ) else { return false }
        do {
            try beforeClaim?(stagingURL)
            try ExportArtifactFileOperations.moveExclusively(
                from: stagingURL,
                to: quarantineURL
            )
        } catch {
            return false
        }
        return resolveStagingQuarantine(
            quarantineURL,
            stagingURL: stagingURL,
            expectedOwner: expectedOwner,
            fileManager: fileManager
        ) == .ownedDirectoryRemoved
    }

    private static func resolveStagingQuarantine(
        _ quarantineURL: URL,
        stagingURL: URL,
        expectedOwner: RenderManifest.SourceIdentity,
        fileManager: FileManager
    ) -> StagingQuarantineResolution {
        guard ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL) else {
            return .ownedDirectoryRemoved
        }
        if ownedStagingDirectoryIsIntact(
            quarantineURL,
            expectedOwner: expectedOwner,
            fileManager: fileManager
        ) {
            do {
                try fileManager.removeItem(at: quarantineURL)
                return ExportArtifactFileIdentityInspector.entryExists(at: quarantineURL)
                    ? .unresolved
                    : .ownedDirectoryRemoved
            } catch {
                return .unresolved
            }
        }
        guard !ExportArtifactFileIdentityInspector.entryExists(at: stagingURL) else {
            return .unresolved
        }
        do {
            try ExportArtifactFileOperations.moveExclusively(
                from: quarantineURL,
                to: stagingURL
            )
            return .externalDirectoryRestored
        } catch {
            return .unresolved
        }
    }

    private static func ownedStagingDirectoryIsIntact(
        _ directory: URL,
        expectedOwner: RenderManifest.SourceIdentity,
        fileManager: FileManager
    ) -> Bool {
        guard let valuesBefore = try? directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), valuesBefore.isDirectory == true,
              valuesBefore.isSymbolicLink != true,
              stagingOwnerIdentity(in: directory, fileManager: fileManager) == expectedOwner,
              let valuesAfter = try? directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ), valuesAfter.isDirectory == true,
              valuesAfter.isSymbolicLink != true else { return false }
        return stagingOwnerIdentity(in: directory, fileManager: fileManager) == expectedOwner
    }

    private static func stagingCleanupQuarantineURL(
        for stagingURL: URL,
        transactionID: UUID
    ) -> URL {
        stagingURL.deletingLastPathComponent().appendingPathComponent(
            ".negaflow-staging-cleanup-\(transactionID.uuidString).tmp",
            isDirectory: true
        )
    }

    private static func appendUnique(_ id: UUID, to values: inout [UUID]) {
        if !values.contains(id) { values.append(id) }
    }

    private static func validateStagingDirectory(
        _ directory: URL,
        transactionID: UUID,
        requiresEmptyDirectory: Bool,
        fileManager: FileManager
    ) -> Bool {
        let standardized = directory.standardizedFileURL
        guard standardized.lastPathComponent
                == ".negaflow-export-\(transactionID.uuidString).tmp",
              standardized.deletingLastPathComponent().path != "/",
              let values = try? standardized.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ), values.isDirectory == true,
              values.isSymbolicLink != true else { return false }
        if requiresEmptyDirectory {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: standardized,
                includingPropertiesForKeys: nil,
                options: []
            ), contents.isEmpty else { return false }
        }
        return true
    }

    private static func validStagingPath(_ directory: URL, transactionID: UUID) -> Bool {
        let standardized = directory.standardizedFileURL
        return standardized.lastPathComponent
            == ".negaflow-export-\(transactionID.uuidString).tmp"
            && standardized.deletingLastPathComponent().path != "/"
    }

    private static func stagingOwnerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(stagingOwnerFilename, isDirectory: false)
    }

    private static func stagingOwnerIdentity(
        in directory: URL,
        fileManager: FileManager
    ) -> RenderManifest.SourceIdentity? {
        let ownerURL = stagingOwnerURL(in: directory.standardizedFileURL)
        guard let values = try? ownerURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ), values.isRegularFile == true,
              values.isSymbolicLink != true else { return nil }
        return try? RenderManifest.sourceIdentity(for: ownerURL)
    }
}
