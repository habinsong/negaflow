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
        Recovers("rollback-required", AddRollbackArtifacts);

        // 백업 세대가 없으면 막고, 사용자가 고르는 탈출구(새로 시작)가 통해야 합니다.
        StartsFreshWithoutBackup("primary-corrupt", Corrupt);
        StartsFreshWithoutBackup("rollback-required", AddRollbackArtifacts);

        // 처음 쓰는 라이브러리는 그대로 새로 만듭니다.
        using Fixture fresh = new("first-run", seed: false);
        Check(fresh.NewHost().Open(fresh.Roots) == LibraryHostState.Open,
            "auto_recovery_first_run_opens_empty");
    }

    private static void Recovers(string name, Action<StorageRootSet> breakIt)
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

    private static void Corrupt(StorageRootSet roots) =>
        File.WriteAllBytes(roots.CatalogPath, "this is not a database"u8.ToArray());

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
