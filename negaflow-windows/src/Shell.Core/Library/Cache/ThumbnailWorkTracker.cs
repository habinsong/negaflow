namespace Negaflow.Shell.Library;

/// <summary>프레임 세대와 시작 전 등록, 종료 대기를 관리합니다. 픽셀/파일 IO는 소유하지 않습니다.</summary>
internal sealed class ThumbnailWorkTracker
{
    internal readonly record struct Ticket(string FrameId, long Revision, ThumbnailCacheIdentity? Identity);
    private readonly Lock gate = new();
    private readonly Dictionary<string, Ticket> current = new(StringComparer.Ordinal);
    private readonly Dictionary<(string Id, string Lane), (Ticket Ticket, string Key, Task Task)> jobs = [];
    private readonly HashSet<Task> active = [];
    private long revision;
    private bool stopped;

    internal Ticket Observe(string id, ThumbnailCacheIdentity? identity = null, bool replace = false, bool updateIdentity = false)
    {
        lock (gate)
        {
            if (!replace && current.TryGetValue(id, out var prior) && (!updateIdentity && identity is null || prior.Identity == identity)) { return prior; }
            if (!updateIdentity) { identity ??= current.GetValueOrDefault(id).Identity; }
            var ticket = new Ticket(id, ++revision, identity);
            current[id] = ticket;
            return ticket;
        }
    }
    internal bool Knows(string id) { lock (gate) { return current.ContainsKey(id); } }
    internal bool Matches(Ticket ticket)
    { lock (gate) { return !stopped && current.TryGetValue(ticket.FrameId, out var latest) && latest == ticket; } }
    internal bool Publish(Ticket ticket, Action publish)
    {
        lock (gate)
        {
            if (!Matches(ticket)) { return false; }
            publish();
            return true;
        }
    }
    internal void Invalidate(string id, Action clear)
    {
        lock (gate) { current.Remove(id); clear(); }
    }
    internal Task Run(Ticket ticket, string lane, string key, Func<Task> action)
    {
        TaskCompletionSource completed;
        var slot = (ticket.FrameId, lane);
        lock (gate)
        {
            if (!Matches(ticket)) { return Task.CompletedTask; }
            if (jobs.TryGetValue(slot, out var old) && old.Ticket == ticket && old.Key == key) { return old.Task; }
            completed = new(TaskCreationOptions.RunContinuationsAsynchronously);
            jobs[slot] = (ticket, key, completed.Task);
            active.Add(completed.Task);
        }
        _ = Task.Run(async () =>
        {
            Exception? failure = null;
            try { await action().ConfigureAwait(false); }
            catch (Exception error) { failure = error; }
            finally
            {
                lock (gate)
                {
                    if (jobs.TryGetValue(slot, out var job) && ReferenceEquals(job.Task, completed.Task)) { jobs.Remove(slot); }
                    active.Remove(completed.Task);
                }
            }
            if (failure is OperationCanceledException) { completed.TrySetCanceled(); }
            else if (failure is not null) { completed.TrySetException(failure); }
            else { completed.TrySetResult(); }
        });
        // Request/Publish는 fire-and-forget이지만 예외는 관찰합니다. await 호출자는 그대로 받습니다.
        _ = completed.Task.ContinueWith(task => _ = task.Exception, TaskContinuationOptions.OnlyOnFaulted);
        return completed.Task;
    }
    internal async Task DrainAsync(bool stop = false)
    {
        while (true)
        {
            Task[] pending;
            lock (gate) { stopped |= stop; pending = [.. active]; }
            if (pending.Length == 0) { return; }
            try { await Task.WhenAll(pending).ConfigureAwait(false); }
            catch (Exception) { /* 호출자의 오류/취소와 별개로 자원 반환을 기다립니다. */ }
        }
    }
}
