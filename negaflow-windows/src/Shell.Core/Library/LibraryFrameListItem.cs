using Negaflow.Catalog;
using System.ComponentModel;
using System.Globalization;
using System.Text;

namespace Negaflow.Shell;

/// <summary>
/// 목록 한 줄에 보이는 것입니다. 표시용 문자열을 XAML 이 아니라 여기서 만들어야 시험할 수
/// 있습니다.
/// </summary>
public sealed class LibraryFrameListItem : INotifyPropertyChanged
{
    public LibraryFrameListItem(
        LibraryFrameSnapshot frame,
        LibrarySourceAvailability availability = LibrarySourceAvailability.Unknown)
    {
        ArgumentNullException.ThrowIfNull(frame);
        Frame = frame;
        Availability = availability;
    }

    public LibraryFrameSnapshot Frame { get; private set; }

    public string Id => Frame.Id;

    public string DisplayName => LibraryFrameNaming.DisplayName(Frame);

    /// <summary>
    /// 현상할 수 없는 frame 은 그 이유를 경로 대신 보여 줍니다. 목록에 있는데 Export 가 조용히
    /// 아무것도 하지 않는 것보다, 왜 안 되는지 그 자리에서 보이는 편이 낫습니다.
    /// </summary>
    public string Detail => Frame.CanDevelop
        ? Frame.SourcePath
        : Frame.Base.Mode == BaseEstimationMode.Preset &&
            string.IsNullOrWhiteSpace(Frame.Base.FilmStockDminId)
            ? "Film base stock is not set"
            : "Dmin not set";

    public bool CanDevelop => Frame.CanDevelop;

    public LibrarySourceAvailability Availability { get; }

    public bool IsSourceOffline => Availability == LibrarySourceAvailability.Offline;

    /// <summary>카드 부제입니다. macOS 는 현상된 카드에만 필름 종류를 답니다.</summary>
    public FilmType FilmType => Frame.Route.FilmType;

    /// <summary>macOS 와 같은 0...5 별점입니다.</summary>
    public int Rating => Frame.Rating;

    /// <summary>깃발이 걸린 사진만 썸네일 왼쪽 위에 표시를 답니다 — macOS 와 같습니다.</summary>
    public bool IsFlagged => Frame.PickState != FramePickState.Unflagged;

    /// <summary>
    /// 깃발 모양입니다. macOS 는 <c>flag.fill</c> 과 <c>xmark.octagon.fill</c> 을 쓰며, 여기서는
    /// Segoe Fluent Icons 의 같은 뜻 글리프를 씁니다.
    /// </summary>
    public string PickGlyph => Frame.PickState == FramePickState.Rejected
        ? ""
        : "";

    /// <summary>깃발 색을 정하는 값입니다. 색 자체는 셸의 converter 가 붙입니다.</summary>
    public FramePickState PickState => Frame.PickState;

    /// <summary>
    /// 이 사진이 대표로 있는 묶음의 장수입니다. 묶음이 없으면 0 이며 배지도 붙지 않습니다.
    /// 셸이 접기 투영을 마친 뒤 채웁니다 — 어떤 사진이 대표인지는 그때에야 정해집니다.
    /// </summary>
    public int StackCount
    {
        get => stackCount;
        set
        {
            if (stackCount == value)
            {
                return;
            }
            stackCount = value;
            PropertyChanged?.Invoke(this, StackCountChangedArgs);
            PropertyChanged?.Invoke(this, HasStackChangedArgs);
            PropertyChanged?.Invoke(this, StackGlyphChangedArgs);
        }
    }

    public bool HasStack => stackCount > 0;

    /// <summary>
    /// 접힌 묶음은 채운 모양, 펼친 묶음은 빈 모양입니다 — macOS <c>rectangle.stack.fill</c> 과
    /// <c>rectangle.stack</c> 에 대응합니다.
    /// </summary>
    public string StackGlyph => IsStackCollapsed ? "" : "";

    /// <summary>배지 모양을 정하는 값입니다. 셸이 채웁니다.</summary>
    public bool IsStackCollapsed { get; set; } = true;

    /// <summary>
    /// 카드 썸네일입니다. Shell.Core 는 XAML 을 참조하지 않으므로 형식을 열어 두고, 셸이
    /// <c>ImageSource</c> 를 넣습니다. 도착이 비동기라 여기만 알림을 냅니다 — 그리드가 카드
    /// 전체를 다시 만들지 않고 그림만 바꿔 끼웁니다.
    /// </summary>
    public object? Thumbnail
    {
        get => thumbnail;
        set
        {
            if (ReferenceEquals(thumbnail, value))
            {
                return;
            }
            thumbnail = value;
            PropertyChanged?.Invoke(this, ThumbnailChangedArgs);
            PropertyChanged?.Invoke(this, HasThumbnailChangedArgs);
            PropertyChanged?.Invoke(this, ThumbnailPendingChangedArgs);
        }
    }

    /// <summary>
    /// 이 칸이 고른 칸인지입니다. 선택 표시 막대를 칸 <b>안에</b> 그리기 때문에 필요합니다 —
    /// WinUI 기본 표시는 왼쪽 세로 막대인데 여기서는 위쪽 가로 막대입니다.
    /// </summary>
    /// <remarks>
    /// 선택 자체는 여전히 <c>ListView</c> 가 들고 있습니다. 이 값은 그 하나를 <b>비추기만</b>
    /// 하며, 필름스트립의 <c>SelectionChanged</c> 한 곳에서만 채웁니다 — 두 곳에서 쓰면
    /// 갈라집니다.
    /// </remarks>
    public bool IsSelected
    {
        get => isSelected;
        set
        {
            if (isSelected == value)
            {
                return;
            }
            isSelected = value;
            PropertyChanged?.Invoke(this, SelectedChangedArgs);
        }
    }

    public bool HasThumbnail => thumbnail is not null;

    /// <summary>썸네일이 아직 없어 자리표시자를 보여야 하는 상태입니다.</summary>
    public bool IsThumbnailPending => thumbnail is null;

    /// <summary>
    /// 같은 사진의 <b>새 스냅샷</b>으로 갈아 끼우고, 보이는 값이 바뀐 것만 알립니다.
    /// </summary>
    /// <remarks>
    /// 별·깃발·제외는 라이브러리 격자·필름스트립·도구줄이 <b>같은 항목 객체</b>를 보고 있습니다.
    /// 목록을 다시 지어 새 객체를 넣는 길로는 세 곳이 함께 따라오지 않습니다 — 필름스트립은
    /// 아이디가 같으면 예전 객체를 그대로 붙들기 때문입니다(<c>FilmstripView.ShowFrames</c>).
    /// 썸네일이 이미 쓰는 길과 같습니다: 칸을 다시 만들지 않고 값만 바꿔 끼웁니다.
    /// </remarks>
    /// <returns>실제로 바뀐 것이 있으면 <c>true</c> 입니다.</returns>
    public bool Refresh(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (ReferenceEquals(Frame, frame))
        {
            return false;
        }
        LibraryFrameSnapshot previous = Frame;
        Frame = frame;
        PropertyChanged?.Invoke(this, FrameChangedArgs);
        if (previous.Rating != frame.Rating)
        {
            PropertyChanged?.Invoke(this, RatingChangedArgs);
        }
        if (previous.PickState != frame.PickState)
        {
            PropertyChanged?.Invoke(this, FlaggedChangedArgs);
            PropertyChanged?.Invoke(this, PickGlyphChangedArgs);
            PropertyChanged?.Invoke(this, PickStateChangedArgs);
        }
        if (previous.CanDevelop != frame.CanDevelop)
        {
            PropertyChanged?.Invoke(this, CanDevelopChangedArgs);
        }
        if (previous.Route.FilmType != frame.Route.FilmType)
        {
            PropertyChanged?.Invoke(this, FilmTypeChangedArgs);
        }
        if (!string.Equals(DisplayNameOf(previous), DisplayName, StringComparison.Ordinal))
        {
            PropertyChanged?.Invoke(this, DisplayNameChangedArgs);
        }
        PropertyChanged?.Invoke(this, DetailChangedArgs);
        return true;
    }

    private static string DisplayNameOf(LibraryFrameSnapshot frame) =>
        LibraryFrameNaming.DisplayName(frame);

    public event PropertyChangedEventHandler? PropertyChanged;

    private object? thumbnail;

    private bool isSelected;

    private int stackCount;

    private static readonly PropertyChangedEventArgs SelectedChangedArgs = new(nameof(IsSelected));

    private static readonly PropertyChangedEventArgs ThumbnailChangedArgs = new(nameof(Thumbnail));

    private static readonly PropertyChangedEventArgs HasThumbnailChangedArgs = new(nameof(HasThumbnail));

    private static readonly PropertyChangedEventArgs ThumbnailPendingChangedArgs =
        new(nameof(IsThumbnailPending));

    private static readonly PropertyChangedEventArgs StackCountChangedArgs =
        new(nameof(StackCount));

    private static readonly PropertyChangedEventArgs HasStackChangedArgs = new(nameof(HasStack));

    private static readonly PropertyChangedEventArgs StackGlyphChangedArgs =
        new(nameof(StackGlyph));

    private static readonly PropertyChangedEventArgs FrameChangedArgs = new(nameof(Frame));

    private static readonly PropertyChangedEventArgs RatingChangedArgs = new(nameof(Rating));

    private static readonly PropertyChangedEventArgs FlaggedChangedArgs = new(nameof(IsFlagged));

    private static readonly PropertyChangedEventArgs PickGlyphChangedArgs = new(nameof(PickGlyph));

    private static readonly PropertyChangedEventArgs PickStateChangedArgs = new(nameof(PickState));

    private static readonly PropertyChangedEventArgs CanDevelopChangedArgs =
        new(nameof(CanDevelop));

    private static readonly PropertyChangedEventArgs FilmTypeChangedArgs = new(nameof(FilmType));

    private static readonly PropertyChangedEventArgs DisplayNameChangedArgs =
        new(nameof(DisplayName));

    private static readonly PropertyChangedEventArgs DetailChangedArgs = new(nameof(Detail));
}

public static class LibraryFrameListItems
{
    public static IReadOnlyList<LibraryFrameListItem> From(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        IReadOnlyDictionary<string, LibrarySourceAvailability>? availabilityByFrameId = null)
    {
        ArgumentNullException.ThrowIfNull(frames);
        List<LibraryFrameListItem> items = new(frames.Count);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            LibrarySourceAvailability availability = availabilityByFrameId is not null &&
                availabilityByFrameId.TryGetValue(frame.Id, out LibrarySourceAvailability value)
                    ? value
                    : LibrarySourceAvailability.Unknown;
            items.Add(new LibraryFrameListItem(frame, availability));
        }
        return items;
    }

    /// <summary>
    /// 이미 화면에 걸린 항목들을 <b>현재 카탈로그 값</b>으로 맞춥니다. 목록은 다시 짓지 않습니다.
    /// </summary>
    /// <remarks>
    /// 별 하나를 줄 때마다 목록을 다시 지으면 격자·필름스트립의 칸이 통째로 헐리고
    /// 다시 세워지며, 그때 원본 존재 확인이 사진 수만큼 다시 돕니다. 바뀐 것은 사진 하나의
    /// 표시값뿐이므로 그 하나만 갈아 끼웁니다.
    /// </remarks>
    /// <returns>실제로 바뀐 항목 수입니다.</returns>
    public static int Refresh(
        IReadOnlyList<LibraryFrameListItem> items,
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentNullException.ThrowIfNull(frames);
        if (items.Count == 0 || frames.Count == 0)
        {
            return 0;
        }
        Dictionary<string, LibraryFrameSnapshot> byId = new(frames.Count, StringComparer.Ordinal);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            byId[frame.Id] = frame;
        }
        int changed = 0;
        foreach (LibraryFrameListItem item in items)
        {
            if (byId.TryGetValue(item.Id, out LibraryFrameSnapshot? current) && item.Refresh(current))
            {
                ++changed;
            }
        }
        return changed;
    }

    /// <summary>
    /// macOS 라이브러리의 빠른 검색과 같은 phrase 검색입니다. 입력어가 한 값 안에 이어져
    /// 있어야 하므로, 이름과 경로가 낱말을 하나씩 나눠 갖는 frame을 잘못 포함하지 않습니다.
    /// 공백 유무, 대소문자, 발음 구별 기호와 전각 차이는 무시합니다.
    /// </summary>
    public static IReadOnlyList<LibraryFrameListItem> Filter(
        IReadOnlyList<LibraryFrameListItem> items,
        string phrase)
    {
        ArgumentNullException.ThrowIfNull(items);
        ArgumentNullException.ThrowIfNull(phrase);

        string compactPhrase = RemoveWhitespace(Normalize(phrase));
        if (compactPhrase.Length == 0)
        {
            return items;
        }

        List<LibraryFrameListItem> matches = [];
        foreach (LibraryFrameListItem item in items)
        {
            if (MatchesPhrase(item.DisplayName, compactPhrase) ||
                MatchesPhrase(item.Frame.SourcePath, compactPhrase))
            {
                matches.Add(item);
            }
        }
        return matches;
    }

    /// <summary>
    /// 읽지 못한 frame 이 있을 때 보여 줄 한 줄입니다. 없으면 <c>null</c> 입니다.
    /// </summary>
    public static string? IssueSummary(IReadOnlyList<LibraryFrameIssue> issues)
    {
        ArgumentNullException.ThrowIfNull(issues);
        if (issues.Count == 0)
        {
            return null;
        }
        return issues.Count == 1
            ? $"1 frame could not be read ({issues[0].Error}). It is still in the catalog."
            : $"{issues.Count} frames could not be read. They are still in the catalog.";
    }

    private static bool MatchesPhrase(string value, string compactPhrase) =>
        RemoveWhitespace(Normalize(value)).Contains(compactPhrase, StringComparison.Ordinal);

    private static string Normalize(string value)
    {
        StringBuilder normalized = new(value.Length);
        bool pendingSpace = false;
        foreach (char character in value.Normalize(NormalizationForm.FormD))
        {
            UnicodeCategory category = CharUnicodeInfo.GetUnicodeCategory(character);
            if (category is UnicodeCategory.NonSpacingMark or UnicodeCategory.SpacingCombiningMark or
                UnicodeCategory.EnclosingMark)
            {
                continue;
            }
            if (char.IsWhiteSpace(character))
            {
                pendingSpace = normalized.Length > 0;
                continue;
            }
            if (pendingSpace)
            {
                normalized.Append(' ');
                pendingSpace = false;
            }
            normalized.Append(char.ToUpperInvariant(character));
        }
        return normalized.ToString().Normalize(NormalizationForm.FormC);
    }

    private static string RemoveWhitespace(string value)
    {
        StringBuilder compact = new(value.Length);
        foreach (char character in value)
        {
            if (!char.IsWhiteSpace(character))
            {
                compact.Append(character);
            }
        }
        return compact.ToString();
    }
}
