using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

using static Negaflow.Catalog.UnitTests.CatalogProcessLockTests;

internal static class CatalogSessionTests
{
    public static void Run(StorageRootSet roots) => VerifyCatalogSession(roots);

    private static void VerifyCatalogSession(StorageRootSet roots)
    {
        string sessionBase = Path.Combine(
            Path.GetDirectoryName(roots.LocalApplicationDataRoot)!,
            $"session-{Guid.NewGuid():N}");
        StorageRootSet sessionRoots = StorageRootResolver.ResolveForTests(sessionBase).Roots!;
        CatalogSession? session = null;

        try
        {
            CatalogSessionOpenResult opened = CatalogSession.Open(sessionRoots);
            session = opened.Session;
            Check(opened.IsSuccess, "session_open");
            Check(session?.IsOpen == true, "session_open_is_open");
            Check(File.Exists(sessionRoots.CatalogLockPath), "session_holds_lock");
            Check(!File.Exists(sessionRoots.CatalogPath), "session_open_does_not_create_catalog");

            // 두 번째 작성자는 lock 에서 막힙니다. 세션 없이는 store 에 닿을 방법이 없습니다.
            CatalogSessionOpenResult second = CatalogSession.Open(sessionRoots);
            Check(!second.IsSuccess, "session_second_rejected");
            Check(second.Error == CatalogSessionError.Busy, "session_second_busy");
            Check(second.Session is null, "session_busy_no_partial_session");

            // 프로세스 경계에서도 같아야 합니다. 같은 프로세스 안의 거부만 보면 FileShare.None 이
            // 실제로 무엇을 막는지는 추론으로 남습니다.
            Check(RunContenderProcess(sessionBase) == "Busy", "session_other_process_busy");

            Check(session!.Read().Error == CatalogStoreError.NotFound,
                "session_read_absent_is_not_found");

            CatalogReadResult created = session.ReadOrCreate();
            Check(created.IsSuccess, "session_read_or_create_success");
            Check(created.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
                "session_read_or_create_is_empty");
            Check(File.Exists(sessionRoots.CatalogPath), "session_read_or_create_creates_file");

            Check(session.Write(Snapshot("roll-s", Row("frame-1", "one"))).IsSuccess,
                "session_write");
            Check(FrameOrder(session.Read()) == "frame-1", "session_write_round_trip");

            // 이미 있는 카탈로그에서는 ReadOrCreate 가 덮지 않습니다.
            CatalogReadResult reopened = session.ReadOrCreate();
            Check(FrameOrder(reopened) == "frame-1", "session_read_or_create_preserves_existing");

            // 손상은 ReadOrCreate 에서도 빈 라이브러리가 되지 않습니다.
            session.Dispose();
            File.WriteAllBytes(sessionRoots.CatalogPath, "not a database"u8.ToArray());
            CatalogSessionOpenResult reopenedSession = CatalogSession.Open(sessionRoots);
            session = reopenedSession.Session;
            Check(reopenedSession.IsSuccess, "session_reopen_after_dispose");
            Check(session!.ReadOrCreate().Error == CatalogStoreError.CorruptDatabase,
                "session_read_or_create_refuses_corrupt");

            session.Dispose();
            Check(session.IsOpen == false, "session_dispose_releases_lock");
            bool threw = false;
            try
            {
                session.Read();
            }
            catch (ObjectDisposedException)
            {
                threw = true;
            }
            Check(threw, "session_read_after_dispose_throws");

            CatalogSessionOpenResult third = CatalogSession.Open(sessionRoots);
            Check(third.IsSuccess, "session_reacquire_after_dispose");
            third.Session?.Dispose();

            // lock 이 풀린 뒤에는 다른 프로세스가 잡을 수 있어야 합니다. 위의 Busy 가 경로 오류나
            // 프로세스 기동 실패를 잘못 읽은 것이 아님을 이것이 확인합니다.
            Check(RunContenderProcess(sessionBase) == "acquired",
                "session_other_process_acquires_when_free");
        }
        finally
        {
            session?.Dispose();
            if (Directory.Exists(sessionBase))
            {
                Directory.Delete(sessionBase, recursive: true);
            }
        }
    }

}
