using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal readonly record struct LibraryHistoryResult(
    string? ActionName,
    CatalogStoreError CatalogError,
    DefectSidecarError SidecarError)
{
    public bool RequiresRecovery => CatalogError == CatalogStoreError.RollbackFailed;
}

/// <summary>라이브러리 전체 변경 상태의 undo/redo 스냅샷을 소유합니다.</summary>
internal sealed class LibraryUndoCoordinator(
    LibraryDocumentState state,
    LibraryDefectRecipeStore defectRecipeStore,
    Func<CatalogStoreError> saveCatalog)
{
    private readonly LibraryUndoStack undoStack = new();
    private readonly Dictionary<Guid, ulong> pendingOrphans = [];
    private readonly Func<CatalogStoreError> saveCatalog =
        saveCatalog ?? throw new ArgumentNullException(nameof(saveCatalog));

    public bool CanUndo => undoStack.CanUndo;

    public bool CanRedo => undoStack.CanRedo;

    public string? UndoActionName => undoStack.UndoActionName;

    public string? RedoActionName => undoStack.RedoActionName;

    public bool CanUndoDefectFrame(string frameId) =>
        undoStack.CanUndoDefectFrame(frameId);

    public void RemoveDefectFrame(string frameId) =>
        undoStack.RemoveDefectFrame(frameId);

    public void CaptureUndo(string actionName)
    {
        ArgumentException.ThrowIfNullOrEmpty(actionName);
        QueueDiscarded(undoStack.Push(Capture(actionName)));
    }

    public LibraryUndoSnapshot CapturePendingRemovalUndo(string actionName)
    {
        ArgumentException.ThrowIfNullOrEmpty(actionName);
        return Capture(actionName);
    }

    public LibraryUndoSnapshot CaptureTransientState() => Capture(string.Empty);

    public void RestoreTransientState(LibraryUndoSnapshot snapshot, bool wasDirty)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        RestoreCatalogState(snapshot);
        state.IsDirty = wasDirty;
    }

    public void CommitPendingRemovalUndo(
        LibraryUndoSnapshot snapshot,
        LibraryFrameRemoval removal)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        ArgumentNullException.ThrowIfNull(removal);
        QueueDiscarded(undoStack.Push(snapshot with { RemovedFrames = removal }));
    }

    public LibraryUndoSnapshot CapturePendingDefectUndo(
        string frameId,
        LibraryDefectHistoryMode mode)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        return Capture(LibraryDefectEditor.UndoActionName) with
        {
            DefectFrameId = frameId,
            DefectHistoryMode = mode,
        };
    }

    public void CommitPendingUndo(LibraryUndoSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        QueueDiscarded(undoStack.Push(snapshot));
    }

    public DefectSidecarError PurgeForTermination()
    {
        Queue(undoStack.RemovalCandidates());
        bool purgedAny = false;
        DefectSidecarError error = PurgePending(ignoreHistory: true, ref purgedAny);
        if (error == DefectSidecarError.None || purgedAny)
        {
            undoStack.Clear();
        }
        return error;
    }

    public LibraryHistoryResult Undo()
    {
        LibraryUndoSnapshot current = Capture(string.Empty);
        bool currentWasDirty = state.IsDirty;
        if (undoStack.PeekUndo() is not { } target)
        {
            return default;
        }
        if (!RestoreForHistory(
                target,
                current,
                currentWasDirty,
                out CatalogStoreError catalogError,
                out DefectSidecarError sidecarError))
        {
            return new(null, catalogError, sidecarError);
        }
        return undoStack.Undo(current) is { } restored
            ? new(restored.ActionName, CatalogStoreError.None, DefectSidecarError.None)
            : default;
    }

    public LibraryHistoryResult Redo()
    {
        LibraryUndoSnapshot current = Capture(string.Empty);
        bool currentWasDirty = state.IsDirty;
        if (undoStack.PeekRedo() is not { } target)
        {
            return default;
        }
        if (!RestoreForHistory(
                target,
                current,
                currentWasDirty,
                out CatalogStoreError catalogError,
                out DefectSidecarError sidecarError))
        {
            return new(null, catalogError, sidecarError);
        }
        return undoStack.Redo(current) is { } restored
            ? new(restored.ActionName, CatalogStoreError.None, DefectSidecarError.None)
            : default;
    }

    private bool RestoreForHistory(
        LibraryUndoSnapshot target,
        LibraryUndoSnapshot current,
        bool currentWasDirty,
        out CatalogStoreError catalogError,
        out DefectSidecarError sidecarError)
    {
        catalogError = CatalogStoreError.None;
        sidecarError = DefectSidecarError.None;
        if (target.DefectFrameId is not { } frameId ||
            target.DefectHistoryMode is not { } mode)
        {
            RestoreCatalogState(target);
            catalogError = saveCatalog();
            if (catalogError == CatalogStoreError.None)
            {
                state.IsDirty = false;
                return true;
            }

            if (catalogError == CatalogStoreError.RollbackFailed)
            {
                // 저장소가 target을 게시했는지조차 확정할 수 없습니다. current를 복원하면 메모리와
                // primary가 다시 갈릴 수 있으므로 Host가 이 결과를 받고 문서를 분리할 때까지
                // target projection을 그대로 두고 추가 저장만 막습니다.
                state.IsDirty = false;
                return false;
            }

            RestoreCatalogState(current);
            state.IsDirty = currentWasDirty;
            return false;
        }

        if (!Guid.TryParseExact(frameId, "D", out Guid parsedFrameId) ||
            parsedFrameId == Guid.Empty)
        {
            return false;
        }

        current.DefectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? currentRecipe);
        target.DefectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? targetRecipe);
        if (currentRecipe is not null && currentRecipe.FrameId != parsedFrameId ||
            targetRecipe is not null && targetRecipe.FrameId != parsedFrameId)
        {
            return false;
        }
        if (currentRecipe?.SourceIdentity is { } currentIdentity &&
            targetRecipe?.SourceIdentity is { } targetIdentity &&
            currentIdentity != targetIdentity)
        {
            return false;
        }

        DefectRecipeSnapshot promoted;
        try
        {
            if (!state.DefectRevisions.TryGetNext(frameId, out ulong nextRevision))
            {
                return false;
            }
            promoted = DefectRecipeSnapshot.Create(
                parsedFrameId,
                nextRevision,
                currentRecipe?.SourceIdentity ?? targetRecipe?.SourceIdentity,
                ResolveDefectItems(targetRecipe?.Items ?? [], currentRecipe?.Items ?? [], mode));
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return false;
        }

        LibraryDefectRecipeWriteResult written = defectRecipeStore.Write(frameId, promoted);
        catalogError = written.CatalogError;
        sidecarError = written.SidecarError;
        return written.IsSuccess;
    }

    private static IReadOnlyList<DefectEditItem> ResolveDefectItems(
        IReadOnlyList<DefectEditItem> target,
        IReadOnlyList<DefectEditItem> current,
        LibraryDefectHistoryMode mode)
    {
        if (mode == LibraryDefectHistoryMode.Exact)
        {
            return target;
        }

        List<DefectEditItem> resolved = target
            .Where(item => item.Kind != DefectEditKind.Infrared)
            .ToList();
        HashSet<Guid> targetInfraredIds = target
            .Where(item => item.Kind == DefectEditKind.Infrared)
            .Select(item => item.Id)
            .ToHashSet();
        for (int index = 0; index < target.Count; ++index)
        {
            DefectEditItem item = target[index];
            if (item.Kind == DefectEditKind.Infrared)
            {
                resolved.Insert(Math.Min(index, resolved.Count), item);
            }
        }
        for (int index = 0; index < current.Count; ++index)
        {
            DefectEditItem item = current[index];
            if (item.Kind == DefectEditKind.Infrared &&
                !targetInfraredIds.Contains(item.Id))
            {
                resolved.Insert(Math.Min(index, resolved.Count), item);
            }
        }
        return resolved;
    }

    private LibraryUndoSnapshot Capture(string actionName) => new(
        actionName,
        [.. state.RowIds],
        [.. state.Payloads.Select(payload => (JsonObject)payload.DeepClone())],
        state.RetainedRows.ToDictionary(
            pair => pair.Key,
            pair => LibraryDocumentState.CloneRows(pair.Value)),
        new Dictionary<string, DefectRecipeSnapshot>(
            state.DefectRecipes,
            StringComparer.Ordinal),
        state.ActiveRollId);

    private void QueueDiscarded(LibraryFrameRemoval removal)
    {
        Queue(removal);
        bool purgedAny = false;
        _ = PurgePending(ignoreHistory: false, ref purgedAny);
    }

    private void Queue(LibraryFrameRemoval removal)
    {
        foreach ((Guid frameId, ulong revision) in removal.DefectSidecars)
        {
            pendingOrphans[frameId] = Math.Max(
                pendingOrphans.GetValueOrDefault(frameId),
                revision);
        }
    }

    private DefectSidecarError PurgePending(bool ignoreHistory, ref bool purgedAny)
    {
        foreach ((Guid frameId, ulong revision) in pendingOrphans.ToArray())
        {
            if (state.IndexById.ContainsKey(frameId.ToString("D")))
            {
                pendingOrphans.Remove(frameId);
                continue;
            }
            if (!ignoreHistory && undoStack.ReferencesRemoval(frameId))
            {
                pendingOrphans.Remove(frameId);
                continue;
            }

            DefectSidecarError error = defectRecipeStore.Purge(frameId, revision);
            if (error != DefectSidecarError.None)
            {
                return error;
            }
            pendingOrphans.Remove(frameId);
            purgedAny = true;
        }
        return DefectSidecarError.None;
    }

    private void RestoreCatalogState(LibraryUndoSnapshot snapshot)
    {
        HashSet<string> currentFrameIds = state.RowIds.ToHashSet(StringComparer.Ordinal);
        HashSet<string> currentDeclarationKeys = [];
        Dictionary<string, JsonNode?> currentDeclarations = new(StringComparer.Ordinal);
        for (int index = 0; index < state.RowIds.Count; ++index)
        {
            if (state.Payloads[index].TryGetPropertyValue(
                    "hasDefectEdits",
                    out JsonNode? declaration))
            {
                currentDeclarationKeys.Add(state.RowIds[index]);
                currentDeclarations[state.RowIds[index]] = declaration?.DeepClone();
            }
        }

        state.RowIds.Clear();
        state.RowIds.AddRange(snapshot.RowIds);
        state.Payloads.Clear();
        state.Payloads.AddRange(
            snapshot.Payloads.Select(payload => (JsonObject)payload.DeepClone()));
        for (int index = 0; index < state.RowIds.Count; ++index)
        {
            string frameId = state.RowIds[index];
            if (!currentFrameIds.Contains(frameId))
            {
                continue;
            }
            if (currentDeclarationKeys.Contains(frameId))
            {
                state.Payloads[index]["hasDefectEdits"] =
                    currentDeclarations[frameId]?.DeepClone();
            }
            else
            {
                state.Payloads[index].Remove("hasDefectEdits");
            }
        }
        state.RetainedRows.Clear();
        foreach ((CatalogEntityTable table, IReadOnlyList<CatalogEntityRow> rows) in
                 snapshot.RetainedRows)
        {
            state.RetainedRows[table] = LibraryDocumentState.CloneRows(rows);
        }
        HashSet<string> restoredFrameIds = snapshot.RowIds.ToHashSet(StringComparer.Ordinal);
        foreach (string frameId in state.DefectRecipes.Keys
                     .Where(frameId => !restoredFrameIds.Contains(frameId))
                     .ToArray())
        {
            state.DefectRecipes.Remove(frameId);
        }
        foreach (string frameId in currentFrameIds.Where(
                     frameId => !restoredFrameIds.Contains(frameId)))
        {
            state.DefectRevisions.Remove(frameId);
        }
        state.ActiveRollId = snapshot.ActiveRollId;
        state.ProjectAll();
    }
}
