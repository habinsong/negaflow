using System.Diagnostics;

namespace Negaflow.Catalog;

internal readonly record struct CatalogPrimarySnapshot(bool Existed, string? CopyPath);

/// <summary>
/// <see cref="SqliteCatalogStore"/>의 한 transaction을 사용자에게 성공으로 공개하기 전에 직전
/// primary 보존, 새 연결 readback, canonical snapshot 비교와 실패 원복을 수행합니다.
/// </summary>
internal static class CatalogCommitVerifier
{
    /// <summary>`NEGA_TIMING=1` 일 때만 commit 내부 구간을 실측합니다.</summary>
    private static readonly bool TraceEnabled = string.Equals(
        Environment.GetEnvironmentVariable("NEGA_TIMING"),
        "1",
        StringComparison.Ordinal);


    public static CatalogWriteResult Commit(
        CatalogSnapshot snapshot,
        StorageRootSet roots) =>
        CommitCore(
            snapshot,
            roots,
            SqliteCatalogStore.Write,
            SqliteCatalogStore.Read,
            CatalogCommitRollback.RestorePreviousPrimary);

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
            restore ?? CatalogCommitRollback.RestorePreviousPrimary);

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

        if (!CatalogCommitFiles.HasValidPaths(roots))
        {
            return CatalogWriteResult.Failure(CatalogStoreError.InvalidPath);
        }

        if (CatalogCommitRollback.HasUnresolvedRollbackArtifact(roots))
        {
            return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
        }

        long traceStart = TraceEnabled ? Stopwatch.GetTimestamp() : 0L;
        double previousRead = 0.0;
        double compare = 0.0;
        double snapshotCopy = 0.0;
        double preserve = 0.0;
        double writeMilliseconds = 0.0;
        double readbackMilliseconds = 0.0;
        double Split()
        {
            long now = Stopwatch.GetTimestamp();
            double elapsed = (now - traceStart) * 1000.0 / Stopwatch.Frequency;
            traceStart = now;
            return elapsed;
        }

        bool primaryExisted = File.Exists(roots.CatalogPath);
        if (!primaryExisted && CatalogCommitRollback.HasBlockingArtifactWhenPrimaryMissing(roots))
        {
            return CatalogWriteResult.Failure(
                CatalogStoreError.MissingAuthoritativeData);
        }

        CatalogPrimarySnapshot primarySnapshot = new(primaryExisted, null);
        if (primaryExisted)
        {
            CatalogReadResult previous = SqliteCatalogStore.Read(roots.CatalogPath);
            if (TraceEnabled)
            {
                previousRead = Split();
            }
            if (previous.Snapshot is not { } previousSnapshot)
            {
                return CatalogWriteResult.Failure(previous.Error);
            }

            bool unchanged = SnapshotsMatch(previousSnapshot, snapshot);
            if (TraceEnabled)
            {
                compare = Split();
            }
            if (unchanged &&
                CatalogRecovery.IsValidCatalogSource(roots.CatalogBackupPath))
            {
                return CatalogWriteResult.Success();
            }

            if (unchanged)
            {
                CatalogStoreError preserveUnchanged = CatalogCommitRollback.PreservePreviousPrimary(
                    roots.CatalogPath,
                    roots);
                return preserveUnchanged == CatalogStoreError.None
                    ? CatalogWriteResult.Success()
                    : CatalogWriteResult.Failure(preserveUnchanged);
            }

            CatalogStoreError snapshotError = CatalogCommitRollback.CreatePrimarySnapshot(
                roots,
                previousSnapshot,
                out primarySnapshot);
            if (TraceEnabled)
            {
                snapshotCopy = Split();
            }
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
                CatalogStoreError preserveError = CatalogCommitRollback.PreservePreviousPrimary(
                    previousPrimaryPath,
                    roots);
                if (TraceEnabled)
                {
                    preserve = Split();
                }
                if (preserveError != CatalogStoreError.None)
                {
                    return CatalogWriteResult.Failure(preserveError);
                }
            }

            CatalogWriteResult written;
            try
            {
                written = writer(snapshot, roots.CatalogPath);
                if (TraceEnabled)
                {
                    writeMilliseconds = Split();
                }
            }
            catch (Exception error) when (CatalogCommitFiles.IsRecoverableCommitException(error))
            {
                if (restore(primarySnapshot, roots))
                {
                    return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
                }
                retainSnapshot = primarySnapshot.Existed;
                CatalogCommitRollback.RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }
            if (!written.IsSuccess)
            {
                if (restore(primarySnapshot, roots))
                {
                    return written;
                }
                retainSnapshot = primarySnapshot.Existed;
                CatalogCommitRollback.RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }

            CatalogReadResult persisted;
            try
            {
                persisted = readback(roots.CatalogPath);
                if (TraceEnabled)
                {
                    readbackMilliseconds = Split();
                }
            }
            catch (Exception error) when (CatalogCommitFiles.IsRecoverableCommitException(error))
            {
                if (restore(primarySnapshot, roots))
                {
                    return CatalogWriteResult.Failure(CatalogStoreError.ReadbackFailed);
                }
                retainSnapshot = primarySnapshot.Existed;
                CatalogCommitRollback.RecordRollbackFailure(roots);
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
                CatalogCommitRollback.RecordRollbackFailure(roots);
                return CatalogWriteResult.Failure(CatalogStoreError.RollbackFailed);
            }

            if (TraceEnabled)
            {
                double verify = Split();
                Console.Error.WriteLine(
                    $"[catalog commit timing] read={previousRead:F1} compare={compare:F1} " +
                    $"snapshot={snapshotCopy:F1} preserve={preserve:F1} " +
                    $"write={writeMilliseconds:F1} readback={readbackMilliseconds:F1} " +
                    $"verify={verify:F1} ms");
            }
            return CatalogWriteResult.Success();
        }
        finally
        {
            if (!retainSnapshot)
            {
                CatalogCommitFiles.TryDelete(primarySnapshot.CopyPath);
            }
        }
    }

    internal static bool SnapshotsMatch(CatalogSnapshot first, CatalogSnapshot second)
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
