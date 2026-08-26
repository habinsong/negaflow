using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

public enum LibraryBrowserViewMode
{
    Folders,
    FilmType,
    Offline,
    All,
}

public sealed record LibraryBrowserFolderSection(
    string Id,
    string? FolderId,
    string Title,
    bool IsRegistered,
    bool IsAvailable,
    IReadOnlyList<LibraryFrameListItem> Items,
    LibraryFolderDevelopmentDrafts? Drafts = null,
    bool IsCollapsed = false,
    bool IsFirst = false) : IReadOnlyList<LibraryFrameListItem>
{
    /// <summary>
    /// macOS <c>.padding(6).padding(.top, isFirst ? 0 : 16)</c> — 격자에는 줄 간격이 하나뿐이라
    /// 폴더 사이를 벌리는 여백을 머리줄이 스스로 답니다. 첫 폴더는 위가 붙어야 제목줄 바로
    /// 아래에서 시작합니다.
    /// </summary>
    public string HeaderMargin => IsFirst ? "6" : "6,22,6,6";

    /// <summary>
    /// 머리줄이 보여 줄 장수입니다. macOS 는 접어도 "16장" 을 그대로 답니다 —
    /// <see cref="Count"/> 는 격자가 그릴 것의 수라 접으면 0 이 되므로 따로 둡니다.
    /// </summary>
    public int FrameCount => Items.Count;

    /// <summary>
    /// 머리줄에 그대로 쓰는 "N장" 입니다. 화면이 문자열을 짓지 않게 여기서 만듭니다.
    /// 형식은 셸이 <see cref="FrameCountFormat"/> 로 걸어 줍니다(언어마다 다르므로).
    /// </summary>
    public string FrameCountLabel => string.Format(
        System.Globalization.CultureInfo.CurrentCulture,
        FrameCountFormat,
        FrameCount);

    /// <summary>macOS 의 "%d장" 자리입니다. 셸이 리소스에서 읽어 한 번 걸어 둡니다.</summary>
    public static string FrameCountFormat { get; set; } = "{0}";

    /// <summary>펼침 ⌄ · 접힘 ›. macOS 폴더 머리줄의 디스클로저와 같은 자리입니다.</summary>
    public string DisclosureGlyph => IsCollapsed ? "" : "";

    /// <summary>
    /// 접힌 폴더는 머리줄만 남고 사진은 그리지 않습니다.
    /// </summary>
    /// <remarks>
    /// **격자가 읽는 것이 이 목록입니다.** 앞 판은 <c>CollectionViewSource.ItemsPath</c> 가
    /// <c>Items</c> 를 가리켰습니다. 그것은 접든 말든 전부 들고 있는 원본이라, 화살표를 눌러도
    /// 글자(⌄/›)만 바뀌고 사진은 그대로 남았습니다 - 접기가 아예 화면에 닿지 않았습니다.
    /// </remarks>
    public IReadOnlyList<LibraryFrameListItem> Displayed => IsCollapsed ? [] : Items;

    public int Count => Displayed.Count;

    /// <summary>
    /// 이 폴더의 첫 frame 이 지금 들고 있는 값입니다. macOS <c>referenceFrame</c> 자리 —
    /// 초안이 없을 때 보여 줄 값이자, 초안을 버릴지 판정하는 기준입니다.
    /// </summary>
    private (DevelopmentProcess Process, DevelopTarget Target) Reference =>
        Items.Count == 0
            ? (DevelopmentProcess.C41, DevelopTarget.Main)
            : (DevelopProcesses.From(
                   Items[0].Frame.Route.FilmType,
                   Items[0].Frame.Route.IsDigitalSource),
               Items[0].Frame.DevelopTarget);

    /// <summary>
    /// 고르개가 보여 줄 값입니다. 적용 전 초안이 있으면 초안이고, 없으면 프레임의 현재 값입니다.
    /// </summary>
    public (DevelopmentProcess Process, DevelopTarget Target) Selection
    {
        get
        {
            (DevelopmentProcess process, DevelopTarget target) = Reference;
            return Drafts is null ? (process, target) : Drafts.Resolve(Id, process, target);
        }
    }

    /// <summary>
    /// 폴더 머리줄의 현상 프로세스 선택지입니다. macOS 가 그 자리에 두는 것과 같은 여섯 개이며,
    /// 이름을 여기서 만들어야 XAML 이 문자열을 짓지 않습니다.
    /// </summary>
    public IReadOnlyList<DevelopProcessChoice> ProcessChoices { get; } =
        [.. DevelopProcesses.All.Select(process =>
            new DevelopProcessChoice(process, DevelopProcesses.DisplayName(process)))];

    /// <summary>
    /// 이 폴더가 지금 보여 줄 프로세스입니다. 폴더 안이 섞여 있으면 첫 frame 을 따릅니다 —
    /// 고르면 폴더 전체에 적용되므로 하나를 대표로 보여 주는 편이 덜 헷갈립니다.
    /// </summary>
    public int ProcessIndex
    {
        get
        {
            DevelopmentProcess current = Selection.Process;
            for (int index = 0; index < ProcessChoices.Count; ++index)
            {
                if (ProcessChoices[index].Process == current)
                {
                    return index;
                }
            }
            return 0;
        }
    }

    /// <summary>
    /// 폴더 머리줄의 타깃 선택지입니다. macOS 는 다섯만 냅니다
    /// (<c>LibraryFolderDevelopmentControls.visibleTargets</c> — PRINT·EXPIRED 없음).
    /// </summary>
    public IReadOnlyList<DevelopTargetChoice> TargetChoices { get; } =
        [.. LibraryFolderDevelopment.VisibleTargets.Select(target =>
            new DevelopTargetChoice(target, DevelopTargets.DisplayName(target)))];

    /// <summary>이 폴더가 보여 줄 타깃입니다. 프로세스와 같이 첫 frame 을 대표로 씁니다.</summary>
    public int TargetIndex
    {
        get
        {
            DevelopTarget current = Selection.Target;
            for (int index = 0; index < TargetChoices.Count; ++index)
            {
                if (TargetChoices[index].Target == current)
                {
                    return index;
                }
            }
            return 0;
        }
    }

    public LibraryFrameListItem this[int index] => Displayed[index];

    public IEnumerator<LibraryFrameListItem> GetEnumerator() => Displayed.GetEnumerator();

    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
}

public sealed record LibraryBrowserProjection(
    int SourceCount,
    int MatchedCount,
    IReadOnlyList<LibraryFrameListItem> Items,
    IReadOnlyList<LibraryBrowserFolderSection> FolderSections);

/// <summary>
/// Library 목록, folder 원본, availability snapshot을 하나의 순서 보존 투영으로 만듭니다.
/// Folder/Film Type은 empty registered folder도 남기고, All/Offline은 평면 목록을 제공합니다.
/// </summary>
public static class LibraryBrowserProjector
{
    public static LibraryBrowserProjection Create(
        IReadOnlyList<LibraryFrameListItem> source,
        IReadOnlyList<LibraryFolderSnapshot> folders,
        IReadOnlyDictionary<string, bool> folderAvailabilityById,
        LibraryBrowserViewMode mode,
        FilmType selectedFilmType = FilmType.ColorNegative,
        LibraryFolderDevelopmentDrafts? drafts = null,
        IReadOnlySet<string>? collapsedSectionIds = null,
        bool includeEmptyFolders = true)
    {
        ArgumentNullException.ThrowIfNull(source);
        ArgumentNullException.ThrowIfNull(folders);
        ArgumentNullException.ThrowIfNull(folderAvailabilityById);

        List<LibraryFrameListItem> unique = StableUnique(source);
        List<LibraryFrameListItem> matched = mode switch
        {
            LibraryBrowserViewMode.FilmType => unique
                .Where(item => item.Frame.Route.FilmType == selectedFilmType)
                .ToList(),
            LibraryBrowserViewMode.Offline => unique
                .Where(item => item.Availability == LibrarySourceAvailability.Offline)
                .ToList(),
            _ => unique,
        };

        IReadOnlyList<LibraryBrowserFolderSection> sections = mode is
            LibraryBrowserViewMode.Folders or LibraryBrowserViewMode.FilmType
                // 파일 목록은 **사진을 담고 있는 폴더만** 냅니다. 등록만 해 두고 사진이
                // 바로 아래에는 없는 폴더까지 내면, 사진이 든 하위 폴더 위에 빈 상위 폴더가
                // 한 줄 더 붙어 "폴더 - 폴더 - 사진" 으로 보입니다.
                ? BuildSections(
                    matched,
                    folders,
                    folderAvailabilityById,
                    includeEmptyRegisteredFolders:
                        includeEmptyFolders && mode == LibraryBrowserViewMode.Folders,
                    drafts,
                    collapsedSectionIds)
                : [];
        return new LibraryBrowserProjection(unique.Count, matched.Count, matched, sections);
    }

    private static List<LibraryFrameListItem> StableUnique(
        IReadOnlyList<LibraryFrameListItem> source)
    {
        HashSet<string> ids = new(StringComparer.Ordinal);
        List<LibraryFrameListItem> result = new(source.Count);
        foreach (LibraryFrameListItem item in source)
        {
            if (ids.Add(item.Id))
            {
                result.Add(item);
            }
        }
        return result;
    }

    private static IReadOnlyList<LibraryBrowserFolderSection> BuildSections(
        IReadOnlyList<LibraryFrameListItem> items,
        IReadOnlyList<LibraryFolderSnapshot> folders,
        IReadOnlyDictionary<string, bool> folderAvailabilityById,
        bool includeEmptyRegisteredFolders,
        LibraryFolderDevelopmentDrafts? drafts,
        IReadOnlySet<string>? collapsedSectionIds)
    {
        Dictionary<string, List<LibraryFrameListItem>> byPath = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameListItem item in items)
        {
            string path = ParentPath(item.Frame.SourcePath);
            if (!byPath.TryGetValue(path, out List<LibraryFrameListItem>? group))
            {
                group = [];
                byPath.Add(path, group);
            }
            group.Add(item);
        }

        List<LibraryBrowserFolderSection> result = [];
        HashSet<string> registeredPaths = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFolderSnapshot folder in folders
            .OrderBy(folder => folder.DisplayName, StringComparer.CurrentCultureIgnoreCase))
        {
            if (!registeredPaths.Add(folder.SourcePath))
            {
                continue;
            }
            List<LibraryFrameListItem> group = byPath.GetValueOrDefault(folder.SourcePath) ?? [];
            if (!includeEmptyRegisteredFolders && group.Count == 0)
            {
                continue;
            }
            result.Add(new LibraryBrowserFolderSection(
                folder.SourcePath,
                folder.Id,
                folder.DisplayName,
                IsRegistered: true,
                IsAvailable: folderAvailabilityById.GetValueOrDefault(folder.Id),
                group,
                drafts,
                collapsedSectionIds?.Contains(folder.SourcePath) == true));
        }

        foreach ((string path, List<LibraryFrameListItem> group) in byPath
            .Where(pair => !registeredPaths.Contains(pair.Key))
            .OrderBy(pair => pair.Key, StringComparer.CurrentCultureIgnoreCase))
        {
            string name = Path.GetFileName(Path.TrimEndingDirectorySeparator(path));
            result.Add(new LibraryBrowserFolderSection(
                path,
                null,
                string.IsNullOrWhiteSpace(name) ? path : name,
                IsRegistered: false,
                IsAvailable: true,
                group,
                drafts,
                collapsedSectionIds?.Contains(path) == true));
        }
        // macOS 는 `isFirst` 로 첫 폴더의 위 여백만 없앱니다. 목록이 다 만들어진 뒤라야
        // 누가 첫 번째인지 알 수 있으므로 여기서 한 번에 표시합니다.
        if (result.Count > 0)
        {
            result[0] = result[0] with { IsFirst = true };
        }
        return result;
    }

    private static string ParentPath(string sourcePath)
    {
        try
        {
            string? parent = Path.GetDirectoryName(Path.GetFullPath(sourcePath));
            return parent is null ? string.Empty : Path.TrimEndingDirectorySeparator(parent);
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return string.Empty;
        }
    }
}

/// <summary>폴더 머리줄 프로세스 목록 한 칸입니다.</summary>
public sealed record DevelopProcessChoice(DevelopmentProcess Process, string Name);

/// <summary>폴더 머리줄 타깃 고르개의 한 줄입니다.</summary>
public sealed record DevelopTargetChoice(DevelopTarget Target, string Name);
