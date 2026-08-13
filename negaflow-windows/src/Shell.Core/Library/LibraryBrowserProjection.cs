using Negaflow.Catalog;
using Negaflow.Shell.Develop;

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
    IReadOnlyList<LibraryFrameListItem> Items) : IReadOnlyList<LibraryFrameListItem>
{
    public int Count => Items.Count;

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
            if (Items.Count == 0)
            {
                return 0;
            }
            DevelopmentProcess current = DevelopProcesses.From(
                Items[0].Frame.Route.FilmType,
                Items[0].Frame.Route.IsDigitalSource);
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

    public LibraryFrameListItem this[int index] => Items[index];

    public IEnumerator<LibraryFrameListItem> GetEnumerator() => Items.GetEnumerator();

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
        FilmType selectedFilmType = FilmType.ColorNegative)
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
                ? BuildSections(
                    matched,
                    folders,
                    folderAvailabilityById,
                    includeEmptyRegisteredFolders: mode == LibraryBrowserViewMode.Folders)
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
        bool includeEmptyRegisteredFolders)
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
                group));
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
                group));
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
