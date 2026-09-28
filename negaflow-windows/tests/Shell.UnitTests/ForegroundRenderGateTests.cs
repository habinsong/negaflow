using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 보이는 사진의 현상이 도는 동안 뒤 작업이 새 렌더를 시작하지 않게 하는 문입니다. 앞 렌더가 여럿
/// 겹쳐도(재시도는 루프를 다시 엽니다) 마지막이 끝나야 열립니다.
/// </summary>
internal static class ForegroundRenderGateTests
{
    internal static void Run()
    {
        Check(ForegroundRenderGate.WaitForIdleAsync().IsCompleted, "foreground_gate_starts_open");
        IDisposable first = ForegroundRenderGate.Enter();
        IDisposable second = ForegroundRenderGate.Enter();
        Task waiting = ForegroundRenderGate.WaitForIdleAsync();
        Check(!waiting.IsCompleted && ForegroundRenderGate.IsBusy, "foreground_gate_closes_while_rendering");
        first.Dispose();
        first.Dispose();
        Check(!waiting.IsCompleted, "foreground_gate_stays_closed_until_the_last_render_ends");
        second.Dispose();
        Check(waiting.Wait(TimeSpan.FromSeconds(1)) && !ForegroundRenderGate.IsBusy,
            "foreground_gate_opens_after_the_last_render");
        using CancellationTokenSource cancel = new();
        using (ForegroundRenderGate.Enter())
        {
            Task cancelled = ForegroundRenderGate.WaitForIdleAsync(cancel.Token);
            cancel.Cancel();
            Check(cancelled.ContinueWith(task => task.IsCanceled).Wait(TimeSpan.FromSeconds(1)) && cancelled.IsCanceled,
                "foreground_gate_wait_can_be_cancelled");
        }
    }
}
