using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// **한글·공백·MAX_PATH 를 넘는 경로에서 카탈로그가 저장되는지**입니다(W50).
/// </summary>
/// <remarks>
/// <para>
/// 사용자의 기본 스캔 폴더는 <c>바탕 화면\negaflow\Scans\20260907\color-negative\무제 필름</c>
/// 처럼 한글과 공백이 섞이고, 롤 이름을 길게 쓰면 260자를 쉽게 넘습니다. Win32 파일 API 는
/// 확장 경로 접두사 없이는 그 길이를 받지 않고, 실기에서 264자 경로의
/// <c>MoveFileExW</c> 가 ERROR_PATH_NOT_FOUND 로 실패해 백업 승격이 통째로
/// <see cref="CatalogStoreError.IoFailure"/> 가 됐습니다.
/// </para>
/// <para>
/// <see cref="StorageExtendedPath"/> 는 그 자리를 고친 helper 인데 직접 시험이 없었습니다.
/// 여기서는 helper 자체와, 그 helper 를 지나는 <b>실제 commit</b> 을 둘 다 봅니다 — 접두사만
/// 맞고 commit 이 깨지면 사용자에게는 똑같이 저장 실패입니다.
/// </para>
/// </remarks>
internal static class CatalogLongPathTests
{
    public static void Run(StorageRootSet parentRoots)
    {
        VerifyExtendedPathPrefix();
        VerifyCommitUnderALongKoreanPath(parentRoots);
    }

    private static void VerifyExtendedPathPrefix()
    {
        string plain = Path.Combine(Path.GetTempPath(), "negaflow-plain.sqlite");
        string extended = StorageExtendedPath.ToExtendedPath(plain);
        Check(extended.StartsWith(@"\\?\", StringComparison.Ordinal),
            "long_path_adds_the_device_prefix", () => extended);
        Check(StorageExtendedPath.ToExtendedPath(extended) == extended,
            "long_path_does_not_double_the_prefix", () => StorageExtendedPath.ToExtendedPath(extended));

        // UNC 는 `\\?\UNC\server\share` 모양이어야 합니다 - `\\?\\\server` 는 열리지 않습니다.
        string unc = StorageExtendedPath.ToExtendedPath(@"\\server\share\무제 필름\catalog.sqlite");
        Check(unc.StartsWith(@"\\?\UNC\server\share", StringComparison.Ordinal),
            "long_path_uses_the_unc_device_prefix", () => unc);
    }

    /// <summary>한글·공백이 든 260자 초과 경로에서 열기·쓰기·다시 읽기가 되어야 합니다.</summary>
    private static void VerifyCommitUnderALongKoreanPath(StorageRootSet parentRoots)
    {
        // 각 칸이 한글과 공백을 함께 담습니다. 실기 롤 이름과 같은 모양입니다.
        //
        // **칸 수를 박지 않습니다.** 시험이 도는 밑자리는 환경마다 길이가 달라(게이트에서는
        // 256자에 그쳤습니다) 고정 횟수로는 MAX_PATH 를 넘는지 보장할 수 없습니다. 넘을
        // 때까지 늘립니다.
        const string segment = "무제 필름 색보정 원본 보관";
        string deep = parentRoots.LocalApplicationDataRoot;
        // catalog 파일 이름과 백업 이름이 뒤에 더 붙으므로 여유를 두고 넘깁니다.
        for (int level = 0; level < 24 && deep.Length <= 300; ++level)
        {
            deep = Path.Combine(deep, segment);
        }
        Check(deep.Length > 260, "long_path_fixture_exceeds_max_path", () => deep.Length.ToString());

        if (StorageRootResolver.ResolveForTests(deep).Roots is not { } roots)
        {
            Check(false, "long_path_storage_root_resolves");
            return;
        }

        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            CatalogStoreError created = session.ReadOrCreate().Error;
            Check(created == CatalogStoreError.None, "long_path_catalog_creates", () => created.ToString());

            CatalogWriteResult written = session.Write(
                Snapshot("롤 하나", Row("frame-1", "하나"), Row("frame-2", "둘")));
            Check(written.IsSuccess, "long_path_catalog_writes", () => written.Error.ToString());

            // **백업 승격이 도는 두 번째 쓰기가 진짜 시험입니다.** 264자에서 깨졌던 자리입니다.
            CatalogWriteResult second = session.Write(
                Snapshot("롤 하나", Row("frame-1", "하나"), Row("frame-2", "둘"), Row("frame-3", "셋")));
            Check(second.IsSuccess, "long_path_catalog_writes_again_with_backup_promotion",
                () => second.Error.ToString());
        }

        CatalogReadResult reopened = SqliteCatalogStore.Read(roots.CatalogPath);
        Check(reopened.IsSuccess, "long_path_catalog_reopens", () => reopened.Error.ToString());
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3", "long_path_catalog_keeps_frames",
            () => FrameOrder(reopened));
        Check(File.Exists(roots.CatalogBackupPath), "long_path_backup_exists");
    }
}
