namespace Negaflow.Catalog;

internal static class CatalogPendingRestoreStore
{
    public static CatalogPendingRestoreScheduleResult Schedule(
        StorageRootSet roots,
        string generationId,
        DateTimeOffset scheduledAt)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!CatalogPendingRestoreFiles.HasValidRoots(roots))
        {
            return CatalogPendingRestoreScheduleResult.Failure(
                CatalogPendingRestoreError.InvalidStorageRoots);
        }
        if (!CatalogPendingRestoreFiles.TryResolveGeneration(
                roots,
                generationId,
                out string generationPath) ||
            !CatalogBackupStore.ValidateGeneration(generationPath).IsValid)
        {
            return CatalogPendingRestoreScheduleResult.Failure(
                CatalogPendingRestoreError.InvalidGeneration);
        }

        string? stagingPath = null;
        string? destinationPath = null;
        bool markerWriteAttempted = false;
        bool markerCommitted = false;
        try
        {
            CatalogPendingRestoreFiles.PrepareRoot(roots);
            CatalogPendingRestoreMarker? previousMarker =
                CatalogPendingRestoreFiles.TryReadMarker(roots, out var previous)
                    ? previous
                    : null;

            stagingPath = Path.Combine(
                roots.PendingRestoreRoot,
                $"staging-{Guid.NewGuid():N}.tmp");
            string destinationName = $"restore-{Guid.NewGuid():N}";
            destinationPath = Path.Combine(roots.PendingRestoreRoot, destinationName);

            CatalogBackupValidationResult pinned =
                CatalogPendingRestoreFiles.CopyValidatedGeneration(
                    generationPath,
                    stagingPath,
                    roots.PendingRestoreRoot);
            if (!pinned.IsValid)
            {
                return CatalogPendingRestoreScheduleResult.Failure(
                    CatalogPendingRestoreError.InvalidPendingSnapshot);
            }
            if (File.Exists(destinationPath) ||
                Directory.Exists(destinationPath) ||
                !CatalogPendingRestoreFiles.PromoteDirectory(
                    stagingPath,
                    destinationPath))
            {
                return CatalogPendingRestoreScheduleResult.Failure(
                    CatalogPendingRestoreError.IoFailure);
            }
            stagingPath = null;
            CatalogBackupValidationResult promoted =
                CatalogBackupStore.ValidateGeneration(destinationPath);
            if (!CatalogPendingRestoreFiles.SameGeneration(pinned, promoted))
            {
                return CatalogPendingRestoreScheduleResult.Failure(
                    CatalogPendingRestoreError.InvalidPendingSnapshot);
            }

            CatalogPendingRestoreMarker marker = new(
                CatalogPendingRestoreMarker.CurrentVersion,
                destinationName,
                generationId,
                scheduledAt.ToUniversalTime(),
                CatalogPendingRestorePhase.Scheduled);
            markerWriteAttempted = true;
            CatalogPendingRestoreFiles.WriteMarkerAtomic(roots, marker);
            markerCommitted = true;

            if (previousMarker is { } old &&
                old.DirectoryName != destinationName &&
                CatalogPendingRestoreFiles.IsValidPendingDirectoryName(
                    old.DirectoryName))
            {
                _ = CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                    Path.Combine(roots.PendingRestoreRoot, old.DirectoryName),
                    roots.PendingRestoreRoot,
                    "restore-",
                    requireValidGeneration: true);
            }
            return CatalogPendingRestoreScheduleResult.Success(
                generationId,
                marker.ScheduledAt);
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogPendingRestoreScheduleResult.Failure(
                CatalogPendingRestoreError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            return CatalogPendingRestoreScheduleResult.Failure(
                CatalogPendingRestoreError.IoFailure);
        }
        finally
        {
            if (stagingPath is not null)
            {
                _ = CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                    stagingPath,
                    roots.PendingRestoreRoot,
                    "staging-",
                    requireValidGeneration: false);
            }
            if (!markerCommitted &&
                !markerWriteAttempted &&
                destinationPath is not null)
            {
                _ = CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                    destinationPath,
                    roots.PendingRestoreRoot,
                    "restore-",
                    requireValidGeneration: true);
            }
        }
    }

    public static CatalogPendingRestoreOperationResult Cancel(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!CatalogPendingRestoreFiles.HasValidRoots(roots))
        {
            return CatalogPendingRestoreOperationResult.Failure(
                CatalogPendingRestoreError.InvalidStorageRoots);
        }

        string markerPath = CatalogPendingRestoreFiles.MarkerPath(roots);
        try
        {
            CatalogPendingRestoreMarker? marker =
                CatalogPendingRestoreFiles.TryReadMarker(roots, out var decoded)
                    ? decoded
                    : null;
            if (Directory.Exists(markerPath) ||
                StoragePathPolicy.IsExistingReparsePoint(markerPath))
            {
                return CatalogPendingRestoreOperationResult.Failure(
                    CatalogPendingRestoreError.InvalidMarker);
            }
            if (File.Exists(markerPath))
            {
                File.Delete(markerPath);
            }
            if (marker is { } existing &&
                CatalogPendingRestoreFiles.IsValidPendingDirectoryName(
                    existing.DirectoryName))
            {
                _ = CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                    Path.Combine(
                        roots.PendingRestoreRoot,
                        existing.DirectoryName),
                    roots.PendingRestoreRoot,
                    "restore-",
                    requireValidGeneration: true);
            }
            return CatalogPendingRestoreOperationResult.Success();
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogPendingRestoreOperationResult.Failure(
                CatalogPendingRestoreError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            return CatalogPendingRestoreOperationResult.Failure(
                CatalogPendingRestoreError.IoFailure);
        }
    }

    public static CatalogPendingRestoreApplicationResult ApplyIfScheduled(
        StorageRootSet roots,
        DateTimeOffset now) =>
        ApplyIfScheduled(
            roots,
            now,
            new CatalogPendingRestoreCleanup(
                RemoveDirectory: path =>
                {
                    if (!CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                            path,
                            roots.PendingRestoreRoot,
                            "restore-",
                            requireValidGeneration: false))
                    {
                        throw new IOException(
                            "Pending restore directory cleanup failed.");
                    }
                },
                RemoveMarker: File.Delete));

    internal static CatalogPendingRestoreApplicationResult ApplyIfScheduled(
        StorageRootSet roots,
        DateTimeOffset now,
        CatalogPendingRestoreCleanup cleanup)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!CatalogPendingRestoreFiles.HasValidRoots(roots))
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.InvalidStorageRoots);
        }

        string markerPath = CatalogPendingRestoreFiles.MarkerPath(roots);
        if (!File.Exists(markerPath) && !Directory.Exists(markerPath))
        {
            return CatalogPendingRestoreApplicationResult.None();
        }
        if (!CatalogPendingRestoreFiles.TryReadMarker(roots, out var marker) ||
            !CatalogPendingRestoreFiles.IsValidPendingDirectoryName(
                marker.DirectoryName) ||
            !CatalogPendingRestoreFiles.IsValidGenerationId(
                marker.SourceGenerationId))
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.InvalidMarker);
        }

        if (marker.Phase == CatalogPendingRestorePhase.Applied)
        {
            bool cleaned = RunCleanup(roots, marker, cleanup);
            return CatalogPendingRestoreApplicationResult.Success(
                cleaned
                    ? CatalogPendingRestoreApplicationKind.CleanupOnly
                    : CatalogPendingRestoreApplicationKind.CleanupPending,
                marker.SourceGenerationId,
                didApplyRestore: false);
        }

        string pendingPath = Path.Combine(
            roots.PendingRestoreRoot,
            marker.DirectoryName);
        CatalogBackupValidationResult pending =
            CatalogBackupStore.ValidateGeneration(pendingPath);
        if (pending.Snapshot is not { } snapshot)
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.InvalidPendingSnapshot);
        }

        if (CatalogCommitVerifier.HasUnresolvedRollbackArtifact(roots))
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.SafetyBackupFailed);
        }

        CatalogPendingRestoreError recovered =
            CatalogDefectRestoreTransaction.RecoverInterruptedActivation(
                roots,
                marker.DirectoryName,
                pending.Manifest!,
                out CatalogDefectRestoreTransaction? resumedTransaction);
        if (recovered != CatalogPendingRestoreError.None)
        {
            return CatalogPendingRestoreApplicationResult.Failure(recovered);
        }

        CatalogReadResult current = SqliteCatalogStore.Read(roots.CatalogPath);
        if (current.Error is
            CatalogStoreError.UnsupportedCatalogVersion or
            CatalogStoreError.UnsupportedStorageVersion)
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.UnsupportedCurrentCatalog,
                current.ObservedVersion);
        }
        if (current.Snapshot is { })
        {
            if (resumedTransaction is null)
            {
                CatalogBackupCreateResult safetyBackup = CatalogBackupStore.Create(
                    roots,
                    now,
                    CatalogBackupStore.DefaultRetentionCount);
                if (!safetyBackup.IsSuccess)
                {
                    return CatalogPendingRestoreApplicationResult.Failure(
                        MapSafetyBackupError(safetyBackup.Error));
                }
            }
        }
        else if (current.Error == CatalogStoreError.NotFound)
        {
            if (CatalogCommitVerifier.HasBlockingArtifactWhenPrimaryMissing(roots) ||
                DefectSidecarStore.HasAnyArtifact(roots))
            {
                return CatalogPendingRestoreApplicationResult.Failure(
                    CatalogPendingRestoreError.SafetyBackupFailed);
            }
        }
        else
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                current.Error == CatalogStoreError.AccessDenied
                    ? CatalogPendingRestoreError.AccessDenied
                    : CatalogPendingRestoreError.SafetyBackupFailed);
        }

        CatalogDefectRestoreTransaction defectTransaction;
        if (resumedTransaction is { } resumed)
        {
            defectTransaction = resumed;
        }
        else
        {
            CatalogPendingRestoreError prepared = CatalogDefectRestoreTransaction.TryPrepare(
                roots,
                pendingPath,
                marker.DirectoryName,
                pending.Manifest!,
                out defectTransaction);
            if (prepared != CatalogPendingRestoreError.None)
            {
                return CatalogPendingRestoreApplicationResult.Failure(prepared);
            }
        }
        CatalogPendingRestoreError activated = defectTransaction.Activate();
        if (activated != CatalogPendingRestoreError.None)
        {
            _ = defectTransaction.CleanupCommitted();
            return CatalogPendingRestoreApplicationResult.Failure(activated);
        }

        CatalogWriteResult applied = CatalogCommitVerifier.Commit(snapshot, roots);
        if (!applied.IsSuccess)
        {
            _ = defectTransaction.Rollback();
            return CatalogPendingRestoreApplicationResult.Failure(
                applied.Error == CatalogStoreError.AccessDenied
                    ? CatalogPendingRestoreError.AccessDenied
                    : CatalogPendingRestoreError.ApplyFailed);
        }

        DefectCatalogHealthResult appliedHealth =
            DefectSidecarStore.ValidateCatalogDeclarations(roots, snapshot);
        if (!appliedHealth.IsHealthy)
        {
            return CatalogPendingRestoreApplicationResult.Failure(
                RestorePreviousState(
                    roots,
                    current,
                    snapshot,
                    defectTransaction)
                    ? CatalogPendingRestoreError.ApplyFailed
                    : CatalogPendingRestoreError.SafetyBackupFailed);
        }

        try
        {
            CatalogPendingRestoreMarker appliedMarker = marker with
            {
                Version = CatalogPendingRestoreMarker.CurrentVersion,
                Phase = CatalogPendingRestorePhase.Applied,
            };
            CatalogPendingRestoreFiles.WriteMarkerAtomic(roots, appliedMarker);
            _ = defectTransaction.CleanupCommitted();
            bool cleaned = RunCleanup(roots, appliedMarker, cleanup);
            return CatalogPendingRestoreApplicationResult.Success(
                cleaned
                    ? CatalogPendingRestoreApplicationKind.Applied
                    : CatalogPendingRestoreApplicationKind.CleanupPending,
                marker.SourceGenerationId,
                didApplyRestore: true);
        }
        catch (UnauthorizedAccessException)
        {
            _ = RestorePreviousState(
                roots,
                current,
                snapshot,
                defectTransaction);
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.AccessDenied);
        }
        catch (Exception error) when (error is
            IOException or NotSupportedException or ArgumentException)
        {
            _ = RestorePreviousState(
                roots,
                current,
                snapshot,
                defectTransaction);
            return CatalogPendingRestoreApplicationResult.Failure(
                CatalogPendingRestoreError.IoFailure);
        }
    }

    private static bool RestorePreviousState(
        StorageRootSet roots,
        CatalogReadResult previous,
        CatalogSnapshot applied,
        CatalogDefectRestoreTransaction defectTransaction)
    {
        bool defectsRestored = defectTransaction.Rollback();
        bool catalogRestored = previous.Snapshot is { } previousSnapshot
            ? CatalogCommitVerifier.Commit(previousSnapshot, roots).IsSuccess
            : previous.Error == CatalogStoreError.NotFound &&
              CatalogCommitVerifier.RemovePrimaryIfMatches(applied, roots);
        return defectsRestored && catalogRestored;
    }

    private static CatalogPendingRestoreError MapSafetyBackupError(
        CatalogBackupError error) => error switch
    {
        CatalogBackupError.DefectSidecarUnavailable =>
            CatalogPendingRestoreError.DefectSidecarUnavailable,
        CatalogBackupError.AccessDenied => CatalogPendingRestoreError.AccessDenied,
        CatalogBackupError.InvalidStorageRoots =>
            CatalogPendingRestoreError.InvalidStorageRoots,
        _ => CatalogPendingRestoreError.SafetyBackupFailed,
    };

    private static bool RunCleanup(
        StorageRootSet roots,
        CatalogPendingRestoreMarker marker,
        CatalogPendingRestoreCleanup cleanup)
    {
        try
        {
            if (!CatalogDefectRestoreTransaction.CleanupArtifacts(
                    roots,
                    marker.DirectoryName))
            {
                return false;
            }
            string pendingPath = Path.Combine(
                roots.PendingRestoreRoot,
                marker.DirectoryName);
            if (File.Exists(pendingPath) || Directory.Exists(pendingPath))
            {
                cleanup.RemoveDirectory(pendingPath);
            }
            string markerPath = CatalogPendingRestoreFiles.MarkerPath(roots);
            if (File.Exists(markerPath) || Directory.Exists(markerPath))
            {
                cleanup.RemoveMarker(markerPath);
            }
            return true;
        }
        catch (Exception error) when (error is
            IOException or UnauthorizedAccessException or NotSupportedException or
            ArgumentException)
        {
            return false;
        }
    }
}
