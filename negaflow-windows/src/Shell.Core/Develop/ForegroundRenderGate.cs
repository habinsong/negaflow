namespace Negaflow.Shell.Develop;

/// <summary>
/// 보이는 사진의 현상이 도는 동안 뒤 작업(썸네일·인화 판 현상)이 새 렌더를 시작하지 않게 합니다.
/// </summary>
/// <remarks>
/// 실측(실제 라이브러리 138장, 엔진이 바뀐 첫 실행): 썸네일 재렌더가 여러 스레드로 도는 동안 사진을
/// 바꾸면 그 렌더들이 디스크와 CPU 를 나눠 써, 고른 사진의 첫 단계가 최대 945 ms 늦었습니다. 앞
/// 요청은 뒤 작업을 기다리지 않으므로 서로 기다리는 일이 없습니다. 이미 시작한 뒤 작업은 끝까지 돕니다.
/// </remarks>
public static class ForegroundRenderGate
{
    private static readonly Lock Gate = new();
    private static int active;
    private static TaskCompletionSource idle = Completed();

    /// <summary>앞 렌더가 시작됐습니다. 끝나면 돌려준 값을 버립니다.</summary>
    public static IDisposable Enter()
    {
        lock (Gate)
        {
            if (active++ == 0)
            {
                idle = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            }
        }
        return new Exit();
    }

    /// <summary>앞 렌더가 없을 때 끝납니다. 뒤 작업이 새 렌더를 시작하기 전에 기다립니다.</summary>
    public static Task WaitForIdleAsync(CancellationToken cancellationToken = default)
    {
        Task task;
        lock (Gate)
        {
            task = idle.Task;
        }
        return task.IsCompleted ? Task.CompletedTask : task.WaitAsync(cancellationToken);
    }

    public static bool IsBusy
    {
        get
        {
            lock (Gate)
            {
                return active != 0;
            }
        }
    }

    private static void Leave()
    {
        TaskCompletionSource? release = null;
        lock (Gate)
        {
            if (--active == 0)
            {
                release = idle;
            }
        }
        release?.TrySetResult();
    }

    private static TaskCompletionSource Completed()
    {
        TaskCompletionSource source = new(TaskCreationOptions.RunContinuationsAsynchronously);
        source.SetResult();
        return source;
    }

    private sealed class Exit : IDisposable
    {
        private int disposed;

        public void Dispose()
        {
            if (Interlocked.Exchange(ref disposed, 1) == 0)
            {
                Leave();
            }
        }
    }
}
