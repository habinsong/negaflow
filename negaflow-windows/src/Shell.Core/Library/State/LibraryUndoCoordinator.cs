using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>라이브러리 전체 변경 상태의 undo/redo 스냅샷을 소유합니다.</summary>
internal sealed class LibraryUndoCoordinator(LibraryDocumentState state)
{
    private readonly LibraryUndoStack undoStack = new();

    public bool CanUndo => undoStack.CanUndo;

    public bool CanRedo => undoStack.CanRedo;

    public string? UndoActionName => undoStack.UndoActionName;

    public string? RedoActionName => undoStack.RedoActionName;

    public void CaptureUndo(string actionName)
    {
        ArgumentException.ThrowIfNullOrEmpty(actionName);
        undoStack.Push(Capture(actionName));
    }

    public string? Undo()
    {
        if (undoStack.Undo(Capture(string.Empty)) is not { } restored)
        {
            return null;
        }
        Restore(restored);
        return restored.ActionName;
    }

    public string? Redo()
    {
        if (undoStack.Redo(Capture(string.Empty)) is not { } restored)
        {
            return null;
        }
        Restore(restored);
        return restored.ActionName;
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

    private void Restore(LibraryUndoSnapshot snapshot)
    {
        state.RowIds.Clear();
        state.RowIds.AddRange(snapshot.RowIds);
        state.Payloads.Clear();
        state.Payloads.AddRange(
            snapshot.Payloads.Select(payload => (JsonObject)payload.DeepClone()));
        state.RetainedRows.Clear();
        foreach ((CatalogEntityTable table, IReadOnlyList<CatalogEntityRow> rows) in
                 snapshot.RetainedRows)
        {
            state.RetainedRows[table] = LibraryDocumentState.CloneRows(rows);
        }
        state.DefectRecipes.Clear();
        foreach ((string frameId, DefectRecipeSnapshot recipe) in snapshot.DefectRecipes)
        {
            state.DefectRecipes[frameId] = recipe;
        }
        state.ActiveRollId = snapshot.ActiveRollId;
        state.ProjectAll();
    }
}
