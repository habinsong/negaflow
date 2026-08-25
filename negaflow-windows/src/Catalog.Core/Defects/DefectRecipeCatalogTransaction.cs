using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 한 frame의 defect sidecar와 catalog 선언을 함께 게시하거나 함께 되돌립니다.
/// 호출자는 <see cref="CatalogSession"/>의 단일 write gate를 잡은 상태여야 합니다.
/// </summary>
internal sealed class DefectRecipeCatalogTransaction(StorageRootSet roots)
{
    internal DefectRecipeCatalogWriteResult Write(
        DefectRecipeSnapshot recipe,
        CatalogSnapshot catalog,
        Func<CatalogWriteResult> commitCatalog,
        bool forceSidecarRollbackFailure)
    {
        if (recipe.Items.Count == 0 ||
            !CatalogDeclaresDefectEdits(catalog, recipe.FrameId))
        {
            return DefectRecipeCatalogWriteResult.Failure(
                DefectSidecarWriteResult.Failure(DefectSidecarError.InvalidSnapshot),
                CatalogStoreError.MissingAuthoritativeData);
        }

        CatalogReadResult durable = SqliteCatalogStore.Read(roots.CatalogPath);
        if (durable.Snapshot is not { } currentCatalog)
        {
            return DefectRecipeCatalogWriteResult.Failure(
                DefectSidecarWriteResult.Failure(DefectSidecarError.InvalidSnapshot),
                durable.Error);
        }
        if (!IsSafeWriteTransition(currentCatalog, catalog, recipe.FrameId))
        {
            return DefectRecipeCatalogWriteResult.Failure(
                DefectSidecarWriteResult.Failure(DefectSidecarError.InvalidSnapshot),
                CatalogStoreError.MissingAuthoritativeData);
        }

        return DefectSidecarCatalogWriter.Write(
            roots,
            recipe,
            () => DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, catalog) ==
                    DefectSidecarError.None
                ? commitCatalog()
                : CatalogWriteResult.Failure(CatalogStoreError.MissingAuthoritativeData),
            forceSidecarRollbackFailure);
    }

    internal DefectRecipeCatalogDeleteResult Delete(
        Guid frameId,
        ulong deletionRevision,
        CatalogSnapshot catalog) =>
        DeleteCore(frameId, deletionRevision, catalog, allowSourceUpdate: false);

    internal DefectRecipeCatalogDeleteResult DeleteForBake(
        Guid frameId,
        ulong deletionRevision,
        CatalogSnapshot catalog) =>
        DeleteCore(frameId, deletionRevision, catalog, allowSourceUpdate: true);

    private DefectRecipeCatalogDeleteResult DeleteCore(
        Guid frameId,
        ulong deletionRevision,
        CatalogSnapshot catalog,
        bool allowSourceUpdate)
    {
        if (frameId == Guid.Empty || deletionRevision == 0)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        CatalogReadResult durable = SqliteCatalogStore.Read(roots.CatalogPath);
        if (durable.Snapshot is not { } currentCatalog)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                catalogError: durable.Error);
        }
        if (!(allowSourceUpdate
                ? IsSafeBakeDeleteTransition(currentCatalog, catalog, frameId)
                : IsSafeDeleteTransition(currentCatalog, catalog, frameId)))
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                DefectSidecarError.InvalidSnapshot,
                CatalogStoreError.MissingAuthoritativeData);
        }

        DefectSidecarReadResult currentSidecar = DefectSidecarStore.Read(roots, frameId);
        if (currentSidecar.Snapshot is not { } currentRecipe)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                currentSidecar.Error);
        }
        if (currentRecipe.RecipeRevision == ulong.MaxValue ||
            deletionRevision != currentRecipe.RecipeRevision + 1UL)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }

        if (DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, catalog) !=
            DefectSidecarError.None)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                catalogError: CatalogStoreError.MissingAuthoritativeData);
        }
        CatalogWriteResult committed = CatalogCommitVerifier.Commit(catalog, roots);
        if (!committed.IsSuccess)
        {
            return DefectRecipeCatalogDeleteResult.Failure(
                catalogError: committed.Error);
        }

        DefectSidecarDeleteResult deleted =
            DefectSidecarStore.Remove(roots, frameId, deletionRevision);
        if (deleted.IsSuccess)
        {
            return DefectRecipeCatalogDeleteResult.Success();
        }

        if (DefectSidecarCatalogHealth.ValidateDeclaredSidecars(
                roots,
                currentCatalog) == DefectSidecarError.None &&
            CatalogCommitVerifier.Commit(currentCatalog, roots).IsSuccess)
        {
            return DefectRecipeCatalogDeleteResult.Failure(deleted.Error);
        }

        CatalogCommitRollback.RecordRollbackFailure(roots);
        return DefectRecipeCatalogDeleteResult.Failure(
            deleted.Error,
            CatalogStoreError.RollbackFailed);
    }

    internal DefectSidecarDeleteResult RemoveUndeclared(
        Guid frameId,
        ulong minimumRevision)
    {
        CatalogReadResult current = SqliteCatalogStore.Read(roots.CatalogPath);
        if (current.Snapshot is not { } snapshot ||
            CatalogDeclaresDefectEdits(snapshot, frameId))
        {
            return DefectSidecarDeleteResult.Failure(
                DefectSidecarError.InvalidSnapshot);
        }
        return DefectSidecarStore.Remove(roots, frameId, minimumRevision);
    }

    private static bool IsSafeWriteTransition(
        CatalogSnapshot current,
        CatalogSnapshot target,
        Guid frameId)
    {
        if (CatalogCommitVerifier.SnapshotsMatch(current, target))
        {
            return CatalogDeclaresDefectEdits(target, frameId);
        }
        return !CatalogDeclaresDefectEdits(current, frameId) &&
            CatalogDeclaresDefectEdits(target, frameId) &&
            (IsOnlyTargetFramePayloadChange(
                 current,
                 target,
                 frameId,
                 "hasDefectEdits") ||
             IsOnlyTargetFrameAdded(current, target, frameId));
    }

    private static bool IsOnlyTargetFrameAdded(
        CatalogSnapshot current,
        CatalogSnapshot target,
        Guid frameId)
    {
        IReadOnlyList<CatalogEntityRow> currentFrames =
            current.Rows(CatalogEntityTable.Frames);
        IReadOnlyList<CatalogEntityRow> targetFrames =
            target.Rows(CatalogEntityTable.Frames);
        int targetIndex = FindUniqueFrameIndex(targetFrames, frameId);
        if (targetIndex < 0 || targetFrames.Count != currentFrames.Count + 1)
        {
            return false;
        }

        List<CatalogEntityRow> withoutAdded = targetFrames.ToList();
        withoutAdded.RemoveAt(targetIndex);
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> normalizedTables =
            CatalogEntityTables.All.ToDictionary(
                table => table,
                table => table == CatalogEntityTable.Frames
                    ? (IReadOnlyList<CatalogEntityRow>)withoutAdded
                    : target.Rows(table));
        CatalogSnapshot normalized = new(
            target.CatalogVersion,
            target.MinimumReaderVersion,
            target.ActiveRollId,
            normalizedTables);
        return CatalogCommitVerifier.SnapshotsMatch(current, normalized);
    }

    private static bool IsSafeDeleteTransition(
        CatalogSnapshot current,
        CatalogSnapshot target,
        Guid frameId) =>
        CatalogDeclaresDefectEdits(current, frameId) &&
        !CatalogDeclaresDefectEdits(target, frameId) &&
        IsOnlyTargetFramePayloadChange(
            current,
            target,
            frameId,
            "hasDefectEdits",
            DefectReviewTrackingCodec.TrackingName);

    private static bool IsSafeBakeDeleteTransition(
        CatalogSnapshot current,
        CatalogSnapshot target,
        Guid frameId) =>
        CatalogDeclaresDefectEdits(current, frameId) &&
        !CatalogDeclaresDefectEdits(target, frameId) &&
        IsOnlyTargetFramePayloadChange(
            current,
            target,
            frameId,
            "hasDefectEdits",
            DefectReviewTrackingCodec.TrackingName,
            LibraryFrameReader.SourcePathName,
            LibraryFrameReader.SourceMetadataName);

    private static bool IsOnlyTargetFramePayloadChange(
        CatalogSnapshot current,
        CatalogSnapshot target,
        Guid frameId,
        params string[] allowedProperties)
    {
        IReadOnlyList<CatalogEntityRow> currentFrames =
            current.Rows(CatalogEntityTable.Frames);
        IReadOnlyList<CatalogEntityRow> targetFrames =
            target.Rows(CatalogEntityTable.Frames);
        int currentIndex = FindUniqueFrameIndex(currentFrames, frameId);
        int targetIndex = FindUniqueFrameIndex(targetFrames, frameId);
        if (currentIndex < 0 || targetIndex < 0)
        {
            return false;
        }

        JsonObject normalizedPayload =
            (JsonObject)targetFrames[targetIndex].Payload.DeepClone();
        foreach (string property in allowedProperties)
        {
            if (currentFrames[currentIndex].Payload.TryGetPropertyValue(
                    property,
                    out JsonNode? currentValue))
            {
                normalizedPayload[property] = currentValue?.DeepClone();
            }
            else
            {
                normalizedPayload.Remove(property);
            }
        }

        List<CatalogEntityRow> normalizedFrames = targetFrames.ToList();
        normalizedFrames[targetIndex] = new CatalogEntityRow(
            targetFrames[targetIndex].Id,
            normalizedPayload);
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> normalizedTables =
            CatalogEntityTables.All.ToDictionary(
                table => table,
                table => table == CatalogEntityTable.Frames
                    ? (IReadOnlyList<CatalogEntityRow>)normalizedFrames
                    : target.Rows(table));
        CatalogSnapshot normalized = new(
            target.CatalogVersion,
            target.MinimumReaderVersion,
            target.ActiveRollId,
            normalizedTables);
        return CatalogCommitVerifier.SnapshotsMatch(current, normalized);
    }

    private static int FindUniqueFrameIndex(
        IReadOnlyList<CatalogEntityRow> frames,
        Guid frameId)
    {
        string expected = frameId.ToString("D");
        int found = -1;
        for (int index = 0; index < frames.Count; ++index)
        {
            if (!string.Equals(
                    frames[index].Id,
                    expected,
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            if (found >= 0)
            {
                return -1;
            }
            found = index;
        }
        return found;
    }

    private static bool CatalogDeclaresDefectEdits(
        CatalogSnapshot snapshot,
        Guid frameId)
    {
        int index = FindUniqueFrameIndex(
            snapshot.Rows(CatalogEntityTable.Frames),
            frameId);
        if (index < 0)
        {
            return false;
        }
        JsonObject payload = snapshot.Rows(CatalogEntityTable.Frames)[index].Payload;
        return payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) &&
            node is JsonValue value &&
            value.TryGetValue(out bool hasEdits) &&
            hasEdits;
    }
}
