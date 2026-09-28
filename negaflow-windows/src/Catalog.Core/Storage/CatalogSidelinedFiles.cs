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
            // 한 번이라도 저장한 라이브러리에는 직전 판 사본이 늘 남아, 이것을 치우지 않으면 빈
            // 카탈로그 쓰기가 거부되어 "새 라이브러리로 시작" 이 실패했습니다.
            if (!SidelineLeftovers(roots, retentionCount))
            {
                return false;
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

    /// <summary>
    /// 주 카탈로그가 없을 때 남은 것들 — 커밋이 남긴 직전 판 사본(<c>library.backup.sqlite</c>),
    /// SQLite 동반 파일(<c>-journal</c>·<c>-wal</c>·<c>-shm</c>), 롤백 흔적 — 을 보관 사본
    /// (<c>library.corrupt-*</c>)으로 옮깁니다. 주 파일 없이 이것들이 남은 자리는 커밋이 멈춘 것으로
    /// 보아 새 카탈로그 쓰기를 거부하는데, 주 파일이 없을 때 이것을 읽는 곳은 없으므로 지우지 않고
    /// 옆에 두면 잃는 것이 없습니다. 카탈로그를 통째로 바꿀 때(복원·새로 시작)만 부릅니다. macOS 는
    /// 지금 상태를 보관하고 진행합니다(<c>preserveUnsafeState</c>).
    /// </summary>
    /// <returns>옮긴 뒤 새 카탈로그를 막는 것이 남지 않았으면 <c>true</c> 입니다.</returns>
    internal static bool SidelineLeftovers(
        StorageRootSet roots,
        int retentionCount = DefaultRetentionCount)
    {
        try
        {
            string[] leftovers =
                [roots.CatalogBackupPath, .. CatalogCommitFiles.CatalogCompanionPaths(roots)];
            foreach (string leftover in leftovers.Where(File.Exists))
            {
                string suffix = leftover.StartsWith(roots.CatalogPath, StringComparison.OrdinalIgnoreCase)
                    ? leftover[roots.CatalogPath.Length..]
                    : string.Empty;
                File.Move(leftover, SidelinedCatalogPath(roots, suffix));
            }
            if (!SidelineRollbackArtifacts(roots, retentionCount))
            {
                return false;
            }
            Prune(roots.LibraryRoot, retentionCount);
            return !CatalogCommitRollback.HasBlockingArtifactWhenPrimaryMissing(roots);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// 되돌리지 못한 커밋의 흔적 — <c>.rollback-required</c> 표식과 <c>.catalog-*.rollback</c>
    /// 사본 — 을 치웁니다. 사본은 커밋 직전 카탈로그라 보관 사본으로 옮기고, 표식만 지웁니다.
    /// 카탈로그를 통째로 바꿀 때(복원·새로 시작)만 부릅니다. 예전에는 이 흔적이 남으면 열기·복원·
    /// 새로 시작이 모두 거부돼 앱 안에서 빠져나갈 길이 없었습니다.
    /// </summary>
    internal static bool SidelineRollbackArtifacts(
        StorageRootSet roots,
        int retentionCount = DefaultRetentionCount)
    {
        try
        {
            if (Directory.Exists(roots.LibraryRoot))
            {
                foreach (string rollback in Directory
                    .EnumerateFiles(roots.LibraryRoot, ".catalog-*.rollback", SearchOption.TopDirectoryOnly)
                    .ToArray())
                {
                    File.Move(rollback, SidelinedCatalogPath(roots, string.Empty));
                }
            }
            string marker = $"{roots.CatalogPath}.rollback-required";
            if (File.Exists(marker))
            {
                File.Delete(marker);
            }
            Prune(roots.LibraryRoot, retentionCount);
            return !CatalogCommitRollback.HasUnresolvedRollbackArtifact(roots);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>
    /// 읽지 못하는 주 카탈로그를 원본 그대로 보관한 뒤 치우고, 남은 것들도 옮깁니다. 복원이 그
    /// 자리에 검증된 세대를 씁니다 — 예전에는 직전 판 사본이 남아 그 쓰기가 거부됐습니다.
    /// </summary>
    internal static bool DiscardUnreadablePrimary(StorageRootSet roots)
    {
        if (!Preserve(roots))
        {
            return false;
        }
        try
        {
            File.Delete(roots.CatalogPath);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return false;
        }
        return SidelineLeftovers(roots);
    }

    private static string SidelinedCatalogPath(StorageRootSet roots, string suffix) =>
        Path.Combine(
            roots.LibraryRoot,
            $"{CatalogPrefix}{Guid.NewGuid():N}{Path.GetExtension(roots.CatalogPath)}{suffix}");

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
