using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 목록 한 줄에 보이는 것입니다. 표시용 문자열을 XAML 이 아니라 여기서 만들어야 시험할 수
/// 있습니다.
/// </summary>
public sealed class LibraryFrameListItem
{
    public LibraryFrameListItem(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        Frame = frame;
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
        : "Dmin not set";

    public bool CanDevelop => Frame.CanDevelop;
}

public static class LibraryFrameListItems
{
    public static IReadOnlyList<LibraryFrameListItem> From(
        IReadOnlyList<LibraryFrameSnapshot> frames)
    {
        ArgumentNullException.ThrowIfNull(frames);
        List<LibraryFrameListItem> items = new(frames.Count);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            items.Add(new LibraryFrameListItem(frame));
        }
        return items;
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
}
