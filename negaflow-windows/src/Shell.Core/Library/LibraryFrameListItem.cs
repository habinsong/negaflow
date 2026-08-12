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

    public LibraryFrameSnapshot Frame { get; }

    public string Id => Frame.Id;

    public string DisplayName => Frame.EffectiveDisplayName;

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

    public bool HasThumbnail => thumbnail is not null;

    /// <summary>썸네일이 아직 없어 자리표시자를 보여야 하는 상태입니다.</summary>
    public bool IsThumbnailPending => thumbnail is null;

    public event PropertyChangedEventHandler? PropertyChanged;

    private object? thumbnail;

    private static readonly PropertyChangedEventArgs ThumbnailChangedArgs = new(nameof(Thumbnail));

    private static readonly PropertyChangedEventArgs HasThumbnailChangedArgs = new(nameof(HasThumbnail));

    private static readonly PropertyChangedEventArgs ThumbnailPendingChangedArgs =
        new(nameof(IsThumbnailPending));
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
