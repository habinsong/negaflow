using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum LibrarySourceAvailability
{
    Unknown,
    Online,
    Offline,
}

public sealed record LibraryAvailabilitySnapshot(
    IReadOnlyDictionary<string, LibrarySourceAvailability> ByFrameId,
    IReadOnlyDictionary<string, bool> ByFolderId);

/// <summary>
/// source path를 중복 검사하지 않는 library availability snapshot입니다. 대형 catalog에서는
/// 이 순수 작업을 background thread에서 수행하고 UI에는 완성된 snapshot만 전달합니다.
/// </summary>
public static class LibraryAvailability
{
    public static LibraryAvailabilitySnapshot Probe(
        IReadOnlyList<LibraryFrameSnapshot> frames,
        IReadOnlyList<LibraryFolderSnapshot> folders,
        Func<string, bool>? fileExists = null,
        Func<string, bool>? directoryExists = null)
    {
        ArgumentNullException.ThrowIfNull(frames);
        ArgumentNullException.ThrowIfNull(folders);
        Func<string, bool> hasFile = fileExists ?? File.Exists;
        Func<string, bool> hasDirectory = directoryExists ?? Directory.Exists;

        Dictionary<string, LibrarySourceAvailability> paths = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, LibrarySourceAvailability> byFrameId = new(StringComparer.Ordinal);
        foreach (LibraryFrameSnapshot frame in frames)
        {
            if (!paths.TryGetValue(frame.SourcePath, out LibrarySourceAvailability availability))
            {
                availability = hasFile(frame.SourcePath)
                    ? LibrarySourceAvailability.Online
                    : LibrarySourceAvailability.Offline;
                paths.Add(frame.SourcePath, availability);
            }
            byFrameId[frame.Id] = availability;
        }

        Dictionary<string, bool> byFolderId = new(StringComparer.Ordinal);
        foreach (LibraryFolderSnapshot folder in folders)
        {
            if (!byFolderId.ContainsKey(folder.Id))
            {
                byFolderId.Add(folder.Id, hasDirectory(folder.SourcePath));
            }
        }
        return new LibraryAvailabilitySnapshot(byFrameId, byFolderId);
    }
}
