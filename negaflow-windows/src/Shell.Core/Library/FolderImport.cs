using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum FolderImportRefusal
{
    None,
    NoFolders,
    InvalidPath,
    FolderNotFound,
    FolderUnreadable,
    HasSubfolders,
    NoImportableImages,
}

public sealed record FolderImportRejection(string Path, FolderImportRefusal Refusal);

public sealed record FolderImportPlan(
    IReadOnlyList<LibraryFolderSnapshot> Folders,
    FrameImportPlan Frames,
    IReadOnlyList<FolderImportRejection> Rejected)
{
    public bool HasImportableFiles { get; init; }
}

public sealed record FolderImportResult(
    FolderImportPlan Plan,
    int AddedFolderCount,
    int AddedFrameCount,
    CatalogStoreError CatalogError)
{
    public int AttachedInfraredCount { get; init; }

    public int RemovedStrayInfraredFrameCount { get; init; }

    public bool IsSuccess =>
        CatalogError == CatalogStoreError.None &&
        Plan.Rejected.Count == 0 &&
        Plan.Folders.Count > 0 &&
        Plan.HasImportableFiles;
}

/// <summary>
/// 선택한 폴더가 이미지를 직접 가진 leaf일 때만 최상위 지원 이미지를 안정된 이름 순서로 계획합니다.
/// 빈 폴더와 하위 폴더가 하나라도 있는 폴더는 등록하지 않고, 하위 폴더를 재귀 탐색하지 않습니다.
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
        Dictionary<string, LibrarySourceMetadata?> metadata =
            new(StringComparer.OrdinalIgnoreCase);
        HashSet<string> seenFolders = new(StringComparer.OrdinalIgnoreCase);
        DateTimeOffset timestamp = addedAt ?? DateTimeOffset.UtcNow;
        // 이미 라이브러리에 있는 원본과 거기 붙은 IR 은 탐침하지 않습니다. 가져오기 관문은 새로
        // 들어올 파일을 거르는 자리이고, 기존 원본은 `FrameImport.Plan` 이 경로만으로 중복을
        // 확정합니다. 예전에는 켤 때 등록 폴더를 다시 훑으며 기존 RAW/TIFF 를 전부 다시 열어,
        // 첫 화면이 2.3 초 늦게 떴습니다.
        HashSet<string> imported = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in existingFrames)
        {
            imported.Add(FrameImport.NormalizePath(frame.SourcePath));
            if (frame.InfraredPath is { } infraredPath)
            {
                imported.Add(FrameImport.NormalizePath(infraredPath));
            }
        }

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

            if (!TryEnumerateLeafImages(
                    normalized,
                    out IReadOnlyList<string> candidates,
                    out FolderImportRefusal refusal))
            {
                rejected.Add(new FolderImportRejection(normalized, refusal));
                continue;
            }

            if (sourceMetadataReader is not null)
            {
                candidates = [.. candidates.Where(path =>
                {
                    if (imported.Contains(FrameImport.NormalizePath(path)))
                    {
                        return true;
                    }
                    LibrarySourceMetadata? value = sourceMetadataReader(path);
                    metadata[path] = value;
                    return value is not null;
                })];
                if (candidates.Count == 0)
                {
                    rejected.Add(new FolderImportRejection(
                        normalized,
                        FolderImportRefusal.NoImportableImages));
                    continue;
                }
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
        Func<string, LibrarySourceMetadata?>? cachedReader = sourceMetadataReader is null
            ? null
            : path => metadata.TryGetValue(path, out LibrarySourceMetadata? value)
                ? value
                : sourceMetadataReader(path);
        return new FolderImportPlan(
            folders,
            FrameImport.Plan(files, existingFrames, process, sourceMetadataReader: cachedReader),
            rejected)
        {
            HasImportableFiles = files.Count > 0,
        };
    }

    internal static bool TryEnumerateLeafImages(
        string normalizedFolderPath,
        out IReadOnlyList<string> files,
        out FolderImportRefusal refusal,
        bool allowEmpty = false)
    {
        files = [];
        refusal = FolderImportRefusal.None;
        try
        {
            if (Directory.EnumerateDirectories(
                    normalizedFolderPath,
                    "*",
                    SearchOption.TopDirectoryOnly).Any())
            {
                refusal = FolderImportRefusal.HasSubfolders;
                return false;
            }
            string[] candidates = Directory
                .EnumerateFiles(normalizedFolderPath, "*", SearchOption.TopDirectoryOnly)
                .Where(IsImportableImage)
                .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            if (candidates.Length == 0 && !allowEmpty)
            {
                refusal = FolderImportRefusal.NoImportableImages;
                return false;
            }
            files = candidates;
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            refusal = FolderImportRefusal.FolderUnreadable;
            return false;
        }
    }

    private static bool IsImportableImage(string path)
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

        return ImageSourcePaths.IsSupportedImportPath(path);
    }
}
