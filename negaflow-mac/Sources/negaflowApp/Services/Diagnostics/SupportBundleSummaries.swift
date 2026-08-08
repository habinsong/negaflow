import Foundation

enum SupportBundleSummaries {
    static func catalog(
        lifecycle: String,
        blockReason: String?,
        catalog: LibraryCatalog?,
        fallbackFrameCount: Int,
        fallbackRollCount: Int,
        defectDirectory: URL
    ) -> SupportBundleCatalogSummary {
        let report = catalog.map {
            LibraryCatalogHealthInspector.inspect(
                $0,
                defectDirectory: defectDirectory
            )
        }
        let grouped = Dictionary(grouping: report?.issues ?? []) {
            "\($0.code.rawValue)|\($0.severity.rawValue)"
        }
        let issues = grouped.map { key, values -> SupportBundleCatalogIssueCount in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return SupportBundleCatalogIssueCount(
                code: parts[0],
                severity: parts[1],
                count: values.count
            )
        }.sorted {
            ($0.severity, $0.code) < ($1.severity, $1.code)
        }
        return SupportBundleCatalogSummary(
            lifecycle: lifecycle,
            blockReason: blockReason,
            snapshotAvailable: catalog != nil,
            catalogVersion: report?.catalogVersion ?? LibraryCatalog.currentVersion,
            frameCount: report?.frameCount ?? fallbackFrameCount,
            rollCount: report?.rollCount ?? fallbackRollCount,
            folderCount: report?.folderCount ?? 0,
            warningCount: report?.warningCount ?? 0,
            errorCount: report?.errorCount ?? 0,
            issues: issues
        )
    }

    static func generations(
        in backupDirectory: URL
    ) -> [SupportBundleBackupGeneration] {
        let generations = (try? LibraryBackupStore.generations(in: backupDirectory)) ?? []
        return generations.map {
            SupportBundleBackupGeneration(
                sequence: $0.sequence,
                createdAt: $0.createdAt,
                state: $0.state.rawValue,
                frameCount: $0.frameCount,
                defectRecipeCount: $0.defectRecipeCount,
                catalogVersion: $0.catalogVersion
            )
        }
    }
}
