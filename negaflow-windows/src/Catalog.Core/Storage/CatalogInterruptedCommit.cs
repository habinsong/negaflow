using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog;

/// <summary>
/// 열기 직전에, 끊긴 커밋이 남긴 흔적을 정리합니다. 프로세스 lock 을 잡은 뒤에만 부릅니다.
/// </summary>
/// <remarks>
/// <para>
/// 커밋은 주 카탈로그를 <c>.catalog-*.rollback</c> 으로 복사해 두고 SQLite 트랜잭션으로 고쳐 쓴 뒤
/// 그 사본을 지웁니다. 도중에 앱이 끝나면 사본과 hot journal 이 남는데, 저널을 먼저 되감으면
/// 표식(<c>.rollback-required</c>)이 없는 한 주 카탈로그는 커밋 앞이나 뒤의 온전한 한 판입니다. 이
/// 흔적 때문에 열기를 막으면 최근 백업으로 되돌아가 그 뒤의 편집을 잃었습니다 — 사본을 보관하고
/// 그대로 엽니다.
/// </para>
/// <para>
/// 표식은 되돌리기까지 실패했다는 뜻입니다. 그때 롤백 사본은 커밋 직전 상태라 어느 백업 세대보다
/// 새로우므로, 지금 파일을 보관한 뒤 그것으로 되돌리기를 마칩니다. 그마저 안 되면 흔적을 그대로
/// 두고, 열기는 막히며 호스트가 최근 백업으로 되돌립니다.
/// </para>
/// <para>
/// 교체 도중 남은 <c>.catalog-*.tmp</c>·<c>.catalog-*.displaced</c> 도 보관 사본으로 옮깁니다. 열기를
/// 막지는 않지만 카탈로그 크기만큼 계속 쌓였습니다. 보관 사본은 최근 몇 개만 남습니다.
/// </para>
/// </remarks>
internal static class CatalogInterruptedCommit
{
    internal static void Resolve(StorageRootSet roots)
    {
        ArgumentNullException.ThrowIfNull(roots);
        try
        {
            if (!Directory.Exists(roots.LibraryRoot))
            {
                return;
            }
            RollBackHotJournal(roots);
            string[] rollbacks = [.. Directory
                .EnumerateFiles(roots.LibraryRoot, ".catalog-*.rollback", SearchOption.TopDirectoryOnly)
                .OrderByDescending(File.GetLastWriteTimeUtc)];
            if (!File.Exists($"{roots.CatalogPath}.rollback-required"))
            {
                if (rollbacks.Length != 0 && CatalogRecovery.IsValidCatalogSource(roots.CatalogPath))
                {
                    _ = CatalogSidelinedFiles.SidelineRollbackArtifacts(roots);
                }
            }
            else if (rollbacks.FirstOrDefault(CatalogRecovery.IsValidCatalogSource) is { } copy &&
                CatalogSidelinedFiles.Preserve(roots) &&
                CatalogCommitFiles.CopyAndPromote(copy, roots.CatalogPath, roots.LibraryRoot) ==
                    CatalogStoreError.None)
            {
                _ = CatalogSidelinedFiles.SidelineRollbackArtifacts(roots);
            }
            CatalogSidelinedFiles.SidelineInterruptedCommitFiles(roots);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SqliteException)
        {
            // 정리는 열기를 막지 않습니다. 남은 흔적은 뒤의 검사가 판정합니다.
        }
    }

    /// <summary>
    /// 커밋은 주 카탈로그에 트랜잭션으로 씁니다. 도중에 끝나면 hot journal(<c>-journal</c>)이 남는데,
    /// 읽기 전용 열기는 그것을 되감지 못해 <c>AccessDenied</c> 로 막혔고 재시도도 같았습니다. 한 번
    /// 쓰기로 열어 SQLite 가 되감게 합니다 — 끊긴 커밋 직전 판으로 돌아갑니다. 저널 모양이 아닌
    /// 쓰레기는 SQLite 가 헤더를 보고 버립니다.
    /// </summary>
    private static void RollBackHotJournal(StorageRootSet roots)
    {
        if (!File.Exists($"{roots.CatalogPath}-journal") || !File.Exists(roots.CatalogPath))
        {
            return;
        }
        using SqliteConnection connection = SqliteCatalogSchema.OpenConnection(
            roots.CatalogPath,
            SqliteOpenMode.ReadWrite);
        _ = SqliteCatalogSchema.ScalarInt64(connection, "PRAGMA schema_version");
    }
}
