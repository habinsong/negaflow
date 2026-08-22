namespace Negaflow.Shell;

/// <summary>누를 때 함께 누른 글쇠입니다. macOS <c>NSEvent.ModifierFlags</c> 자리입니다.</summary>
[Flags]
public enum LibrarySelectionModifiers
{
    None = 0,

    /// <summary>이어 고르기입니다. macOS 도 Shift 입니다.</summary>
    Shift = 1,

    /// <summary>하나씩 더하고 빼기입니다. macOS 는 Command, Windows 는 Ctrl 입니다.</summary>
    Toggle = 2,
}

/// <summary>
/// 여러 장 고르기입니다. macOS <c>AppModel.selectFrame(_:orderedFrameIDs:modifiers:)</c> 를
/// 그대로 옮긴 것입니다.
/// </summary>
/// <remarks>
/// 규칙은 셋뿐입니다.
/// <list type="number">
/// <item>Shift 는 <b>기준점</b>에서 누른 칸까지를 통째로 고릅니다.</item>
/// <item>Ctrl 은 누른 칸 하나만 더하거나 뺍니다. 기준점은 그 칸이 됩니다.</item>
/// <item>아무것도 안 누르면 그 칸 하나만 남습니다.</item>
/// </list>
/// 기준점(<c>frameSelectionAnchorID</c>)이 없으면 Shift 도 한 장 고르기로 떨어집니다 —
/// macOS 도 그렇습니다.
/// </remarks>
public sealed record LibraryFrameSelectionCommand(
    IReadOnlyList<string> SelectedFrameIds,
    string? ActiveFrameId,
    string? AnchorFrameId)
{
    /// <summary>
    /// 누른 칸과 글쇠로 새 선택을 냅니다. <paramref name="orderedFrameIds"/> 는 화면에 보이는
    /// 차례여야 합니다 — Shift 범위가 그 차례를 따릅니다.
    /// </summary>
    public static LibraryFrameSelectionCommand Apply(
        string frameId,
        IReadOnlyList<string> orderedFrameIds,
        IReadOnlyList<string> currentSelection,
        string? currentActiveFrameId,
        string? anchorFrameId,
        LibrarySelectionModifiers modifiers)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(orderedFrameIds);
        ArgumentNullException.ThrowIfNull(currentSelection);
        // 화면에 없는 칸은 고를 수 없습니다. macOS `guard orderedFrameIDs.contains(frame.id)`.
        int targetIndex = IndexOf(orderedFrameIds, frameId);
        if (targetIndex < 0)
        {
            return new LibraryFrameSelectionCommand(
                currentSelection,
                currentActiveFrameId,
                anchorFrameId);
        }

        if (modifiers.HasFlag(LibrarySelectionModifiers.Shift) &&
            anchorFrameId is not null &&
            IndexOf(orderedFrameIds, anchorFrameId) is int anchorIndex and >= 0)
        {
            int start = Math.Min(anchorIndex, targetIndex);
            int end = Math.Max(anchorIndex, targetIndex);
            string[] range = [.. orderedFrameIds.Skip(start).Take(end - start + 1)];
            // 기준점은 그대로 둡니다 — 이어서 Shift 를 누르면 같은 자리에서 범위가 자랍니다.
            return new LibraryFrameSelectionCommand(range, frameId, anchorFrameId);
        }

        if (modifiers.HasFlag(LibrarySelectionModifiers.Toggle))
        {
            List<string> next = [.. currentSelection];
            bool wasSelected = next.RemoveAll(id =>
                string.Equals(id, frameId, StringComparison.Ordinal)) > 0;
            if (!wasSelected)
            {
                next.Add(frameId);
            }
            // 뺀 칸이 활성이었으면 남은 것 가운데 화면 차례가 가장 앞선 것으로 옮깁니다.
            string? active = !wasSelected
                ? frameId
                : currentActiveFrameId is not null &&
                    next.Contains(currentActiveFrameId, StringComparer.Ordinal)
                        ? currentActiveFrameId
                        : orderedFrameIds.FirstOrDefault(id =>
                            next.Contains(id, StringComparer.Ordinal));
            return new LibraryFrameSelectionCommand(next, active, frameId);
        }

        return new LibraryFrameSelectionCommand([frameId], frameId, frameId);
    }

    private static int IndexOf(IReadOnlyList<string> ids, string frameId)
    {
        for (int index = 0; index < ids.Count; ++index)
        {
            if (string.Equals(ids[index], frameId, StringComparison.Ordinal))
            {
                return index;
            }
        }
        return -1;
    }
}
