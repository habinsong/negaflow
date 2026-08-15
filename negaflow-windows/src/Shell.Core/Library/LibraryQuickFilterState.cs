namespace Negaflow.Shell;

/// <summary>
/// 라이브러리 헤더의 빠른 필터입니다. macOS <c>LibraryQuickFilterState</c> 와 같은 축이며,
/// 조건은 전부 AND 로 걸립니다.
/// </summary>
/// <remarks>
/// 여덟 축 모두 macOS 와 같은 이름·같은 뜻이며, 화면의 차례도 macOS
/// <c>LibraryBrowserFilterBar</c> 와 같습니다.
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

    /// <summary>
    /// 아직 쌍 비교로 검증되지 않은 스캐너 프로파일이 걸린 사진입니다. macOS 는
    /// <c>scannerProfileState(isAnyOf: [.missing, .draft, .realOnly, .pairedSmoke])</c> 입니다 —
    /// 그 목록에 <c>none</c> 은 <b>없습니다</b>. 프로파일을 아예 고르지 않은 사진은 검증할
    /// 프로파일 자체가 없으므로 걸리지 않습니다.
    /// </summary>
    public bool UnvalidatedProfile { get; init; }

    /// <summary>
    /// 지금 스캔 중인 롤의 사진만 봅니다. 활성 롤이 없으면 이 축은 아무 것도 걸러내지
    /// 않습니다 — 켠 순간 격자가 비면 사용자는 사진이 사라졌다고 읽습니다.
    /// </summary>
    public bool CurrentRoll { get; init; }

    /// <summary>활성 롤에 속한 frame id 입니다. 비면 이 축은 꺼진 것과 같습니다.</summary>
    public IReadOnlyList<string> CurrentRollFrameIds { get; init; } = [];

    public bool IsActive =>
        MinimumRating is not null || Picked || Rejected || Offline || Infrared ||
        DefectRecipe || MetadataUnknown || UnvalidatedProfile || IsCurrentRollActive;

    private bool IsCurrentRollActive => CurrentRoll && CurrentRollFrameIds.Count > 0;

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
        if (MetadataUnknown && item.Frame.SourceMetadata is not null)
        {
            return false;
        }
        if (UnvalidatedProfile && !IsUnvalidatedProfile(item.Frame.Base.ScannerProfileId))
        {
            return false;
        }
        return !IsCurrentRollActive ||
            CurrentRollFrameIds.Contains(item.Frame.Id, StringComparer.Ordinal);
    }

    /// <summary>
    /// 이 프로파일 id 가 macOS 의 "검증되지 않음" 네 상태 중 하나인지.
    /// </summary>
    /// <remarks>
    /// 지금 함께 나가는 15개는 모두 <c>realOnly</c> 이고, 모르는 id 는 <c>missing</c> 입니다.
    /// 둘 다 그 집합 안이므로 프로파일이 걸려 있기만 하면 참입니다. 프로파일이 <c>pairedValidated</c>
    /// 인 판이 생기면 이 함수만 고치면 됩니다.
    /// </remarks>
    private static bool IsUnvalidatedProfile(string? scannerProfileId) =>
        !string.IsNullOrEmpty(scannerProfileId);
}
