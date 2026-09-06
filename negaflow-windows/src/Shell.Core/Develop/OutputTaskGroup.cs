namespace Negaflow.Shell.Develop;

/// <summary>파일 출력과 부속 파일 게시가 끝날 때까지 종료를 기다립니다.</summary>
public sealed class OutputTaskGroup
{
    private readonly Lock gate = new();
    private readonly HashSet<Task> active = [];
    private bool draining;
    public bool IsRunning { get { lock (gate) { return active.Count != 0; } } }

    public async Task RunAsync(Func<Task> operation)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate)
        {
            if (draining || active.Count != 0) { return; }
            active.Add(completion.Task);
        }
        try { await operation().ConfigureAwait(true); }
        finally
        {
            lock (gate) { active.Remove(completion.Task); }
            completion.SetResult();
        }
    }

    public async Task DrainAsync()
    {
        Task[] pending;
        lock (gate) { draining = true; pending = [.. active]; }
        try { await Task.WhenAll(pending).ConfigureAwait(false); }
        finally { lock (gate) { draining = false; } }
    }
}
