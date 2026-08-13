namespace Negaflow.Shell;

/// <summary>
/// 라이브러리 헤더의 빠른 필터입니다. macOS <c>LibraryQuickFilterState</c> 와 같은 축이며,
/// 조건은 전부 AND 로 걸립니다.
/// </summary>
/// <remarks>
/// macOS 의 <c>currentRoll</c> 과 <c>unvalidatedProfile</c> 은 아직 없습니다. 각각 storage
/// group/scan session 과 스캐너 프로파일 검증 상태를 catalog projection 이 읽어야 하는데 둘 다
/// 아직 투영되지 않습니다. 데이터 없이 토글만 만들면 눌러도 아무 일이 없는 컨트롤이 되므로
/// 만들지 않았습니다.
/// </remarks>
public sealed record LibraryQuickFilterState
{
    public int? MinimumRating { get; init; }

    public bool Picked { get; init; }

    public bool Rejected { get; init; }

    public bool Offline { get; init; }

    public bool Infrared { get; init; }

    public bool DefectRecipe { get; init; }

    /// <summary>
    /// 원본의 크기·화소 수를 아직 기록하지 못한 frame 입니다. macOS 의
    /// <c>metadata(field: .snapshot, presence: .unknown)</c> 과 같은 조건이며, 이 값이 없으면
    /// relink 가 다른 사진을 같은 자리에 연결하는 것을 막지 못합니다.
    /// </summary>
    public bool MetadataUnknown { get; init; }

    public bool IsActive =>
        MinimumRating is not null || Picked || Rejected || Offline || Infrared ||
        DefectRecipe || MetadataUnknown;

    public static LibraryQuickFilterState None { get; } = new();

    public IReadOnlyList<LibraryFrameListItem> Apply(IReadOnlyList<LibraryFrameListItem> items)
    {
        ArgumentNullException.ThrowIfNull(items);
        if (!IsActive)
        {
            return items;
        }
        List<LibraryFrameListItem> matched = [];
        foreach (LibraryFrameListItem item in items)
        {
            if (Matches(item))
            {
                matched.Add(item);
            }
        }
        return matched;
    }

    private bool Matches(LibraryFrameListItem item)
    {
        if (MinimumRating is { } minimum && item.Frame.Rating < Math.Clamp(minimum, 1, 5))
        {
            return false;
        }
        // macOS 는 두 깃발을 하나의 "이 중 아무거나" 조건으로 묶습니다 — 둘 다 켜면 둘 다 보입니다.
        if ((Picked || Rejected) && !(
                (Picked && item.Frame.PickState == Catalog.FramePickState.Picked) ||
                (Rejected && item.Frame.PickState == Catalog.FramePickState.Rejected)))
        {
            return false;
        }
        if (Offline && !item.IsSourceOffline)
        {
            return false;
        }
        if (Infrared && string.IsNullOrEmpty(item.Frame.InfraredPath))
        {
            return false;
        }
        if (DefectRecipe && item.Frame.DefectRecipe is null)
        {
            return false;
        }
        return !MetadataUnknown || item.Frame.SourceMetadata is null;
    }
}
