using System.Runtime.InteropServices;

namespace Negaflow.Catalog;

internal readonly record struct CatalogPrimarySnapshot(bool Existed, string? CopyPath);

/// <summary>
/// <see cref="SqliteCatalogStore"/>의 한 transaction을 사용자에게 성공으로 공개하기 전에 직전
/// primary 보존, 새 연결 readback, canonical snapshot 비교와 실패 원복을 수행합니다.
/// </summary>
internal static class CatalogCommitVerifier
{
    private const uint MoveFileWriteThrough = 0x00000008;

    public static CatalogWriteResult Commit(
        CatalogSnapshot snapshot,
        StorageRootSet roots) =>
        CommitCore(
            snapshot,
            roots,
            SqliteCatalogStore.Write,
            SqliteCatalogStore.Read,
            RestorePreviousPrimary);

    /// <summary>write/readback/rollback 실패를 결정적으로 재현하는 unit-test seam입니다.</summary>
    internal static CatalogWriteResult CommitForTesting(
        CatalogSnapshot snapshot,
        StorageRootSet roots,
        Func<CatalogSnapshot, string, CatalogWriteResult>? writer = null,
        Func<string, CatalogReadResult>? readback = null,
        Func<CatalogPrimarySnapshot, StorageRootSet, bool>? restore = null) =>
        CommitCore(
            snapshot,
            roots,
            writer ?? SqliteCatalogStore.Write,
            readback ?? SqliteCatalogStore.Read,
            restore ?? RestorePreviousPrimary);

    private static CatalogWriteResult CommitCore(
        CatalogSnapshot snapshot,
        StorageRootSet roots,
        Func<CatalogSnapshot, string, CatalogWriteResult> writer,
        Func<string, CatalogReadResult> readback,
        Func<CatalogPrimarySnapshot, StorageRootSet, bool> restore)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(writer);
        ArgumentNullException.ThrowIfNull(readback);
        ArgumentNullException.ThrowIfNull(restore);

        if (!HasValidPaths(roots))
        {
            return CatalogWriteResult.Failure(CatalogStoreError.InvalidPath);
        }

        if (HasUnresolvedRollbackArtifact(roots))
        {
            return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
        }

        bool primaryExisted = File.Exists(roots.CatalogPath);
        if (!primaryExisted && HasBlockingArtifactWhenPrimaryMissing(roots))
        {
            return CatalogWriteResult.Failure(
                CatalogStoreError.MissingAuthoritativeData);
        }

        CatalogPrimarySnapshot primarySnapshot = new(primaryExisted, null);
        if (primaryExisted)
        {
            CatalogReadResult previous = SqliteCatalogStore.Read(roots.CatalogPath);
            if (previous.Snapshot is not { } previousSnapshot)
            {
                return CatalogWriteResult.Failure(previous.Error);
            }

            bool unchanged = SnapshotsMatch(previousSnapshot, snapshot);
            if (unchanged &&
                CatalogRecovery.IsValidCatalogSource(roots.CatalogBackupPath))
            {
                return CatalogWriteResult.Success();
            }

            if (unchanged)
            {
                CatalogStoreError preserveUnchanged = PreservePreviousPrimary(
                    roots.CatalogPath,
                    roots);
                return preserveUnchanged == CatalogStoreError.None
                    ? CatalogWriteResult.Success()
                    : CatalogWriteResult.Failure(preserveUnchanged);
            }

            CatalogStoreError snapshotError = CreatePrimarySnapshot(
                roots,
                previousSnapshot,
                out primarySnapshot);
            if (snapshotError != CatalogStoreError.None)
            {
                return CatalogWriteResult.Failure(snapshotError);
            }
        }

        bool retainSnapshot = false;
        try
        {
            if (primarySnapshot.CopyPath is { } previousPrimaryPath)
            {
                CatalogStoreError preserveError = PreservePreviousPrimary(
                    previousPrimaryPath,
                    roots);
                if (preserveError != CatalogStoreError.None)
                {
                    return CatalogWriteResult.Failure(preserveError);
                }
            }

            CatalogWriteResult written;
            try
            {
                written = writer(snapshot, roots.CatalogPath);
            }
            catch (Exception error) when (IsRecoverableCommitException(error))
            {
                if (restore(primarySnapshot, roots))
                {
                    return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
                }
                retainSnapshot = primarySnapshot.Existed;
                RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }
            if (!written.IsSuccess)
            {
                if (restore(primarySnapshot, roots))
                {
                    return written;
                }
                retainSnapshot = primarySnapshot.Existed;
                RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }

            CatalogReadResult persisted;
            try
            {
                persisted = readback(roots.CatalogPath);
            }
            catch (Exception error) when (IsRecoverableCommitException(error))
            {
                if (restore(primarySnapshot, roots))
                {
                    return CatalogWriteResult.Failure(CatalogStoreError.ReadbackFailed);
                }
                retainSnapshot = primarySnapshot.Existed;
                RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }
            if (persisted.Snapshot is not { } persistedSnapshot ||
                !SnapshotsMatch(snapshot, persistedSnapshot))
            {
                if (restore(primarySnapshot, roots))
                {
                    return CatalogWriteResult.Failure(CatalogStoreError.ReadbackFailed);
                }
                retainSnapshot = primarySnapshot.Existed;
                RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }

            return CatalogWriteResult.Success();
        }
        finally
        {
            if (!retainSnapshot)
            {
                TryDelete(primarySnapshot.CopyPath);
            }
        }
    }

    private static bool HasValidPaths(StorageRootSet roots)
    {
        try
        {
            return Path.IsPathFullyQualified(roots.LibraryRoot) &&
                Path.IsPathFullyQualified(roots.CatalogPath) &&
                Path.IsPathFullyQualified(roots.CatalogBackupPath) &&
                !string.Equals(
                    Path.GetFullPath(roots.CatalogPath),
                    Path.GetFullPath(roots.CatalogBackupPath),
                    StringComparison.OrdinalIgnoreCase) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.CatalogPath) &&
                StoragePathPolicy.IsLexicallyContained(
                    roots.LibraryRoot,
                    roots.CatalogBackupPath);
        }
        catch (Exception error) when (error is
            ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    internal static bool HasBlockingArtifactWhenPrimaryMissing(StorageRootSet roots) =>
        File.Exists(roots.CatalogBackupPath) ||
        Directory.Exists(roots.CatalogBackupPath) ||
        CatalogCompanionPaths(roots).Any(path =>
            File.Exists(path) || Directory.Exists(path)) ||
        HasUnresolvedRollbackArtifact(roots);

    private static CatalogStoreError CreatePrimarySnapshot(
        StorageRootSet roots,
        CatalogSnapshot expectedPrevious,
        out CatalogPrimarySnapshot snapshot)
    {
        string rollbackPath = Path.Combine(
            roots.LibraryRoot,
            $".catalog-{Guid.NewGuid():N}.rollback");
        CatalogStoreError copied = CopyAndPromote(
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
                !SnapshotsMatch(expectedPrevious, capturedSnapshot))
            {
                TryDelete(rollbackPath);
                snapshot = new CatalogPrimarySnapshot(true, null);
                return CatalogStoreError.ReadbackFailed;
            }
        }
        return copied;
    }

    private static CatalogStoreError PreservePreviousPrimary(
        string previousPrimaryPath,
        StorageRootSet roots)
    {
        if (!CatalogRecovery.IsValidCatalogSource(previousPrimaryPath))
        {
            return CatalogStoreError.IoFailure;
        }
        return CopyAndPromote(
            previousPrimaryPath,
            roots.CatalogBackupPath,
            roots.LibraryRoot);
    }

    private static bool RestorePreviousPrimary(
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
        return CopyAndPromote(
            rollbackPath,
            roots.CatalogPath,
            roots.LibraryRoot) == CatalogStoreError.None;
    }

    private static bool RestorePriorAbsence(StorageRootSet roots)
    {
        List<string> quarantined = [];
        try
        {
            foreach (string path in CatalogCompanionPaths(roots).Prepend(roots.CatalogPath))
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
                if (!MoveFileEx(path, quarantinePath, MoveFileWriteThrough))
                {
                    return false;
                }
                quarantined.Add(quarantinePath);
            }

            bool restored = !File.Exists(roots.CatalogPath) &&
                !Directory.Exists(roots.CatalogPath) &&
                CatalogCompanionPaths(roots).All(path =>
                    !File.Exists(path) && !Directory.Exists(path));
            if (restored)
            {
                foreach (string path in quarantined)
                {
                    TryDelete(path);
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

    private static CatalogStoreError CopyAndPromote(
        string sourcePath,
        string destinationPath,
        string libraryRoot)
    {
        if (!Path.IsPathFullyQualified(sourcePath) ||
            !Path.IsPathFullyQualified(destinationPath) ||
            !StoragePathPolicy.IsLexicallyContained(libraryRoot, sourcePath) ||
            !StoragePathPolicy.IsLexicallyContained(libraryRoot, destinationPath) ||
            !File.Exists(sourcePath) ||
            StoragePathPolicy.IsExistingReparsePoint(sourcePath) ||
            StoragePathPolicy.IsExistingReparsePoint(destinationPath))
        {
            return CatalogStoreError.InvalidPath;
        }

        string? destinationDirectory = Path.GetDirectoryName(destinationPath);
        if (destinationDirectory is null)
        {
            return CatalogStoreError.InvalidPath;
        }

        string temporaryPath = Path.Combine(
            destinationDirectory,
            $".catalog-{Guid.NewGuid():N}.tmp");
        string? displacedPath = null;
        bool promotionAttempted = false;
        bool promotionVerified = false;
        try
        {
            Directory.CreateDirectory(destinationDirectory);
            using (FileStream sourceCopy = new(
                       sourcePath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read,
                       bufferSize: 1024 * 1024,
                       FileOptions.SequentialScan))
            using (FileStream temporary = new(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 1024 * 1024,
                       FileOptions.WriteThrough))
            {
                sourceCopy.CopyTo(temporary);
                temporary.Flush(flushToDisk: true);
            }

            if (!CatalogRecovery.IsValidCatalogSource(temporaryPath))
            {
                return CatalogStoreError.IoFailure;
            }
            using FileStream source = new(
                sourcePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan);
            using (FileStream candidate = new(
                temporaryPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan))
            {
                if (!FilesEqual(source, candidate))
                {
                    return CatalogStoreError.IoFailure;
                }
            }

            if (StoragePathPolicy.IsExistingReparsePoint(destinationPath))
            {
                return CatalogStoreError.InvalidPath;
            }
            promotionAttempted = true;
            if (File.Exists(destinationPath))
            {
                displacedPath = Path.Combine(
                    destinationDirectory,
                    $".catalog-{Guid.NewGuid():N}.displaced");
                File.Replace(
                    temporaryPath,
                    destinationPath,
                    displacedPath,
                    ignoreMetadataErrors: true);
            }
            else
            {
                if (!MoveFileEx(
                    temporaryPath,
                    destinationPath,
                    MoveFileWriteThrough))
                {
                    return ClassifyWin32(Marshal.GetLastPInvokeError());
                }
            }

            using (FileStream durable = new(
                destinationPath,
                FileMode.Open,
                FileAccess.ReadWrite,
                FileShare.ReadWrite | FileShare.Delete,
                bufferSize: 1,
                FileOptions.WriteThrough))
            {
                durable.Flush(flushToDisk: true);
            }
            bool promotedIsValid = CatalogRecovery.IsValidCatalogSource(destinationPath);
            using (FileStream promoted = new(
                destinationPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1024 * 1024,
                FileOptions.SequentialScan))
            {
                promotionVerified = promotedIsValid && FilesEqual(source, promoted);
            }
            return promotionVerified
                ? CatalogStoreError.None
                : CatalogStoreError.IoFailure;
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogStoreError.AccessDenied;
        }
        catch (Exception error) when (error is IOException or NotSupportedException)
        {
            return CatalogStoreError.IoFailure;
        }
        finally
        {
            if (!promotionAttempted || promotionVerified)
            {
                TryDelete(temporaryPath);
            }
            if (promotionVerified)
            {
                TryDelete(displacedPath);
            }
        }
    }

    private static bool FilesEqual(FileStream first, FileStream second)
    {
        if (first.Length != second.Length)
        {
            return false;
        }

        first.Position = 0;
        second.Position = 0;
        Span<byte> firstBuffer = stackalloc byte[8192];
        Span<byte> secondBuffer = stackalloc byte[8192];
        while (true)
        {
            int firstRead = first.Read(firstBuffer);
            int secondRead = second.Read(secondBuffer);
            if (firstRead != secondRead)
            {
                return false;
            }
            if (firstRead == 0)
            {
                return true;
            }
            if (!firstBuffer[..firstRead].SequenceEqual(secondBuffer[..secondRead]))
            {
                return false;
            }
        }
    }

    private static IEnumerable<string> CatalogCompanionPaths(StorageRootSet roots)
    {
        yield return $"{roots.CatalogPath}-journal";
        yield return $"{roots.CatalogPath}-wal";
        yield return $"{roots.CatalogPath}-shm";
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

    private static void RecordRollbackFailure(StorageRootSet roots)
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

    private static void TryDelete(string? path)
    {
        if (path is null)
        {
            return;
        }
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 비권위 staging/이전 세대 정리 실패는 검증된 primary의 결과를 덮지 않습니다.
        }
    }

    private static CatalogStoreError ClassifyWin32(int error) => error switch
    {
        5 => CatalogStoreError.AccessDenied,
        32 or 33 => CatalogStoreError.Busy,
        _ => CatalogStoreError.IoFailure,
    };

    private static bool IsRecoverableCommitException(Exception error) => error is not
        OutOfMemoryException and not AccessViolationException;

    [DllImport(
        "kernel32.dll",
        EntryPoint = "MoveFileExW",
        CharSet = CharSet.Unicode,
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool MoveFileEx(
        string existingFileName,
        string newFileName,
        uint flags);

    private static bool SnapshotsMatch(CatalogSnapshot first, CatalogSnapshot second)
    {
        if (first.CatalogVersion != second.CatalogVersion ||
            first.MinimumReaderVersion != second.MinimumReaderVersion ||
            !string.Equals(first.ActiveRollId, second.ActiveRollId, StringComparison.Ordinal))
        {
            return false;
        }

        try
        {
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                IReadOnlyList<CatalogEntityRow> firstRows = first.Rows(table);
                IReadOnlyList<CatalogEntityRow> secondRows = second.Rows(table);
                if (firstRows.Count != secondRows.Count)
                {
                    return false;
                }
                for (int index = 0; index < firstRows.Count; index++)
                {
                    if (!string.Equals(
                            firstRows[index].Id,
                            secondRows[index].Id,
                            StringComparison.Ordinal) ||
                        !CatalogJson.SerializeCanonical(firstRows[index].Payload)
                            .AsSpan()
                            .SequenceEqual(CatalogJson.SerializeCanonical(secondRows[index].Payload)))
                    {
                        return false;
                    }
                }
            }
            return true;
        }
        catch (System.Text.Json.JsonException)
        {
            return false;
        }
    }
}
