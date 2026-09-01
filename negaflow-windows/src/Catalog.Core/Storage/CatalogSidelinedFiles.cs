namespace Negaflow.Catalog;

/// <summary>
/// 복구 과정에서 옆으로 치워 둔 카탈로그 사본(<c>library.corrupt-*</c>)과 그 짝인 결함
/// 폴더입니다. macOS <c>LibraryBackupStore.preserveUnsafeState</c> +
/// <c>LibraryCatalogSidelinedFiles</c> 이식본입니다.
/// </summary>
/// <remarks>
/// 최근 것 몇 개만 남깁니다 — 마지막으로 기댈 사본이라 무조건 지우면 안 되고, 무한정 쌓아
/// 두면 지원 폴더가 계속 커집니다. macOS 는 이 정리를 안 해서 개발 머신에 9.2MB 가
/// 쌓여 있었습니다.
/// </remarks>
public static class CatalogSidelinedFiles
{
    public const int DefaultRetentionCount = 3;

    internal const string CatalogPrefix = "library.corrupt-";
    internal const string DefectPrefix = "defects.corrupt-";

    /// <summary>
    /// 지금 카탈로그와 결함 기록을 옆에 복사해 둡니다. <b>원본은 건드리지 않습니다</b> —
    /// 지우는 것은 부르는 쪽의 몫입니다.
    /// </summary>
    /// <returns>사본을 남겼거나 남길 것이 없었으면 <c>true</c> 입니다.</returns>
    public static bool Preserve(
        StorageRootSet roots,
        int retentionCount = DefaultRetentionCount)
    {
        ArgumentNullException.ThrowIfNull(roots);
        string identifier = Guid.NewGuid().ToString("N");
        string parent = roots.LibraryRoot;
        string extension = Path.GetExtension(roots.CatalogPath);
        string preservedCatalog = Path.Combine(
            parent,
            $"{CatalogPrefix}{identifier}{extension}");
        string preservedDefects = Path.Combine(parent, $"{DefectPrefix}{identifier}");

        List<string> created = [];
        try
        {
            if (File.Exists(roots.CatalogPath))
            {
                File.Copy(roots.CatalogPath, preservedCatalog);
                created.Add(preservedCatalog);
            }
            if (Directory.Exists(roots.DefectRecipeRoot) &&
                !StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                CopyDirectory(roots.DefectRecipeRoot, preservedDefects);
                created.Add(preservedDefects);
            }
            Prune(parent, retentionCount);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException)
        {
            // 반쯤 만든 사본은 남기지 않습니다 - 다음 정리가 그것을 "최근 사본" 으로 셉니다.
            for (int index = created.Count - 1; index >= 0; index--)
            {
                TryRemove(created[index]);
            }
            return false;
        }
    }

    /// <summary>
    /// 마지막 탈출구의 파일 몫입니다. 지금 카탈로그와 결함 기록을 옆에 보관한 뒤 치웁니다.
    /// <b>사진 원본과 백업 세대는 건드리지 않습니다</b> — 나중에 백업에서 되돌릴 수 있어야
    /// 합니다. 빈 카탈로그를 세우는 것은 부르는 쪽의 몫입니다.
    /// </summary>
    public static bool PrepareFreshStart(
        StorageRootSet roots,
        int retentionCount = DefaultRetentionCount)
    {
        ArgumentNullException.ThrowIfNull(roots);
        if (!Preserve(roots, retentionCount))
        {
            return false;
        }
        try
        {
            if (File.Exists(roots.CatalogPath))
            {
                File.Delete(roots.CatalogPath);
            }
            // junction 이면 그 안을 지우지 않고 연결만 끊습니다.
            if (Directory.Exists(roots.DefectRecipeRoot))
            {
                Directory.Delete(
                    roots.DefectRecipeRoot,
                    recursive: !StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot));
            }
            Directory.CreateDirectory(roots.DefectRecipeRoot);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>최근 <paramref name="retentionCount"/> 개만 남기고 나머지를 지웁니다.</summary>
    public static void Prune(string directory, int retentionCount = DefaultRetentionCount)
    {
        int keep = Math.Max(1, retentionCount);
        try
        {
            if (!Directory.Exists(directory))
            {
                return;
            }
            foreach (string prefix in (string[])[CatalogPrefix, DefectPrefix])
            {
                string[] matches = [.. Directory
                    .EnumerateFileSystemEntries(directory, prefix + "*", SearchOption.TopDirectoryOnly)
                    .OrderByDescending(File.GetLastWriteTimeUtc)
                    .ThenByDescending(path => path, StringComparer.Ordinal)];
                for (int index = keep; index < matches.Length; index++)
                {
                    TryRemove(matches[index]);
                }
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 정리에 실패해도 복구 자체를 막지 않습니다.
        }
    }

    private static void CopyDirectory(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        foreach (string file in Directory.EnumerateFiles(
            source,
            "*",
            SearchOption.TopDirectoryOnly))
        {
            File.Copy(file, Path.Combine(destination, Path.GetFileName(file)));
        }
    }

    private static void TryRemove(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
                return;
            }
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // 못 지운 사본은 다음 정리가 다시 봅니다.
        }
    }
}
