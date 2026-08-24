namespace Negaflow.Catalog;

/// <summary>
/// sidecar-first defect 게시가 catalog commit에 실패했을 때 직전 sidecar 바이트와 revision floor를
/// 정확히 복구합니다. 일반 sidecar 읽기·쓰기·삭제는 <see cref="DefectSidecarStore"/>가 소유합니다.
/// </summary>
internal static class DefectSidecarCatalogWriter
{
    internal static DefectRecipeCatalogWriteResult Write(
        StorageRootSet roots,
        DefectRecipeSnapshot snapshot,
        Func<CatalogWriteResult> commitCatalog,
        bool forceSidecarRollbackFailure = false)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(commitCatalog);
        lock (DefectSidecarStore.Gate)
        {
            if (!TryCaptureRollbackState(
                    roots,
                    snapshot.FrameId,
                    out DefectSidecarRollbackState rollback,
                    out DefectSidecarError captureError))
            {
                return DefectRecipeCatalogWriteResult.Failure(
                    DefectSidecarWriteResult.Failure(captureError));
            }

            DefectSidecarWriteResult sidecar =
                DefectSidecarStore.WriteLocked(roots, snapshot);
            if (!sidecar.IsSuccess)
            {
                return DefectRecipeCatalogWriteResult.Failure(sidecar);
            }
            if (sidecar.Kind == DefectSidecarWriteKind.SkippedNewer)
            {
                return DefectRecipeCatalogWriteResult.Failure(
                    DefectSidecarWriteResult.Failure(
                        DefectSidecarError.InvalidSnapshot,
                        sidecar.ExistingRevision));
            }

            CatalogWriteResult catalog = commitCatalog();
            if (catalog.IsSuccess)
            {
                return DefectRecipeCatalogWriteResult.Success(snapshot, sidecar);
            }
            if (RestoreOrBlock(roots, rollback, forceSidecarRollbackFailure))
            {
                return DefectRecipeCatalogWriteResult.Failure(sidecar, catalog.Error);
            }
            return DefectRecipeCatalogWriteResult.Failure(
                DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure),
                CatalogStoreError.RollbackFailed);
        }
    }

    internal static DefectRecipeCatalogBatchWriteResult WriteMany(
        StorageRootSet roots,
        IReadOnlyList<DefectRecipeSnapshot> snapshots,
        Func<CatalogWriteResult> commitCatalog,
        bool forceSidecarRollbackFailure = false)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshots);
        ArgumentNullException.ThrowIfNull(commitCatalog);
        lock (DefectSidecarStore.Gate)
        {
            List<DefectSidecarRollbackState> rollbacks = new(snapshots.Count);
            foreach (DefectRecipeSnapshot snapshot in snapshots)
            {
                if (!TryCaptureRollbackState(
                        roots,
                        snapshot.FrameId,
                        out DefectSidecarRollbackState rollback,
                        out DefectSidecarError captureError))
                {
                    return DefectRecipeCatalogBatchWriteResult.Failure(captureError);
                }
                rollbacks.Add(rollback);
            }

            List<DefectRecipeSnapshot> stored = new(snapshots.Count);
            for (int index = 0; index < snapshots.Count; ++index)
            {
                DefectSidecarWriteResult sidecar =
                    DefectSidecarStore.WriteLocked(roots, snapshots[index]);
                if (!sidecar.IsSuccess || sidecar.Kind == DefectSidecarWriteKind.SkippedNewer)
                {
                    DefectSidecarError error = sidecar.IsSuccess
                        ? DefectSidecarError.InvalidSnapshot
                        : sidecar.Error;
                    return RestoreManyOrBlock(
                            roots,
                            rollbacks,
                            stored.Count,
                            forceSidecarRollbackFailure)
                        ? DefectRecipeCatalogBatchWriteResult.Failure(error)
                        : DefectRecipeCatalogBatchWriteResult.Failure(
                            DefectSidecarError.IoFailure,
                            CatalogStoreError.RollbackFailed);
                }

                stored.Add(snapshots[index]);
            }

            CatalogWriteResult catalog = commitCatalog();
            if (catalog.IsSuccess)
            {
                return DefectRecipeCatalogBatchWriteResult.Success(stored);
            }
            if (RestoreManyOrBlock(
                    roots,
                    rollbacks,
                    stored.Count,
                    forceSidecarRollbackFailure))
            {
                return DefectRecipeCatalogBatchWriteResult.Failure(
                    catalogError: catalog.Error);
            }
            return DefectRecipeCatalogBatchWriteResult.Failure(
                DefectSidecarError.IoFailure,
                CatalogStoreError.RollbackFailed);
        }
    }

    private static bool TryCaptureRollbackState(
        StorageRootSet roots,
        Guid frameId,
        out DefectSidecarRollbackState rollback,
        out DefectSidecarError error)
    {
        rollback = default;
        error = DefectSidecarError.None;
        if (frameId == Guid.Empty)
        {
            error = DefectSidecarError.InvalidFrameId;
            return false;
        }
        if (!DefectSidecarFile.HasValidRoots(roots))
        {
            error = DefectSidecarError.InvalidStorageRoots;
            return false;
        }

        string path = DefectSidecarStore.PathFor(roots, frameId);
        string key = DefectSidecarFile.RevisionKey(path);
        try
        {
            DefectSidecarReadResult existing = DefectSidecarFile.ReadFile(path, frameId);
            byte[]? bytes = null;
            DefectRecipeSnapshot? previous = existing.Snapshot;
            if (previous is not null)
            {
                bytes = File.ReadAllBytes(path);
                if (bytes.LongLength > DefectSidecarStore.MaximumFileBytes)
                {
                    error = DefectSidecarError.InvalidContent;
                    return false;
                }
            }
            else if (existing.Error != DefectSidecarError.NotFound)
            {
                error = existing.Error;
                return false;
            }

            bool hadRevisionFloor = DefectSidecarStore.RevisionFloors.TryGetValue(
                key,
                out ulong revisionFloor);
            rollback = new DefectSidecarRollbackState(
                path,
                key,
                previous,
                bytes,
                hadRevisionFloor,
                revisionFloor);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            error = DefectSidecarError.AccessDenied;
            return false;
        }
        catch (Exception exception) when (exception is
            IOException or NotSupportedException or ArgumentException or PathTooLongException)
        {
            error = DefectSidecarError.IoFailure;
            return false;
        }
    }

    private static bool RestoreOrBlock(
        StorageRootSet roots,
        DefectSidecarRollbackState rollback,
        bool forceFailure)
    {
        if (!forceFailure && RestoreRollbackState(rollback))
        {
            return true;
        }
        CatalogCommitRollback.RecordRollbackFailure(roots);
        return false;
    }

    private static bool RestoreManyOrBlock(
        StorageRootSet roots,
        IReadOnlyList<DefectSidecarRollbackState> rollbacks,
        int writtenCount,
        bool forceFailure)
    {
        if (forceFailure)
        {
            CatalogCommitRollback.RecordRollbackFailure(roots);
            return false;
        }
        bool restored = true;
        for (int index = Math.Min(writtenCount, rollbacks.Count) - 1; index >= 0; --index)
        {
            restored = RestoreRollbackState(rollbacks[index]) && restored;
        }
        if (restored)
        {
            return true;
        }
        CatalogCommitRollback.RecordRollbackFailure(roots);
        return false;
    }

    private static bool RestoreRollbackState(DefectSidecarRollbackState rollback)
    {
        try
        {
            if (Directory.Exists(rollback.Path) ||
                StoragePathPolicy.IsExistingReparsePoint(rollback.Path))
            {
                return false;
            }
            if (rollback.Previous is not null)
            {
                DefectSidecarFile.PrepareDirectory(Path.GetDirectoryName(rollback.Path)!);
                DefectSidecarFile.WriteAtomic(rollback.Path, rollback.Bytes!);
            }
            else
            {
                if (File.Exists(rollback.Path))
                {
                    File.Delete(rollback.Path);
                }
                if (File.Exists(rollback.Path) || Directory.Exists(rollback.Path))
                {
                    return false;
                }
            }

            if (rollback.HadRevisionFloor)
            {
                DefectSidecarStore.RevisionFloors[rollback.RevisionKey] =
                    rollback.RevisionFloor;
            }
            else
            {
                DefectSidecarStore.RevisionFloors.Remove(rollback.RevisionKey);
            }
            return true;
        }
        catch (Exception exception) when (exception is
            IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException or PathTooLongException)
        {
            return false;
        }
    }

    private readonly record struct DefectSidecarRollbackState(
        string Path,
        string RevisionKey,
        DefectRecipeSnapshot? Previous,
        byte[]? Bytes,
        bool HadRevisionFloor,
        ulong RevisionFloor);
}
