using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 카탈로그를 열지 못했을 때 <b>사용자가 빠져나갈 수 있는지</b> 재는 자리입니다.
/// macOS 대응: <c>LibraryBlockedRecoveryView</c> 와 <c>AppModel+LibraryRecovery</c>.
/// </summary>
internal static class LibraryRecoveryTests
{
    public static void Run()
    {
        VerifyBlockedOpenIsReported();
        VerifyBackupGenerationsAreListedWithReasons();
        VerifyRestoreFromBlockedState();
        VerifyStartFreshEscapesWithoutBackups();
        VerifyDiagnosticsNarrowTheCause();
    }

    /// <summary>
    /// 지원 요청을 받았을 때 "왜 못 열었는지" 를 좁힐 수 있어야 합니다. macOS 에서 이번
    /// 사고의 원인을 찾는 데 오래 걸린 것은 진단이 <c>failure=corrupt</c> 까지밖에
    /// 알려 주지 않아서였습니다. <b>경로·파일명·사진 내용은 담지 않습니다.</b>
    /// </summary>
    private static void VerifyDiagnosticsNarrowTheCause()
    {
        using RecoveryFixture fixture = new();
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open,
            "recovery_diagnostics_open");
        Check(fixture.Host.CreateBackup().IsSuccess, "recovery_diagnostics_backup");
        string text = fixture.Host.BuildRecoveryDiagnostics("9.9.9").Text;

        Check(text.StartsWith("negaflow.library-recovery.v1", StringComparison.Ordinal),
            "recovery_diagnostics_has_marker");
        Check(text.Contains("appVersion=9.9.9", StringComparison.Ordinal),
            "recovery_diagnostics_has_version");
        Check(text.Contains("lifecycle=Open", StringComparison.Ordinal),
            "recovery_diagnostics_has_lifecycle");
        Check(text.Contains("backupCount=1", StringComparison.Ordinal),
            "recovery_diagnostics_has_backup_count");
        Check(text.Contains("backup[0].state=Verified", StringComparison.Ordinal),
            "recovery_diagnostics_has_generation_state");
        // W8 이 요구한 관측값들입니다 - 이것이 없으면 다음 사고에서 또 코드 하나로만 봅니다.
        Check(text.Contains("userVersion=1", StringComparison.Ordinal),
            "recovery_diagnostics_has_user_version");
        Check(text.Contains("catalogVersion=1", StringComparison.Ordinal),
            "recovery_diagnostics_has_catalog_version");
        Check(text.Contains("integrityCheck=ok", StringComparison.Ordinal),
            "recovery_diagnostics_has_integrity_check");
        Check(text.Contains("rows.frames=1", StringComparison.Ordinal),
            "recovery_diagnostics_has_table_row_counts",
            () => text);
        Check(text.Contains("unreadableFrames=0", StringComparison.Ordinal),
            "recovery_diagnostics_has_unreadable_frame_count");
        Check(!text.Contains(fixture.Roots.CatalogPath, StringComparison.OrdinalIgnoreCase),
            "recovery_diagnostics_omits_paths");
        Check(!text.Contains("IMG_0001", StringComparison.Ordinal),
            "recovery_diagnostics_omits_file_names");

        // 못 여는 카탈로그에서도 판정이 남아야 합니다 - 그때가 지원 요청이 오는 때입니다.
        fixture.Host.Dispose();
        LibraryHostService blocked = fixture.NewHost();
        fixture.CorruptCatalog();
        Check(blocked.Open(fixture.Roots) == LibraryHostState.Unavailable,
            "recovery_diagnostics_blocked_open");
        string blockedText = blocked.BuildRecoveryDiagnostics("9.9.9").Text;
        Check(blockedText.Contains("lifecycle=Unavailable", StringComparison.Ordinal),
            "recovery_diagnostics_blocked_lifecycle");
        Check(blockedText.Contains("catalogRead=", StringComparison.Ordinal) &&
            !blockedText.Contains("catalogRead=None", StringComparison.Ordinal),
            "recovery_diagnostics_blocked_reports_read_error",
            () => blockedText);
        Check(blockedText.Contains("integrityCheck=failed", StringComparison.Ordinal),
            "recovery_diagnostics_blocked_integrity_failed",
            () => blockedText);
    }

    /// <summary>
    /// 못 열면 <see cref="LibraryHostState.Unavailable"/> 이고, 어디를 열려다 실패했는지가
    /// 남아야 합니다. 이것이 없으면 화면은 아무 것도 보여 줄 수 없습니다.
    /// </summary>
    private static void VerifyBlockedOpenIsReported()
    {
        using RecoveryFixture fixture = new();
        fixture.CorruptCatalog();

        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Unavailable,
            "recovery_blocked_state",
            () => fixture.Host.State.ToString());
        Check(fixture.Host.StoreError != CatalogStoreError.None,
            "recovery_blocked_reports_store_error",
            () => fixture.Host.StoreError.ToString());
        Check(fixture.Host.AttemptedRoots is not null,
            "recovery_blocked_keeps_attempted_roots");
        Check(fixture.Host.StorageRoots is null,
            "recovery_blocked_does_not_claim_open_roots");
        Check(fixture.Host.Frames.Count == 0, "recovery_blocked_has_no_frames");
    }

    /// <summary>
    /// 복원할 수 없는 세대는 <b>왜</b> 안 되는지 보여 줄 수 있어야 합니다 — 이유 없이
    /// 비활성인 버튼은 버그로 보입니다.
    /// </summary>
    private static void VerifyBackupGenerationsAreListedWithReasons()
    {
        using RecoveryFixture fixture = new();
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "recovery_list_open");
        Check(fixture.Host.BackupGenerations().Count == 0, "recovery_list_starts_empty");

        Check(fixture.Host.CreateBackup().IsSuccess, "recovery_list_creates_backup");
        IReadOnlyList<CatalogBackupGeneration> listed = fixture.Host.BackupGenerations();
        Check(listed.Count == 1, "recovery_list_sees_generation",
            () => $"count={listed.Count}");
        if (listed.Count != 1)
        {
            return;
        }
        Check(listed[0].State == CatalogBackupGenerationState.Verified,
            "recovery_list_generation_verified", () => listed[0].State.ToString());
        Check(listed[0].IsRestorable, "recovery_list_generation_restorable");
        Check(listed[0].FrameCount == 1, "recovery_list_generation_frame_count",
            () => $"frames={listed[0].FrameCount}");
        Check(listed[0].CreatedAt is not null, "recovery_list_generation_created_at");

        // 세대 안의 카탈로그를 망가뜨리면 목록에는 남되 복원 후보에서는 빠져야 합니다.
        fixture.DamageGeneration(listed[0].Id);
        IReadOnlyList<CatalogBackupGeneration> damaged = fixture.Host.BackupGenerations();
        Check(damaged.Count == 1, "recovery_list_keeps_damaged_generation");
        Check(damaged.Count == 1 && !damaged[0].IsRestorable,
            "recovery_list_damaged_not_restorable");
        Check(damaged.Count == 1 && damaged[0].State == CatalogBackupGenerationState.Damaged,
            "recovery_list_damaged_state",
            () => damaged.Count == 1 ? damaged[0].State.ToString() : "<none>");
        Check(damaged.Count == 1 && damaged[0].FrameCount == 1,
            "recovery_list_damaged_still_reports_counts");
    }

    /// <summary>차단된 상태에서 백업을 골라 되돌리면 사진이 돌아와야 합니다.</summary>
    private static void VerifyRestoreFromBlockedState()
    {
        using RecoveryFixture fixture = new();
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "recovery_restore_open");
        Check(fixture.Host.CreateBackup().IsSuccess, "recovery_restore_backup");
        string generationId = fixture.Host.BackupGenerations()[0].Id;
        fixture.Host.Dispose();

        LibraryHostService blocked = fixture.NewHost();
        fixture.CorruptCatalog();
        Check(blocked.Open(fixture.Roots) == LibraryHostState.Unavailable,
            "recovery_restore_blocked");
        Check(blocked.Frames.Count == 0, "recovery_restore_blocked_has_no_frames");

        CatalogPendingRestoreScheduleResult scheduled = blocked.ScheduleRestore(generationId);
        Check(scheduled.IsSuccess, "recovery_restore_schedules",
            () => scheduled.Error.ToString());
        Check(blocked.RetryOpen() == LibraryHostState.Open, "recovery_restore_reopens",
            () => $"{blocked.State}/session={blocked.SessionError}/store={blocked.StoreError}/defect={blocked.DefectSidecarError}");
        Check(blocked.Frames.Count == 1, "recovery_restore_returns_frames",
            () => $"frames={blocked.Frames.Count}");
    }

    /// <summary>
    /// 백업이 하나도 없을 때 사용자가 빠져나갈 유일한 길입니다. 빠져나간 뒤 원래 카탈로그의
    /// 사본이 옆에 남아 있어야 합니다 — 잘못된 선택이었을 때 되돌릴 것이 있어야 합니다.
    /// </summary>
    private static void VerifyStartFreshEscapesWithoutBackups()
    {
        using RecoveryFixture fixture = new();
        fixture.CorruptCatalog();
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Unavailable,
            "recovery_fresh_blocked");
        Check(fixture.Host.BackupGenerations().Count == 0, "recovery_fresh_no_backups");

        Check(fixture.Host.StartFreshLibrary(), "recovery_fresh_starts");
        Check(fixture.Host.State == LibraryHostState.Open, "recovery_fresh_opens",
            () => $"{fixture.Host.State}/{fixture.Host.StoreError}");
        Check(fixture.Host.Frames.Count == 0, "recovery_fresh_is_empty");
        Check(fixture.PreservedCatalogCount() == 1, "recovery_fresh_preserves_original",
            () => $"copies={fixture.PreservedCatalogCount()}");
    }

    private sealed class RecoveryFixture : IDisposable
    {
        private readonly string testParent;
        private readonly string isolatedBase;
        private readonly List<LibraryHostService> hosts = [];

        internal RecoveryFixture()
        {
            testParent = Path.Combine(AppContext.BaseDirectory, "library-recovery-tests");
            isolatedBase = Path.Combine(
                testParent,
                $"{Environment.ProcessId}-{Guid.NewGuid():N}");
            Roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
            using (CatalogSession seed = CatalogSession.Open(Roots).Session!)
            {
                _ = seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", TestFrameFactory.FrameRecord(
                                "frame-1",
                                "IMG_0001.tif",
                                0.0)),
                        ],
                    }));
            }
            Host = NewHost();
        }

        internal StorageRootSet Roots { get; }

        internal LibraryHostService Host { get; }

        internal LibraryHostService NewHost()
        {
            LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()));
            hosts.Add(host);
            return host;
        }

        /// <summary>이 빌드가 못 읽는 카탈로그로 만듭니다.</summary>
        internal void CorruptCatalog() =>
            File.WriteAllBytes(Roots.CatalogPath, "this is not a database"u8.ToArray());

        /// <summary>세대 안의 카탈로그만 흔들어 검증을 깨뜨립니다. 매니페스트는 남깁니다.</summary>
        internal void DamageGeneration(string generationId) =>
            File.WriteAllBytes(
                Path.Combine(Roots.BackupRoot, generationId, "library.json"),
                "{}"u8.ToArray());

        internal int PreservedCatalogCount() =>
            Directory.Exists(Roots.LibraryRoot)
                ? Directory.GetFiles(Roots.LibraryRoot, "library.corrupt-*").Length
                : 0;

        public void Dispose()
        {
            foreach (LibraryHostService host in hosts)
            {
                host.Dispose();
            }
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }
}
