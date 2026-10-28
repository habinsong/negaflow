using Negaflow.Catalog;
using Negaflow.Shell.Storage;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 일정 백업이 <b>실제로 돌아 파일을 만드는지</b>, 그리고 <b>종료가 백업을 기다리지 않는지</b> 재는 자리입니다.
/// macOS 대응: <c>runScheduledBackupIfDue()</c>(매일·매주)와 <c>scheduleSessionBackupAfterSave()</c>(변경 후 자동).
/// 예전에는 기본 일정이 "종료할 때" 라 종료마다 백업을 UI 스레드에서 기다려 창이 "응답 없음" 이 됐습니다.
/// </summary>
internal static class LibraryBackupScheduleTests
{
    public static void Run()
    {
        VerifyDefaultScheduleIsAutomatic();
        VerifyTerminationCreatesNoBackup();
        VerifySessionBackupAfterSave();
        VerifyStartupCatchUpCreatesBackup();
        VerifyManualCreatesNothing();
        VerifyBackupFailureIsRecorded();
    }

    /// <summary>
    /// 고른 적이 없으면 "변경 후 자동" 입니다(저장값은 예전 "종료할 때" 그대로). 시작·종료 일정으로는 돌지
    /// 않습니다. <b>이미 저장된 선택은 그대로 존중합니다.</b>
    /// </summary>
    private static void VerifyDefaultScheduleIsAutomatic()
    {
        LibraryBackupSettings untouched = new();
        Check(untouched.Schedule is null, "backup_schedule_unchosen_is_null");
        Check(untouched.EffectiveSchedule == LibraryBackupSchedule.OnTermination,
            "backup_schedule_default_is_automatic",
            () => untouched.EffectiveSchedule.ToString());
        Check(!untouched.IsDue(DateTimeOffset.Now), "backup_schedule_automatic_is_not_a_timed_backup");

        LibraryBackupSettings chosenManual = new()
        {
            Schedule = LibraryBackupSchedule.Manual,
            ScheduleDefaultUpgraded = true,
        };
        Check(chosenManual.Normalize().EffectiveSchedule == LibraryBackupSchedule.Manual,
            "backup_schedule_respects_stored_manual");
        Check(!chosenManual.IsDue(DateTimeOffset.Now), "backup_schedule_stored_manual_never_due");

        VerifyDeadScheduleDefaultIsUpgradedOnce();
    }

    /// <summary>
    /// 예전 빌드가 저장한 "수동" 은 <b>한 번도 동작한 적 없는 기본값</b>입니다. 그 값만 딱 한 번 되돌립니다.
    /// </summary>
    private static void VerifyDeadScheduleDefaultIsUpgradedOnce()
    {
        LibraryBackupSettings stored = new() { Schedule = LibraryBackupSchedule.Manual };
        LibraryBackupSettings upgraded = stored.UpgradeDeadScheduleDefault();
        Check(upgraded.Schedule is null, "backup_dead_default_becomes_unchosen");
        Check(upgraded.EffectiveSchedule == LibraryBackupSchedule.OnTermination,
            "backup_dead_default_upgrades_to_automatic",
            () => upgraded.EffectiveSchedule.ToString());
        Check(upgraded.ScheduleDefaultUpgraded, "backup_dead_default_records_the_upgrade");

        // 한 번뿐입니다. 그 뒤에 고른 "수동" 은 영원히 존중합니다.
        LibraryBackupSettings chosenAfterwards =
            upgraded with { Schedule = LibraryBackupSchedule.Manual };
        LibraryBackupSettings again = chosenAfterwards.UpgradeDeadScheduleDefault();
        Check(again.Schedule == LibraryBackupSchedule.Manual,
            "backup_upgrade_does_not_repeat",
            () => again.Schedule?.ToString() ?? "<null>");
        Check(!again.IsDue(DateTimeOffset.Now), "backup_chosen_manual_stays_manual");

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

    /// <summary>종료는 백업을 만들지 않고 시도도 적지 않습니다 — 백업을 기다리느라 멈추지 않습니다.</summary>
    private static void VerifyTerminationCreatesNoBackup()
    {
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.OnTermination,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_termination_open");

        fixture.Host.Dispose();

        Check(fixture.GenerationCount() == 0, "backup_termination_creates_no_generation",
            () => $"generations={fixture.GenerationCount()}");
        Check(fixture.Settings.LastAttemptAt is null, "backup_termination_records_no_attempt");
    }

    /// <summary>
    /// 저장 뒤 잠시 지나면 백그라운드로 한 세대를 만들고, 한 시간 안에는 다시 만들지 않습니다(macOS
    /// <c>scheduleSessionBackupAfterSave</c>). 종료가 시작되면 더 예약하지 않습니다.
    /// </summary>
    private static void VerifySessionBackupAfterSave()
    {
        using ScheduleFixture fixture = new(
            new LibraryBackupSettings { Schedule = LibraryBackupSchedule.OnTermination },
            sessionBackupDelay: TimeSpan.FromMilliseconds(20));
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_session_open");

        DateTimeOffset now = DateTimeOffset.Now;
        fixture.Host.ScheduleSessionBackupAfterSave(now);
        Check(fixture.WaitForSessionBackup(), "backup_session_finishes");
        Check(fixture.GenerationCount() == 1, "backup_session_creates_generation",
            () => $"generations={fixture.GenerationCount()}");
        Check(fixture.Settings.LastAttemptAt is not null && fixture.Settings.LastSuccessAt is not null,
            "backup_session_records_attempt_and_success");

        // 방금 시도했으므로 한 시간 안의 저장은 새 세대를 만들지 않습니다.
        fixture.Host.ScheduleSessionBackupAfterSave(now + TimeSpan.FromMinutes(5));
        Thread.Sleep(200);
        Check(fixture.GenerationCount() == 1, "backup_session_respects_minimum_interval",
            () => $"generations={fixture.GenerationCount()}");

        // 종료가 시작되면 더 예약하지 않습니다.
        _ = fixture.Host.PrepareForTerminationAsync(fixture.Roots.LibraryRoot);
        fixture.Host.ScheduleSessionBackupAfterSave(now + TimeSpan.FromHours(2));
        Thread.Sleep(200);
        Check(fixture.GenerationCount() == 1, "backup_session_stops_at_termination",
            () => $"generations={fixture.GenerationCount()}");
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

        fixture.Host.RunScheduledBackupIfDue(now);

        Check(fixture.GenerationCount() == 1, "backup_startup_catch_up_creates_generation",
            () => $"generations={fixture.GenerationCount()}");
        Check(fixture.Settings.LastSuccessAt == now, "backup_startup_records_success_time");

        // 방금 만들었으므로 다시 부르면 아무 것도 만들지 않습니다.
        fixture.Host.RunScheduledBackupIfDue(now);
        Check(fixture.GenerationCount() == 1, "backup_startup_not_due_twice");
    }

    private static void VerifyManualCreatesNothing()
    {
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.Manual,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_manual_open");
        fixture.Host.RunScheduledBackupIfDue(DateTimeOffset.Now);
        fixture.Host.ScheduleSessionBackupAfterSave(DateTimeOffset.Now);
        fixture.Host.Dispose();
        Check(fixture.GenerationCount() == 0, "backup_manual_creates_nothing");
        Check(fixture.Settings.LastAttemptAt is null, "backup_manual_records_no_attempt");
    }

    /// <summary>
    /// 백업이 실패해도 던지지 않고 시도만 적습니다. 성공은 정말 성공했을 때만 적습니다.
    /// </summary>
    private static void VerifyBackupFailureIsRecorded()
    {
        DateTimeOffset now = new(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);
        using ScheduleFixture fixture = new(new LibraryBackupSettings
        {
            Schedule = LibraryBackupSchedule.Daily,
        });
        Check(fixture.Host.Open(fixture.Roots) == LibraryHostState.Open, "backup_failure_open");
        // 카탈로그 파일을 치우면 백업이 읽을 것이 없어 InvalidCatalog 로 실패합니다.
        File.Delete(fixture.Roots.CatalogPath);

        bool threw = false;
        try
        {
            _ = fixture.Host.RunScheduledBackupIfDue(now);
            fixture.Host.Dispose();
        }
        catch (Exception error)
        {
            threw = true;
            Check(false, "backup_failure_throws", () => error.GetType().Name);
        }
        Check(!threw, "backup_failure_does_not_throw");
        Check(fixture.GenerationCount() == 0, "backup_failure_creates_no_generation");
        Check(fixture.Settings.LastAttemptAt is not null, "backup_failure_records_attempt");
        Check(fixture.Settings.LastSuccessAt is null, "backup_failure_records_no_false_success");
    }

    private sealed class ScheduleFixture : IDisposable
    {
        private readonly string testParent;
        private readonly string isolatedBase;

        internal ScheduleFixture(LibraryBackupSettings settings, TimeSpan? sessionBackupDelay = null)
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
                    update => { lock (gate) { Settings = update(Settings); } }),
                SessionBackupDelay = sessionBackupDelay ?? TimeSpan.FromSeconds(120),
            };
        }

        private readonly Lock gate = new();

        internal bool WaitForSessionBackup()
        {
            for (int attempt = 0; attempt < 200; ++attempt)
            {
                if (Host.SessionBackupTask is { } task)
                {
                    return task.Wait(TimeSpan.FromSeconds(10));
                }
                Thread.Sleep(10);
            }
            return false;
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
