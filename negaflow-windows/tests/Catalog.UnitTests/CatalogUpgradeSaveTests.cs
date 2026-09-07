using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// **1.1.4 이하가 쓴 카탈로그를 이 빌드로 열었을 때 저장이 되는지**를 잽니다.
/// </summary>
/// <remarks>
/// 실기에서 그대로 났습니다. 논리 catalog version 을 1 에서 2 로 올린 뒤(`d0aa9935`),
/// 1 로 쓰인 130장짜리 카탈로그가 이렇게 됐습니다:
///
/// - 열립니다. 사진도 다 보입니다 — <see cref="SqliteCatalogStore.Read"/> 가 사다리로 올립니다.
/// - 저장은 <b>전부</b> <see cref="CatalogStoreError.IoFailure"/> 로 막힙니다.
/// - 종료 경로가 저장부터 하므로 <b>앱이 꺼지지 않습니다</b>(termination.txt 12:57~12:58, 4회).
///
/// commit 은 새 primary 를 쓰기 <b>전에</b> 직전 primary 를 백업으로 보존하고, 그 보존은
/// <c>IsValidCatalogSource</c> 를 통과해야 하는데 그 검사만 디스크의 <b>원시</b> version 이
/// 현재 상수와 정확히 같은지를 봤습니다. 보존이 먼저라 2 로 다시 쓸 기회가 오지 않는
/// 교착이었습니다.
/// </remarks>
internal static class CatalogUpgradeSaveTests
{
    public static void Run(StorageRootSet parentRoots)
    {
        VerifyOlderCatalogStillSaves(parentRoots);
        VerifyOlderCatalogIsAValidPreservationSource(parentRoots);
        VerifyFutureCatalogIsStillRefusedAsSource(parentRoots);
    }

    /// <summary>이전 판이 쓴 카탈로그를 열고, 바뀐 것 없이 저장해도 성공해야 합니다.</summary>
    private static void VerifyOlderCatalogStillSaves(StorageRootSet parentRoots)
    {
        StorageRootSet roots = ChildRoots(parentRoots, "upgrade-save");
        WritePreviousVersionCatalog(roots.CatalogPath);

        // 열기는 예전에도 됐습니다. 여기서 막히면 이 시험이 재는 자리가 아닙니다.
        CatalogReadResult opened = SqliteCatalogStore.Read(roots.CatalogPath);
        Check(opened.IsSuccess, "upgrade_save_opens_previous_version",
            () => opened.Error.ToString());
        Check(opened.Snapshot?.CatalogVersion == CatalogSnapshot.CurrentCatalogVersion,
            "upgrade_save_read_promotes");
        Check(FrameOrder(opened) == "frame-1,frame-2", "upgrade_save_keeps_frames");

        // **막혔던 자리입니다.** 백업이 없고 내용이 그대로라 commit 은 "직전 primary 보존"
        // 으로 갑니다. 예전에는 여기서 IoFailure 였습니다.
        CatalogWriteResult unchanged = CatalogCommitVerifier.Commit(opened.Snapshot!, roots);
        Check(unchanged.IsSuccess, "upgrade_save_unchanged_commit_succeeds",
            () => unchanged.Error.ToString());

        // 바뀐 내용도 저장돼야 하고, 그때 디스크 파일이 현재 version 으로 올라가야 합니다.
        CatalogSnapshot edited = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"),
            Row("frame-3", "three"));
        CatalogWriteResult changed = CatalogCommitVerifier.Commit(edited, roots);
        Check(changed.IsSuccess, "upgrade_save_changed_commit_succeeds",
            () => changed.Error.ToString());

        CatalogReadResult reopened = SqliteCatalogStore.Read(roots.CatalogPath);
        Check(reopened.IsSuccess, "upgrade_save_reopens", () => reopened.Error.ToString());
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3",
            "upgrade_save_persists_the_edit");
    }

    /// <summary>
    /// 보존 대상 판정 자체를 직접 잽니다. commit 을 거치지 않아 어디가 틀렸는지가 분명합니다.
    /// </summary>
    private static void VerifyOlderCatalogIsAValidPreservationSource(StorageRootSet parentRoots)
    {
        StorageRootSet roots = ChildRoots(parentRoots, "upgrade-source");
        WritePreviousVersionCatalog(roots.CatalogPath);
        Check(CatalogRecovery.IsValidCatalogSource(roots.CatalogPath),
            "upgrade_previous_version_is_a_valid_source");
    }

    /// <summary>
    /// 느슨해진 것이 아니어야 합니다. 이 빌드보다 <b>높은</b> version 은 여전히 거부입니다 —
    /// 모르는 형식을 백업으로 승격시키면 되돌릴 것을 잃습니다.
    /// </summary>
    private static void VerifyFutureCatalogIsStillRefusedAsSource(StorageRootSet parentRoots)
    {
        StorageRootSet roots = ChildRoots(parentRoots, "upgrade-future");
        Check(SqliteCatalogStore.Write(Snapshot("roll-a", Row("frame-1", "one")), roots.CatalogPath)
            .IsSuccess, "upgrade_future_fixture_write");
        SetCatalogVersions(roots.CatalogPath, CatalogSnapshot.CurrentCatalogVersion + 1,
            CatalogSnapshot.CurrentCatalogVersion + 1);
        Check(!CatalogRecovery.IsValidCatalogSource(roots.CatalogPath),
            "upgrade_future_version_is_not_a_valid_source");
    }

    /// <summary>이전 판이 쓴 것과 같은 파일을 만듭니다 — 논리 version 만 한 칸 아래입니다.</summary>
    private static void WritePreviousVersionCatalog(string catalogPath)
    {
        Check(SqliteCatalogStore.Write(
                Snapshot("roll-a", Row("frame-1", "one"), Row("frame-2", "two")),
                catalogPath).IsSuccess,
            "upgrade_fixture_write");
        SetCatalogVersions(
            catalogPath,
            CatalogSnapshot.CurrentCatalogVersion - 1,
            CatalogSnapshot.CurrentCatalogVersion - 1);
    }

    private static void SetCatalogVersions(string catalogPath, int version, int minimumReader) =>
        ExecuteFixtureSql(
            catalogPath,
            $"UPDATE catalog_metadata SET catalog_version={version}, " +
            $"minimum_reader_version={minimumReader} WHERE singleton=1");

    private static StorageRootSet ChildRoots(StorageRootSet parentRoots, string name) =>
        StorageRootResolver.ResolveForTests(
            Path.Combine(parentRoots.LocalApplicationDataRoot, name)).Roots!;
}
