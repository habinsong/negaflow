using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 종료 저장이 실패했을 때의 두 갈래입니다. macOS <c>ApplicationLifecycleTests</c> 의
/// <c>testQuitIsCancelledWhenTerminationSnapshotCannotBePrepared</c> ·
/// <c>testQuitProceedsWithoutSavingWhenUserConfirms</c> 와 같은 모양입니다.
/// </summary>
internal static class QuitAfterFailedSaveTests
{
    internal static void Run()
    {
        int relaunchCancelled = 0;
        int asked = 0;
        int reported = 0;
        bool quit = QuitAfterFailedSave.DecideAsync(
            () => relaunchCancelled++,
            () =>
            {
                asked++;
                return Task.FromResult(false);
            },
            () => reported++).GetAwaiter().GetResult();
        Check(!quit && asked == 1 && reported == 1 && relaunchCancelled == 1,
            "quit_after_failed_save_cancel_keeps_the_app",
            () => $"quit={quit} asked={asked} reported={reported} relaunch={relaunchCancelled}");

        relaunchCancelled = 0;
        reported = 0;
        quit = QuitAfterFailedSave.DecideAsync(
            () => relaunchCancelled++,
            () => Task.FromResult(true),
            () => reported++).GetAwaiter().GetResult();
        Check(quit && reported == 0 && relaunchCancelled == 1,
            "quit_after_failed_save_confirm_quits_without_relaunch",
            () => $"quit={quit} reported={reported} relaunch={relaunchCancelled}");
    }
}
