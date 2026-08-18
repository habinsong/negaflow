namespace Negaflow.Catalog;

/// <summary>
/// commit 이 실패했을 때 직전 상태로 되돌리는 일과, 되돌리지 못한 흔적을 남기는 일입니다.
/// 되돌림이 또 실패하면 표식을 남겨 다음 세션이 mutation 을 막습니다.
/// </summary>
internal static class CatalogCommitRollback
{
    internal static bool HasBlockingArtifactWhenPrimaryMissing(StorageRootSet roots) =>
        File.Exists(roots.CatalogBackupPath) ||
        Directory.Exists(roots.CatalogBackupPath) ||
        CatalogCommitFiles.CatalogCompanionPaths(roots).Any(path =>
            File.Exists(path) || Directory.Exists(path)) ||
        HasUnresolvedRollbackArtifact(roots);

    /// <summary>
    /// restore 직전 primary가 없었던 경우에만 사용합니다. 방금 적용한 exact snapshot인지 다시
    /// 확인한 뒤 primary를 제거해 catalog+sidecar rollback을 같은 상태로 맞춥니다.
    /// </summary>
    internal static bool RemovePrimaryIfMatches(
        CatalogSnapshot expected,
        StorageRootSet roots)
    {
        try
        {
            CatalogReadResult current = SqliteCatalogStore.Read(roots.CatalogPath);
            if (current.Snapshot is not { } snapshot ||
                !CatalogCommitVerifier.SnapshotsMatch(expected, snapshot))
            {
                return false;
            }
            foreach (string companion in CatalogCommitFiles.CatalogCompanionPaths(roots))
            {
                if (Directory.Exists(companion) ||
                    StoragePathPolicy.IsExistingReparsePoint(companion))
                {
                    return false;
                }
                if (File.Exists(companion))
                {
                    File.Delete(companion);
                }
            }
            if (Directory.Exists(roots.CatalogPath) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.CatalogPath))
            {
                return false;
            }
            File.Delete(roots.CatalogPath);
            return SqliteCatalogStore.Read(roots.CatalogPath).Error ==
                CatalogStoreError.NotFound;
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }

    internal static CatalogStoreError CreatePrimarySnapshot(
        StorageRootSet roots,
        CatalogSnapshot expectedPrevious,
        out CatalogPrimarySnapshot snapshot)
    {
        string rollbackPath = Path.Combine(
            roots.LibraryRoot,
            $".catalog-{Guid.NewGuid():N}.rollback");
        CatalogStoreError copied = CatalogCommitFiles.CopyAndPromote(
            roots.CatalogPath,
            rollbackPath,
            roots.LibraryRoot);
        snapshot = copied == CatalogStoreError.None
            ? new CatalogPrimarySnapshot(true, rollbackPath)
            : new CatalogPrimarySnapshot(true, null);
        if (copied == CatalogStoreError.None)
        {
            CatalogReadResult captured = SqliteCatalogStore.Read(rollbackPath);
            if (captured.Snapshot is not { } capturedSnapshot ||
                !CatalogCommitVerifier.SnapshotsMatch(expectedPrevious, capturedSnapshot))
            {
                CatalogCommitFiles.TryDelete(rollbackPath);
                snapshot = new CatalogPrimarySnapshot(true, null);
                return CatalogStoreError.ReadbackFailed;
            }
        }
        return copied;
    }

    internal static CatalogStoreError PreservePreviousPrimary(
        string previousPrimaryPath,
        StorageRootSet roots)
    {
        if (!CatalogRecovery.IsValidCatalogSource(previousPrimaryPath))
        {
            return CatalogStoreError.IoFailure;
        }
        return CatalogCommitFiles.CopyAndPromote(
            previousPrimaryPath,
            roots.CatalogBackupPath,
            roots.LibraryRoot);
    }

    internal static bool RestorePreviousPrimary(
        CatalogPrimarySnapshot snapshot,
        StorageRootSet roots)
    {
        if (!snapshot.Existed)
        {
            return RestorePriorAbsence(roots);
        }

        if (snapshot.CopyPath is not { } rollbackPath)
        {
            return false;
        }
        return CatalogCommitFiles.CopyAndPromote(
            rollbackPath,
            roots.CatalogPath,
            roots.LibraryRoot) == CatalogStoreError.None;
    }

    internal static bool RestorePriorAbsence(StorageRootSet roots)
    {
        List<string> quarantined = [];
        try
        {
            foreach (string path in CatalogCommitFiles.CatalogCompanionPaths(roots).Prepend(roots.CatalogPath))
            {
                if (Directory.Exists(path) || StoragePathPolicy.IsExistingReparsePoint(path))
                {
                    return false;
                }
                if (!File.Exists(path))
                {
                    continue;
                }

                string quarantinePath = Path.Combine(
                    roots.LibraryRoot,
                    $".catalog-{Guid.NewGuid():N}.removed");
                if (!CatalogCommitFiles.MoveFileEx(path, quarantinePath, CatalogCommitFiles.MoveFileWriteThrough))
                {
                    return false;
                }
                quarantined.Add(quarantinePath);
            }

            bool restored = !File.Exists(roots.CatalogPath) &&
                !Directory.Exists(roots.CatalogPath) &&
                CatalogCommitFiles.CatalogCompanionPaths(roots).All(path =>
                    !File.Exists(path) && !Directory.Exists(path));
            if (restored)
            {
                foreach (string path in quarantined)
                {
                    CatalogCommitFiles.TryDelete(path);
                }
            }
            return restored;
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException)
        {
            return false;
        }
    }

    internal static bool HasUnresolvedRollbackArtifact(StorageRootSet roots)
    {
        string markerPath = $"{roots.CatalogPath}.rollback-required";
        if (File.Exists(markerPath) || Directory.Exists(markerPath))
        {
            return true;
        }

        try
        {
            return Directory.Exists(roots.LibraryRoot) &&
                Directory.EnumerateFileSystemEntries(
                    roots.LibraryRoot,
                    ".catalog-*.rollback",
                    SearchOption.TopDirectoryOnly).Any();
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or ArgumentException)
        {
            return true;
        }
    }

    internal static void RecordRollbackFailure(StorageRootSet roots)
    {
        string markerPath = $"{roots.CatalogPath}.rollback-required";
        try
        {
            if (File.Exists(markerPath) || Directory.Exists(markerPath))
            {
                return;
            }
            using FileStream marker = new(
                markerPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.Read,
                bufferSize: 1,
                FileOptions.WriteThrough);
            marker.WriteByte(1);
            marker.Flush(flushToDisk: true);
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException)
        {
            // 현재 세션은 이미 mutation 금지 상태가 되며, 보존된 rollback/SQLite artifact를 유지합니다.
        }
    }
}
