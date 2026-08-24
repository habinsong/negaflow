using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 되돌릴 수 있는 카탈로그 상태 한 장입니다.
/// </summary>
/// <remarks>
/// 연산마다 역연산을 따로 쓰지 않고 **바뀌기 직전 상태를 통째로** 담습니다. 역연산은 열 가지
/// 연산에 열 가지 실수 자리를 만들지만, 상태 복원은 한 자리뿐입니다. 카탈로그 한 장은 사진
/// 수백 장이어도 수 MB 이므로 이 선택이 값싸게 옳습니다.
/// </remarks>
internal sealed record LibraryUndoSnapshot(
    string ActionName,
    List<string> RowIds,
    List<JsonObject> Payloads,
    Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> RetainedRows,
    Dictionary<string, DefectRecipeSnapshot> DefectRecipes,
    string? ActiveRollId,
    string? DefectFrameId = null,
    LibraryDefectHistoryMode? DefectHistoryMode = null,
    LibraryFrameRemoval? RemovedFrames = null);

internal enum LibraryDefectHistoryMode
{
    PreservingInfrared,
    Exact,
}

/// <summary>
/// 되돌리기·다시 실행 더미입니다. macOS 는 AppKit <c>UndoManager</c> 를 쓰고, 여기서는 같은
/// 자리를 이 클래스가 맡습니다.
/// </summary>
internal sealed class LibraryUndoStack
{
    /// <summary>
    /// 담아 둘 단계 수입니다. 무제한으로 두면 긴 편집 뒤 메모리가 카탈로그 크기의 몇 배로
    /// 불어납니다.
    /// </summary>
    public const int MaximumDepth = 20;

    private readonly LinkedList<LibraryUndoSnapshot> undo = new();
    private readonly LinkedList<LibraryUndoSnapshot> redo = new();

    public bool CanUndo => undo.Count > 0;

    public bool CanRedo => redo.Count > 0;

    /// <summary>되돌릴 동작의 이름입니다. 없으면 null 입니다.</summary>
    public string? UndoActionName => undo.Last?.Value.ActionName;

    public string? RedoActionName => redo.Last?.Value.ActionName;

    public LibraryUndoSnapshot? PeekUndo() => undo.Last?.Value;

    public LibraryUndoSnapshot? PeekRedo() => redo.Last?.Value;

    public bool CanUndoDefectFrame(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        foreach (LibraryUndoSnapshot snapshot in undo)
        {
            if (string.Equals(snapshot.DefectFrameId, frameId, StringComparison.Ordinal))
            {
                return true;
            }
        }
        return false;
    }

    /// <summary>
    /// 새 편집을 담습니다. **다시 실행 더미는 지웁니다** — 되돌린 뒤 다른 길로 갔으면 옛 앞길은
    /// 더 이상 이 상태에서 이어지지 않습니다.
    /// </summary>
    public LibraryFrameRemoval Push(LibraryUndoSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        List<LibraryFrameRemoval> discarded = redo
            .Select(candidate => candidate.RemovedFrames)
            .OfType<LibraryFrameRemoval>()
            .ToList();
        redo.Clear();
        undo.AddLast(snapshot);
        while (undo.Count > MaximumDepth)
        {
            if (undo.First!.Value.RemovedFrames is { } removal)
            {
                discarded.Add(removal);
            }
            undo.RemoveFirst();
        }
        return MergeRemovals(discarded);
    }

    /// <summary>
    /// 한 단계 되돌립니다. 부르는 쪽은 <paramref name="current"/> 에 지금 상태를 주어야 합니다 —
    /// 그것이 다시 실행할 자리가 됩니다.
    /// </summary>
    public LibraryUndoSnapshot? Undo(LibraryUndoSnapshot current)
    {
        ArgumentNullException.ThrowIfNull(current);
        if (undo.Last is not { } last)
        {
            return null;
        }
        undo.RemoveLast();
        redo.AddLast(current with
        {
            ActionName = last.Value.ActionName,
            DefectFrameId = last.Value.DefectFrameId,
            DefectHistoryMode = last.Value.DefectHistoryMode,
            RemovedFrames = last.Value.RemovedFrames,
        });
        return last.Value;
    }

    public LibraryUndoSnapshot? Redo(LibraryUndoSnapshot current)
    {
        ArgumentNullException.ThrowIfNull(current);
        if (redo.Last is not { } last)
        {
            return null;
        }
        redo.RemoveLast();
        undo.AddLast(current with
        {
            ActionName = last.Value.ActionName,
            DefectFrameId = last.Value.DefectFrameId,
            DefectHistoryMode = last.Value.DefectHistoryMode,
            RemovedFrames = last.Value.RemovedFrames,
        });
        return last.Value;
    }

    public void Clear()
    {
        undo.Clear();
        redo.Clear();
    }

    public LibraryFrameRemoval RemovalCandidates() => MergeRemovals(
        undo.Concat(redo)
            .Select(snapshot => snapshot.RemovedFrames)
            .OfType<LibraryFrameRemoval>());

    public bool ReferencesRemoval(Guid frameId) => undo.Concat(redo).Any(snapshot =>
        snapshot.RemovedFrames?.DefectSidecars.Any(sidecar => sidecar.FrameId == frameId) == true);

    public void RemoveDefectFrame(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        RemoveDefectFrame(undo, frameId);
        RemoveDefectFrame(redo, frameId);
    }

    private static void RemoveDefectFrame(
        LinkedList<LibraryUndoSnapshot> snapshots,
        string frameId)
    {
        LinkedListNode<LibraryUndoSnapshot>? node = snapshots.First;
        while (node is not null)
        {
            LinkedListNode<LibraryUndoSnapshot>? next = node.Next;
            if (string.Equals(node.Value.DefectFrameId, frameId, StringComparison.Ordinal))
            {
                snapshots.Remove(node);
            }
            node = next;
        }
    }

    private static LibraryFrameRemoval MergeRemovals(
        IEnumerable<LibraryFrameRemoval> removals)
    {
        Dictionary<Guid, ulong> sidecars = [];
        HashSet<string> frames = new(StringComparer.Ordinal);
        foreach (LibraryFrameRemoval removal in removals)
        {
            frames.UnionWith(removal.FrameIds);
            foreach ((Guid frameId, ulong revision) in removal.DefectSidecars)
            {
                sidecars[frameId] = Math.Max(sidecars.GetValueOrDefault(frameId), revision);
            }
        }
        return new LibraryFrameRemoval(
            [.. frames],
            [.. sidecars.Select(pair => (pair.Key, pair.Value))]);
    }
}
