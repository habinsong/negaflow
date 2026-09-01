using Negaflow.Catalog;
using Negaflow.Shell.Storage;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 일정 백업이 <b>실제로 돌아 파일을 만드는지</b> 재는 자리입니다. 설정만 있고 부르는 곳이
/// 없으면 사용자는 "종료할 때"를 골라 두고도 백업 0 개인 채로 지냅니다.
/// macOS 대응: <c>runScheduledBackupIfDue()</c> 와 종료 경로의 <c>createLibraryBackupNow()</c>.
/// </summary>
internal static class LibraryBackupScheduleTests
{
    public static void Run()
    {
        VerifyDefaultScheduleIsOnTermination();
        VerifyTerminationCreatesBackup();
        VerifyStartupCatchUpCreatesBackup();
        VerifyManualCreatesNothing();
        VerifyBackupFailureDoesNotBlockTermination();
    }

    /// <summary>
    /// 고른 적이 없으면 "종료할 때"입니다. 설정을 한 번도 열지 않은 사용자가 안전망 0 인
    /// 채로 지내면 안 됩니다. <b>이미 저장된 선택은 그대로 존중합니다.</b>
    /// </summary>
    private static void VerifyDefaultScheduleIsOnTermination()
    {
        LibraryBackupSettings untouched = new();
        Check(untouched.Schedule is null, "backup_schedule_unchosen_is_null");
        Check(untouched.EffectiveSchedule == LibraryBackupSchedule.OnTermination,
            "backup_schedule_default_is_on_termination",
            () => untouched.EffectiveSchedule.ToString());
        Check(untouched.IsDue(DateTimeOffset.Now, isTerminating: true),
            "backup_schedule_default_is_due_on_termination");

        LibraryBackupSettings chosenManual = new()
        {
            Schedule = LibraryBackupSchedule.Manual,
            ScheduleDefaultUpgraded = true,
        };
        Check(chosenManual.Normalize().EffectiveSchedule == LibraryBackupSchedule.Manual,
            "backup_schedule_respects_stored_manual");
        Check(!chosenManual.IsDue(DateTimeOffset.Now, isTerminating: true),
            "backup_schedule_stored_manual_never_due");

        VerifyDeadScheduleDefaultIsUpgradedOnce();
    }

    /// <summary>
    /// 예전 빌드가 저장한 "수동" 은 <b>한 번도 동작한 적 없는 기본값</b>입니다 — 일정 화면은
    /// 있었지만 <c>IsDue</c> 를 부르는 코드가 없었습니다. 실기에서 확인했습니다:
    /// <c>schedule=0 · lastAttemptAt=null · lastSuccessAt=null</c> 인데 종료해도 백업이
    /// 만들어지지 않았습니다. 그 값만 딱 한 번 되돌립니다.
    /// </summary>
    private static void VerifyDeadScheduleDefaultIsUpgradedOnce()
    {
        LibraryBackupSettings stored = new() { Schedule = LibraryBackupSchedule.Manual };
        LibraryBackupSettings upgraded = stored.UpgradeDeadScheduleDefault();
        Check(upgraded.Schedule is null, "backup_dead_default_becomes_unchosen");
        Check(upgraded.EffectiveSchedule == LibraryBackupSchedule.OnTermination,
            "backup_dead_default_upgrades_to_on_termination",
            () => upgraded.EffectiveSchedule.ToString());
        Check(upgraded.ScheduleDefaultUpgraded, "backup_dead_default_records_the_upgrade");

        // 한 번뿐입니다. 그 뒤에 고른 "수동" 은 영원히 존중합니다.
        LibraryBackupSettings chosenAfterwards =
            upgraded with { Schedule = LibraryBackupSchedule.Manual };
        LibraryBackupSettings again = chosenAfterwards.UpgradeDeadScheduleDefault();
        Check(again.Schedule == LibraryBackupSchedule.Manual,
            "backup_upgrade_does_not_repeat",
            () => again.Schedule?.ToString() ?? "<null>");
        Check(!again.IsDue(DateTimeOffset.Now, isTerminating: true),
            "backup_chosen_manual_stays_manual");

        // 사용자가 실제로 고른 다른 값은 건드리지 않습니다.
        foreach (LibraryBackupSchedule chosen in (LibraryBackupSchedule[])
            [LibraryBackupSchedule.Daily, LibraryBackupSchedule.Weekly,
             LibraryBackupSchedule.OnTermination])
        {
            LibraryBackupSettings kept =
                new LibraryBackupSettings { Schedule = chosen }.UpgradeDeadScheduleDefault();
            Check(kept.Schedule == chosen, $"backup_upgrade_keeps_{chosen}");
        }
    }

    private static void VerifyTerminationCreatesBackup()
    {
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.OnTermination,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open,
            "backup_termination_open");
        Check(fixture.GenerationCount() == 0, "backup_termination_none_before_close");

        fixture.Host.Dispose();

        Check(fixture.GenerationCount() == 1, "backup_termination_creates_generation",
            () => $"generations={fixture.GenerationCount()}");
        Check(fixture.Settings.LastAttemptAt is not null, "backup_termination_records_attempt");
        Check(fixture.Settings.LastSuccessAt is not null, "backup_termination_records_success");
    }

    /// <summary>매일/매주는 밀린 것을 시작할 때 따라잡습니다.</summary>
    private static void VerifyStartupCatchUpCreatesBackup()
    {
        DateTimeOffset now = new(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.Daily,
            LastSuccessAt = now - TimeSpan.FromDays(2),
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_startup_open");

        fixture.Host.RunScheduledBackupIfDue(now, isTerminating: false);

        Check(fixture.GenerationCount() == 1, "backup_startup_catch_up_creates_generation",
            () => $"generations={fixture.GenerationCount()}");
        Check(fixture.Settings.LastSuccessAt == now, "backup_startup_records_success_time");

        // 방금 만들었으므로 다시 부르면 아무 것도 만들지 않습니다.
        fixture.Host.RunScheduledBackupIfDue(now, isTerminating: false);
        Check(fixture.GenerationCount() == 1, "backup_startup_not_due_twice");
    }

    private static void VerifyManualCreatesNothing()
    {
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.Manual,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_manual_open");
        fixture.Host.RunScheduledBackupIfDue(DateTimeOffset.Now, isTerminating: false);
        fixture.Host.Dispose();
        Check(fixture.GenerationCount() == 0, "backup_manual_creates_nothing");
        Check(fixture.Settings.LastAttemptAt is null, "backup_manual_records_no_attempt");
    }

    /// <summary>
    /// 카탈로그 커밋은 백업보다 먼저 끝나므로 데이터는 이미 안전합니다. 백업이 실패했다고
    /// 종료가 막히면 사용자는 앱을 끌 수 없습니다 — 실패는 적고 종료는 진행합니다.
    /// </summary>
    private static void VerifyBackupFailureDoesNotBlockTermination()
    {
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.OnTermination,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_failure_open");
        // 카탈로그 파일을 치우면 백업이 읽을 것이 없어 InvalidCatalog 로 실패합니다.
        File.Delete(fixture.Roots.CatalogPath);

        bool threw = false;
        try
        {
            fixture.Host.Dispose();
        }
        catch (Exception error)
        {
            threw = true;
            Check(false, "backup_failure_blocks_termination", () => error.GetType().Name);
        }
        Check(!threw, "backup_failure_does_not_block_termination");
        Check(fixture.GenerationCount() == 0, "backup_failure_creates_no_generation");
        Check(fixture.Settings.LastAttemptAt is not null,
            "backup_failure_records_attempt");
        Check(fixture.Settings.LastSuccessAt is null,
            "backup_failure_records_no_false_success");
    }

    private sealed class ScheduleFixture : IDisposable
    {
        private readonly string testParent;
        private readonly string isolatedBase;

        internal ScheduleFixture(LibraryBackupSettings settings)
        {
            Settings = settings;
            testParent = Path.Combine(AppContext.BaseDirectory, "backup-schedule-tests");
            isolatedBase = Path.Combine(
                testParent,
                $"{Environment.ProcessId}-{Guid.NewGuid():N}");
            Roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
            using (CatalogSession seed = CatalogSession.Open(Roots).Session!)
            {
                _ = seed.Write(CatalogSnapshot.Empty);
            }
            Host = new LibraryHostService(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()))
            {
                BackupSchedule = new LibraryBackupScheduleBinding(
                    () => Settings,
                    update => Settings = update(Settings)),
            };
        }

        internal LibraryBackupSettings Settings { get; private set; }

        internal StorageRootSet Roots { get; }

        internal LibraryHostService Host { get; }

        internal int GenerationCount() =>
            Directory.Exists(Roots.BackupRoot)
                ? Directory.GetDirectories(Roots.BackupRoot, "backup-*").Length
                : 0;

        public void Dispose()
        {
            Host.Dispose();
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }
}
