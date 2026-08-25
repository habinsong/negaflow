using System.Diagnostics;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

internal sealed record LibraryInfraredCleanWork(
    string FrameId,
    Guid FrameGuid,
    DefectSourceIdentity SourceIdentity,
    string VisiblePath,
    string InfraredPath,
    FrameSourceKind SourceKind,
    ulong RecipeRevision,
    DefectSourceObservation? SourceObservation = null);

/// <summary>
/// 선택 debounce와 frame별 IR native run 수명을 소유합니다. catalog 준비·적용은 UI dispatcher에서,
/// 블로킹 native 검출만 worker에서 실행합니다.
/// </summary>
internal sealed class LibraryInfraredCleanCoordinator : IDisposable
{
    private sealed record ActiveRun(long Revision, DevelopRun Run);

    /// <summary>`NEGA_TIMING=1` 일 때만 선택→적용 사이의 각 구간을 실측합니다.</summary>
    private sealed class ScheduleTiming
    {
        internal long Start = Stopwatch.GetTimestamp();
        internal double Debounce;
        internal double Dispatch;
        internal double Prepare;
        internal double Detect;

        internal double Split()
        {
            long now = Stopwatch.GetTimestamp();
            double elapsed = (now - Start) * 1000.0 / Stopwatch.Frequency;
            Start = now;
            return elapsed;
        }
    }

    private readonly object sync = new();
    private readonly IUiDispatcher dispatcher;
    private readonly Func<string?> activeFrameId;
    private readonly Func<string, LibraryInfraredCleanWork?> prepare;
    private readonly Func<LibraryInfraredCleanWork, DevelopRun, InfraredDefectDetectionOutcome> detect;
    private readonly Action<LibraryInfraredCleanWork, InfraredDefectDetectionOutcome> complete;
    private readonly Action<string> rearm;
    private readonly Func<CancellationToken, Task> selectionDelay;
    private readonly CancellationTokenSource lifetime = new();
    private readonly Dictionary<string, ActiveRun> activeRuns = new(StringComparer.Ordinal);
    private long nextRevision;
    private long lifecycleGeneration;
    private bool disposed;

    internal LibraryInfraredCleanCoordinator(
        IUiDispatcher dispatcher,
        Func<string?> activeFrameId,
        Func<string, LibraryInfraredCleanWork?> prepare,
        Func<LibraryInfraredCleanWork, DevelopRun, InfraredDefectDetectionOutcome> detect,
        Action<LibraryInfraredCleanWork, InfraredDefectDetectionOutcome> complete,
        Action<string> rearm,
        Func<CancellationToken, Task>? selectionDelay = null)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(activeFrameId);
        ArgumentNullException.ThrowIfNull(prepare);
        ArgumentNullException.ThrowIfNull(detect);
        ArgumentNullException.ThrowIfNull(complete);
        ArgumentNullException.ThrowIfNull(rearm);
        this.dispatcher = dispatcher;
        this.activeFrameId = activeFrameId;
        this.prepare = prepare;
        this.detect = detect;
        this.complete = complete;
        this.rearm = rearm;
        this.selectionDelay = selectionDelay ?? (token => Task.Delay(
            InfraredCleanPolicy.SelectionDebounceMilliseconds,
            token));
    }

    internal void Schedule(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        long generation;
        lock (sync)
        {
            if (disposed)
            {
                return;
            }
            generation = lifecycleGeneration;
        }
        _ = DelayAndStartAsync(
            frameId,
            generation,
            InfraredPerformanceTrace.Enabled ? new ScheduleTiming() : null,
            lifetime.Token);
    }

    internal bool YieldToManualTool(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ActiveRun? active;
        lock (sync)
        {
            if (!activeRuns.Remove(frameId, out active))
            {
                return false;
            }
        }
        active.Run.Cancel();
        rearm(frameId);
        return true;
    }

    internal void Reset()
    {
        ActiveRun[] running;
        lock (sync)
        {
            lifecycleGeneration++;
            running = [.. activeRuns.Values];
            activeRuns.Clear();
        }
        foreach (ActiveRun active in running)
        {
            active.Run.Cancel();
        }
    }

    private async Task DelayAndStartAsync(
        string frameId,
        long generation,
        ScheduleTiming? timing,
        CancellationToken cancellationToken)
    {
        try
        {
            await selectionDelay(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return;
        }
        if (cancellationToken.IsCancellationRequested)
        {
            return;
        }
        if (timing is not null)
        {
            timing.Debounce = timing.Split();
        }
        _ = dispatcher.TryEnqueue(() => StartIfCurrent(frameId, generation, timing));
    }

    private void StartIfCurrent(string frameId, long generation, ScheduleTiming? timing)
    {
        if (timing is not null)
        {
            timing.Dispatch = timing.Split();
        }
        lock (sync)
        {
            if (disposed || lifecycleGeneration != generation)
            {
                return;
            }
        }
        if (!string.Equals(activeFrameId(), frameId, StringComparison.Ordinal) ||
            prepare(frameId) is not { } work)
        {
            return;
        }
        if (timing is not null)
        {
            timing.Prepare = timing.Split();
        }

        var run = new DevelopRun();
        long revision;
        ActiveRun? prior = null;
        lock (sync)
        {
            if (disposed || lifecycleGeneration != generation)
            {
                run.Dispose();
                return;
            }
            revision = ++nextRevision;
            if (activeRuns.Remove(frameId, out ActiveRun? existing))
            {
                prior = existing;
            }
            activeRuns[frameId] = new ActiveRun(revision, run);
        }
        prior?.Run.Cancel();
        _ = RunAsync(work, revision, run, timing);
    }

    private async Task RunAsync(
        LibraryInfraredCleanWork work,
        long revision,
        DevelopRun run,
        ScheduleTiming? timing)
    {
        InfraredDefectDetectionOutcome outcome;
        try
        {
            outcome = await Task.Run(() => detect(work, run)).ConfigureAwait(false);
        }
        catch
        {
            outcome = new InfraredDefectDetectionOutcome(null, true);
        }

        if (timing is not null)
        {
            timing.Detect = timing.Split();
        }
        if (!dispatcher.TryEnqueue(() => Finish(work, revision, run, outcome, timing)))
        {
            RemoveIfCurrent(work.FrameId, revision);
            run.Dispose();
        }
    }

    private void Finish(
        LibraryInfraredCleanWork work,
        long revision,
        DevelopRun run,
        InfraredDefectDetectionOutcome outcome,
        ScheduleTiming? timing)
    {
        if (timing is not null)
        {
            InfraredPerformanceTrace.Write(
                $"schedule debounce={timing.Debounce:F1} dispatch={timing.Dispatch:F1} " +
                $"prepare={timing.Prepare:F1} detect={timing.Detect:F1} " +
                $"publish={timing.Split():F1}");
        }
        bool current = RemoveIfCurrent(work.FrameId, revision);
        run.Dispose();
        if (current)
        {
            complete(work, outcome);
        }
    }

    private bool RemoveIfCurrent(string frameId, long revision)
    {
        lock (sync)
        {
            if (!activeRuns.TryGetValue(frameId, out ActiveRun? active) ||
                active.Revision != revision)
            {
                return false;
            }
            activeRuns.Remove(frameId);
            return true;
        }
    }

    public void Dispose()
    {
        lock (sync)
        {
            if (disposed)
            {
                return;
            }
            disposed = true;
        }
        lifetime.Cancel();
        Reset();
        lifetime.Dispose();
    }
}
