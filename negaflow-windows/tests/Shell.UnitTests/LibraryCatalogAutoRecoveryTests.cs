using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 카탈로그 파일이 망가진 모양마다 열기가 어떻게 되는지입니다. macOS
/// <c>LibraryCatalogFile.prepareForUse</c> 는 카탈로그가 없거나 깨지면 가장 최근의 검증된 백업
/// 세대로 되돌려 엽니다(<c>restoreLatest</c>). fixture 는 실제 라이브러리처럼 두 번 저장해 직전 판
/// 사본(<c>library.backup.sqlite</c>)이 있는 상태에서 시작합니다 — 한 번만 쓴 fixture 는 이 사본이
/// 없어 복원 실패를 놓쳤습니다.
/// </summary>
internal static class LibraryCatalogAutoRecoveryTests
{
    internal static void Run()
    {
        // 백업 세대가 있으면 되돌려 엽니다.
        Recovers("primary-missing", roots =>
        {
            File.Delete(roots.CatalogPath);
            File.Delete(roots.CatalogBackupPath);
        });
        Recovers("primary-missing-previous-copy-left", roots => File.Delete(roots.CatalogPath));
        Recovers("primary-corrupt", Corrupt);
        Recovers("primary-truncated", roots =>
        {
            byte[] bytes = File.ReadAllBytes(roots.CatalogPath);
            File.WriteAllBytes(roots.CatalogPath, bytes[..(bytes.Length / 2)]);
        });
        // 쓰다 끊긴 0 바이트 파일입니다. SQLite 는 빈 데이터베이스로 열어 저장 버전 0 을 읽습니다.
        Recovers("primary-zero-bytes", roots => File.WriteAllBytes(roots.CatalogPath, []));
        // 사진 행의 결함 선언이 bool 이 아닙니다 — 카탈로그 행이 깨진 것이라 백업으로 되돌립니다.
        Recovers("frame-declaration-malformed", BreakDeclaration);
        // 쓸 수 있는 롤백 사본이 있으면 백업이 아니라 그 사본으로 되돌리기를 마칩니다.
        Recovers("rollback-required", AddRollbackArtifacts, LibraryOpenOutcome.Restored);

        // 백업 세대가 없으면 막고, 사용자가 고르는 탈출구(새로 시작)가 통해야 합니다.
        StartsFreshWithoutBackup("primary-corrupt", Corrupt);
        StartsFreshWithoutBackup("frame-declaration-malformed", BreakDeclaration);
        // 되돌릴 사본도 쓸 수 없는 표식입니다 — 이때만 막힙니다.
        StartsFreshWithoutBackup("rollback-required", roots =>
        {
            File.WriteAllText(Path.Combine(roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.rollback"), "broken");
            File.WriteAllText($"{roots.CatalogPath}.rollback-required", "1");
        });

        // 커밋이 끊긴 자리는 백업보다 새 상태로 엽니다 — 오래된 백업으로 되돌리면 그 뒤의 편집을
        // 잃습니다.
        KeepsNewerStateAfterInterruptedCommit();
        FinishesFailedRollbackFromTheRollbackCopy();
        SidelinesInterruptedCommitLeftovers();

        // 처음 쓰는 라이브러리는 그대로 새로 만듭니다.
        using Fixture fresh = new("first-run", seed: false);
        LibraryHostService firstRun = fresh.NewHost();
        Check(firstRun.Open(fresh.Roots) == LibraryHostState.Open && firstRun.OpenStatus is null,
            "auto_recovery_first_run_opens_empty_without_a_message");
    }

    private static void Recovers(
        string name,
        Action<StorageRootSet> breakIt,
        LibraryOpenOutcome expected = LibraryOpenOutcome.RecoveredFromBackup)
    {
        using Fixture fixture = new(name, seed: true);
        fixture.Backup();
        breakIt(fixture.Roots);
        LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) == LibraryHostState.Open && host.Frames.Count == 1,
            $"auto_recovery_{name}_restores_latest_backup",
            () => $"{host.State}/session={host.SessionError}/store={host.StoreError}/frames={host.Frames.Count}");
        Check(CatalogRecovery.PendingRestoreGenerationId(fixture.Roots) is null,
            $"auto_recovery_{name}_consumes_the_restore");
        // macOS "백업에서 라이브러리 복구: 사진 N장" 을 알릴 근거입니다.
        Check(host.OpenStatus is { FrameCount: 1 } status && status.Outcome == expected,
            $"auto_recovery_{name}_reports_recovery", () => host.OpenStatus?.ToString() ?? "none");
        Check(host.Save() == CatalogStoreError.None, $"auto_recovery_{name}_saves_after_open",
            () => host.Save().ToString());
    }

    private static void StartsFreshWithoutBackup(string name, Action<StorageRootSet> breakIt)
    {
        using Fixture fixture = new($"{name}-no-backup", seed: true);
        breakIt(fixture.Roots);
        LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) != LibraryHostState.Open,
            $"auto_recovery_{name}_without_backup_stays_blocked");
        Check(host.StartFreshLibrary() && host.State == LibraryHostState.Open && host.Frames.Count == 0,
            $"auto_recovery_{name}_start_fresh_escapes",
            () => $"{host.State}/session={host.SessionError}/store={host.StoreError}");
        Check(Directory.EnumerateFiles(fixture.Roots.LibraryRoot, "library.corrupt-*").Any(),
            $"auto_recovery_{name}_start_fresh_preserves_the_old_catalog");
    }

    /// <summary>
    /// 커밋 중 강제 종료로 롤백 사본만 남았습니다(표식 없음). 주 카탈로그는 트랜잭션이라 온전하므로
    /// 그대로 열고 사본은 보관합니다.
    /// </summary>
    private static void KeepsNewerStateAfterInterruptedCommit()
    {
        using Fixture fixture = new("interrupted-commit", seed: true);
        fixture.Backup();
        string previous = Path.Combine(fixture.Roots.LibraryRoot, "previous-primary.sqlite");
        File.Copy(fixture.Roots.CatalogPath, previous);
        fixture.WriteTwoFrames();
        string rollback = Path.Combine(fixture.Roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.rollback");
        File.Move(previous, rollback);
        LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) == LibraryHostState.Open && host.Frames.Count == 2,
            "auto_recovery_interrupted_commit_keeps_the_newer_catalog",
            () => $"{host.State}/session={host.SessionError}/frames={host.Frames.Count}");
        Check(host.OpenStatus is { Outcome: LibraryOpenOutcome.Restored, FrameCount: 2 },
            "auto_recovery_interrupted_commit_is_an_ordinary_open",
            () => host.OpenStatus?.ToString() ?? "none");
        Check(!File.Exists(rollback) &&
              Directory.EnumerateFiles(fixture.Roots.LibraryRoot, "library.corrupt-*").Any(),
            "auto_recovery_interrupted_commit_preserves_the_rollback_copy");
    }

    /// <summary>
    /// 되돌리기까지 실패한 자리(표식)입니다. 롤백 사본은 커밋 직전 상태라 어느 백업보다 새로우므로
    /// 그것으로 되돌리기를 마칩니다.
    /// </summary>
    private static void FinishesFailedRollbackFromTheRollbackCopy()
    {
        using Fixture fixture = new("failed-rollback", seed: true);
        fixture.Backup();
        fixture.WriteTwoFrames();
        File.Copy(fixture.Roots.CatalogPath,
            Path.Combine(fixture.Roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.rollback"));
        Corrupt(fixture.Roots);
        File.WriteAllText($"{fixture.Roots.CatalogPath}.rollback-required", "1");
        LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) == LibraryHostState.Open && host.Frames.Count == 2,
            "auto_recovery_failed_rollback_uses_the_rollback_copy",
            () => $"{host.State}/session={host.SessionError}/store={host.StoreError}/frames={host.Frames.Count}");
        Check(!File.Exists($"{fixture.Roots.CatalogPath}.rollback-required"),
            "auto_recovery_failed_rollback_clears_the_marker");
    }

    /// <summary>교체 도중 남은 임시 파일은 열기에서 보관 사본으로 옮겨져 쌓이지 않습니다.</summary>
    private static void SidelinesInterruptedCommitLeftovers()
    {
        using Fixture fixture = new("interrupted-leftovers", seed: true);
        string temporary = Path.Combine(fixture.Roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.tmp");
        string displaced = Path.Combine(fixture.Roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.displaced");
        File.Copy(fixture.Roots.CatalogPath, temporary);
        File.Copy(fixture.Roots.CatalogPath, displaced);
        LibraryHostService host = fixture.NewHost();
        Check(host.Open(fixture.Roots) == LibraryHostState.Open && host.Frames.Count == 1 &&
              !File.Exists(temporary) && !File.Exists(displaced) &&
              Directory.EnumerateFiles(fixture.Roots.LibraryRoot, "library.corrupt-*").Any(),
            "auto_recovery_interrupted_commit_leftovers_are_sidelined",
            () => $"{host.State} tmp={File.Exists(temporary)} displaced={File.Exists(displaced)}");
    }

    private static void Corrupt(StorageRootSet roots) =>
        File.WriteAllBytes(roots.CatalogPath, "this is not a database"u8.ToArray());

    private static void BreakDeclaration(StorageRootSet roots)
    {
        Microsoft.Data.Sqlite.SqliteConnectionStringBuilder builder = new()
        {
            DataSource = roots.CatalogPath,
            Mode = Microsoft.Data.Sqlite.SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using Microsoft.Data.Sqlite.SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        using Microsoft.Data.Sqlite.SqliteCommand read = connection.CreateCommand();
        read.CommandText = "SELECT id, payload FROM frames LIMIT 1";
        string id;
        System.Text.Json.Nodes.JsonObject payload;
        using (Microsoft.Data.Sqlite.SqliteDataReader row = read.ExecuteReader())
        {
            row.Read();
            id = row.GetString(0);
            payload = System.Text.Json.Nodes.JsonNode.Parse((byte[])row.GetValue(1))!.AsObject();
        }
        payload["hasDefectEdits"] = "yes";
        using Microsoft.Data.Sqlite.SqliteCommand write = connection.CreateCommand();
        write.CommandText = "UPDATE frames SET payload = $payload WHERE id = $id";
        write.Parameters.AddWithValue("$payload", System.Text.Encoding.UTF8.GetBytes(payload.ToJsonString()));
        write.Parameters.AddWithValue("$id", id);
        write.ExecuteNonQuery();
    }

    /// <summary>커밋이 실패하고 되돌리기도 실패한 자리입니다. 사본은 커밋 직전 카탈로그입니다.</summary>
    private static void AddRollbackArtifacts(StorageRootSet roots)
    {
        File.Copy(roots.CatalogPath, Path.Combine(roots.LibraryRoot, $".catalog-{Guid.NewGuid():N}.rollback"));
        File.WriteAllText($"{roots.CatalogPath}.rollback-required", "1");
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string parent = Path.Combine(Path.GetTempPath(), "negaflow-catalog-auto-recovery");
        private readonly string isolatedBase;
        private readonly List<LibraryHostService> hosts = [];

        internal Fixture(string name, bool seed)
        {
            isolatedBase = Path.Combine(parent, $"{name}-{Guid.NewGuid():N}");
            Roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
            if (!seed)
            {
                return;
            }
            using CatalogSession session = CatalogSession.Open(Roots).Session!;
            CatalogSnapshot snapshot = new(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                        [new("frame-1", TestFrameFactory.FrameRecord("frame-1", "IMG_0001.tif", 0.0))],
                });
            Check(session.Write(snapshot).IsSuccess && session.Write(snapshot).IsSuccess &&
                  File.Exists(Roots.CatalogBackupPath),
                "auto_recovery_fixture_has_previous_copy");
        }

        internal StorageRootSet Roots { get; }

        /// <summary>백업보다 새 상태를 만듭니다 — 사진 한 장을 더합니다.</summary>
        internal void WriteTwoFrames()
        {
            using CatalogSession session = CatalogSession.Open(Roots).Session!;
            CatalogSnapshot snapshot = new(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [
                        new("frame-1", TestFrameFactory.FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                        new("frame-2", TestFrameFactory.FrameRecord("frame-2", "IMG_0002.tif", 0.0)),
                    ],
                });
            Check(session.Write(snapshot).IsSuccess, "auto_recovery_fixture_newer_state");
        }

        internal void Backup()
        {
            using LibraryHostService host = NewHostUnowned();
            Check(host.Open(Roots) == LibraryHostState.Open && host.CreateBackup().IsSuccess,
                "auto_recovery_fixture_backup");
        }

        internal LibraryHostService NewHost()
        {
            LibraryHostService host = NewHostUnowned();
            hosts.Add(host);
            return host;
        }

        private static LibraryHostService NewHostUnowned() =>
            new(new FakeDispatcher(accepts: true), new FakeExporter(_ => OkResult()));

        public void Dispose()
        {
            foreach (LibraryHostService host in hosts)
            {
                host.Dispose();
            }
            try
            {
                if (Directory.Exists(isolatedBase) &&
                    StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
                {
                    Directory.Delete(isolatedBase, recursive: true);
                }
            }
            catch (IOException)
            {
            }
        }
    }
}
