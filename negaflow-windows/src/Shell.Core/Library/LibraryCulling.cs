namespace Negaflow.Shell;

/// <summary>
/// 격자 대신 무엇을 보여 줄지입니다. macOS <c>LibraryCullingMode</c> 와 같은 셋입니다.
/// </summary>
public enum LibraryCullingMode
{
    Grid,
    Compare,
    Survey,
}

/// <summary>
/// 훑어보기 화면에 올릴 사진을 고릅니다.
/// </summary>
/// <remarks>
/// 순서는 **격자에 보이는 차례**를 따릅니다 — 고른 차례가 아닙니다. 정렬을 바꾼 뒤 비교를 열면
/// 왼쪽·오른쪽이 화면과 같은 차례로 놓여야 사용자가 어느 쪽이 어느 쪽인지 압니다.
/// </remarks>
public static class LibraryCullingProjection
{
    /// <summary>고른 사진들을 격자 차례로 늘어놓습니다. 중복 id 는 한 번만 셉니다.</summary>
    public static IReadOnlyList<string> SelectedFrameIds(
        IReadOnlyList<string> orderedFrameIds,
        IReadOnlyCollection<string> selectedFrameIds)
    {
        ArgumentNullException.ThrowIfNull(orderedFrameIds);
        ArgumentNullException.ThrowIfNull(selectedFrameIds);
        var selected = new HashSet<string>(selectedFrameIds, StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        return [.. orderedFrameIds.Where(id => selected.Contains(id) && seen.Add(id))];
    }

    /// <summary>
    /// 비교에 올릴 두 장입니다. 기준이 앞, 후보가 뒤입니다. 두 장이 안 되면 빈 목록입니다 —
    /// 한 장짜리 비교는 비교가 아닙니다.
    /// </summary>
    /// <remarks>
    /// 후보는 **지금 활성인 사진**이며, 활성이 고른 것들 밖이면 두 번째를 씁니다. 기준은 후보가
    /// 아닌 첫 사진입니다 — 그래야 활성만 바꿔 가며 같은 기준과 견줄 수 있습니다.
    /// </remarks>
    public static IReadOnlyList<string> CompareFrameIds(
        IReadOnlyList<string> orderedFrameIds,
        IReadOnlyCollection<string> selectedFrameIds,
        string? activeFrameId)
    {
        IReadOnlyList<string> selected = SelectedFrameIds(orderedFrameIds, selectedFrameIds);
        if (selected.Count < 2)
        {
            return [];
        }
        string candidate = activeFrameId is not null &&
            selected.Contains(activeFrameId, StringComparer.Ordinal)
                ? activeFrameId
                : selected[1];
        string? reference = selected.FirstOrDefault(id =>
            !string.Equals(id, candidate, StringComparison.Ordinal));
        return reference is null ? [] : [reference, candidate];
    }
}
