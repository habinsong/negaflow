using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 커밋은 주 카탈로그에 트랜잭션으로 씁니다. 도중에 앱이 끝나면 hot journal(<c>-journal</c>)이
/// 남습니다. 읽기 전용 열기는 그것을 되감지 못해 <c>AccessDenied</c> 로 막혔고, 재시도로도
/// 빠져나갈 수 없었습니다.
/// </summary>
internal static class CatalogHotJournalTests
{
    public static void Run(StorageRootSet roots)
    {
        StorageRootSet hot = NewRoots(roots, "hot-journal");
        Seed(hot);
        LeaveHotJournal(hot.CatalogPath);
        Check(File.Exists(Journal(hot)), "hot_journal_fixture_leaves_a_journal");
        using (CatalogSession? session = CatalogSession.Open(hot).Session)
        {
            CatalogReadResult read = session?.Read() ?? default;
            Check(FrameLabels(read) == "one", "hot_journal_rolls_back_to_the_last_commit",
                () => $"session={session is not null} read={read.Error} labels={FrameLabels(read)}");
            Check(!File.Exists(Journal(hot)), "hot_journal_is_consumed");
        }

        // 저널 모양이 아닌 쓰레기도 열기를 막지 않습니다. -wal 은 rollback journal 모드에서 읽지 않습니다.
        StorageRootSet junk = NewRoots(roots, "junk-journal");
        Seed(junk);
        File.WriteAllText(Journal(junk), "junk journal");
        File.WriteAllText($"{junk.CatalogPath}-wal", "junk wal");
        using (CatalogSession? session = CatalogSession.Open(junk).Session)
        {
            CatalogReadResult read = session?.Read() ?? default;
            Check(FrameLabels(read) == "one", "junk_journal_does_not_block_the_open",
                () => $"session={session is not null} read={read.Error}");
        }
    }

    private static string Journal(StorageRootSet roots) => $"{roots.CatalogPath}-journal";

    private static StorageRootSet NewRoots(StorageRootSet roots, string name) =>
        StorageRootResolver.ResolveForTests(Path.Combine(
            Path.GetDirectoryName(roots.LocalApplicationDataRoot)!,
            $"{name}-{Guid.NewGuid():N}")).Roots!;

    private static void Seed(StorageRootSet roots)
    {
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        Check(session.Write(Snapshot("roll", Row("frame-1", "one"))).IsSuccess, "hot_journal_seed");
    }

    /// <summary>
    /// 커밋 도중의 디스크 상태를 만듭니다. 사본에서 트랜잭션을 열고 캐시를 넘치게 해 바뀐 페이지를
    /// 파일에 쓰게 한 뒤, 그 순간의 파일과 저널을 제자리에 복사합니다.
    /// </summary>
    private static void LeaveHotJournal(string catalogPath)
    {
        string scratch = Path.Combine(Path.GetDirectoryName(catalogPath)!, $"inflight-{Guid.NewGuid():N}.sqlite");
        File.Copy(catalogPath, scratch);
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = StorageExtendedPath.ToExtendedPath(scratch),
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using (SqliteConnection connection = new(builder.ConnectionString))
        {
            connection.Open();
            using SqliteCommand command = connection.CreateCommand();
            command.CommandText =
                "PRAGMA journal_mode=DELETE; PRAGMA cache_size=1; BEGIN IMMEDIATE;" +
                "UPDATE frames SET payload = X'00';" +
                "CREATE TABLE spill(x); WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 400)" +
                " INSERT INTO spill SELECT randomblob(2000) FROM n;";
            command.ExecuteNonQuery();
            File.Copy(scratch, catalogPath, overwrite: true);
            File.Copy($"{scratch}-journal", $"{catalogPath}-journal", overwrite: true);
        }
        File.Delete(scratch);
    }
}
