using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum FolderImportRefusal
{
    NoFolders,
    InvalidPath,
    FolderNotFound,
    FolderUnreadable,
}

public sealed record FolderImportRejection(string Path, FolderImportRefusal Refusal);

public sealed record FolderImportPlan(
    IReadOnlyList<LibraryFolderSnapshot> Folders,
    FrameImportPlan Frames,
    IReadOnlyList<FolderImportRejection> Rejected);

public sealed record FolderImportResult(
    FolderImportPlan Plan,
    int AddedFolderCount,
    int AddedFrameCount,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => CatalogError == CatalogStoreError.None;
}

/// <summary>
/// macOS Library folder import와 같이 선택한 폴더의 최상위 TIFF만 안정된 이름 순서로 계획합니다.
/// 빈 폴더도 catalog source로 남기고, 하위 폴더를 재귀적으로 가져오지는 않습니다.
/// </summary>
public static class FolderImport
{
    public static FolderImportPlan Plan(
        IReadOnlyList<string> folderPaths,
        IReadOnlyList<LibraryFrameSnapshot> existingFrames,
        DevelopmentProcess process,
        DateTimeOffset? addedAt = null,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(folderPaths);
        ArgumentNullException.ThrowIfNull(existingFrames);

        List<LibraryFolderSnapshot> folders = [];
        List<FolderImportRejection> rejected = [];
        List<string> files = [];
        HashSet<string> seenFolders = new(StringComparer.OrdinalIgnoreCase);
        DateTimeOffset timestamp = addedAt ?? DateTimeOffset.UtcNow;

        foreach (string folderPath in folderPaths)
        {
            if (!LibraryFolderRecord.TryNormalizePath(folderPath, out string normalized))
            {
                rejected.Add(new FolderImportRejection(folderPath ?? string.Empty,
                    FolderImportRefusal.InvalidPath));
                continue;
            }
            if (!Directory.Exists(normalized))
            {
                rejected.Add(new FolderImportRejection(normalized, FolderImportRefusal.FolderNotFound));
                continue;
            }
            if (!seenFolders.Add(normalized))
            {
                continue;
            }

            string[] candidates;
            try
            {
                candidates = Directory.EnumerateFiles(normalized, "*", SearchOption.TopDirectoryOnly)
                    .Where(IsImportableTiff)
                    .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                    .ToArray();
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                NotSupportedException or ArgumentException or PathTooLongException)
            {
                rejected.Add(new FolderImportRejection(normalized, FolderImportRefusal.FolderUnreadable));
                continue;
            }

            if (LibraryFolderRecord.TryCreate(normalized, timestamp, out LibraryFolderSnapshot folder))
            {
                folders.Add(folder);
                files.AddRange(candidates);
            }
        }

        if (folders.Count == 0 && rejected.Count == 0)
        {
            rejected.Add(new FolderImportRejection(string.Empty, FolderImportRefusal.NoFolders));
        }
        return new FolderImportPlan(
            folders,
            FrameImport.Plan(files, existingFrames, process, sourceMetadataReader: sourceMetadataReader),
            rejected);
    }

    private static bool IsImportableTiff(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & FileAttributes.Hidden) != 0)
            {
                return false;
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }

        string extension = Path.GetExtension(path);
        return string.Equals(extension, ".tif", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(extension, ".tiff", StringComparison.OrdinalIgnoreCase);
    }
}
