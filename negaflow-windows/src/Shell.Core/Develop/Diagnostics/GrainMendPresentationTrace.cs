using System.Diagnostics;

namespace Negaflow.Shell.Develop;

public enum GrainMendPresentationTool
{
    Auto,
    Guided,
    Brush,
    Clone,
    Infrared,
}

public readonly record struct GrainMendPresentationSample(
    long Id,
    GrainMendPresentationTool Tool,
    string FrameId,
    long StartedTimestamp)
{
    public bool IsEnabled => Id > 0;
}

/// <summary>
/// GrainMend 입력과 WinUI composition 사이를 같은 단조 시계로 잇는 opt-in 표본입니다.
/// </summary>
/// <remarks>
/// 일반 실행에서는 <see cref="PreviewTrace"/>가 꺼져 있어 표본도 만들지 않습니다. 완료 시각을
/// 먼저 잡고 로그를 한 번만 쓰므로 파일 I/O는 측정값에 들어가지 않습니다.
/// </remarks>
public static class GrainMendPresentationTrace
{
    private static readonly object InfraredGate = new();
    private static readonly Dictionary<string, GrainMendPresentationSample> InfraredSamples =
        new(StringComparer.Ordinal);
    private static long nextId;

    public static GrainMendPresentationSample Begin(
        GrainMendPresentationTool tool,
        string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (!PreviewTrace.IsEnabled)
        {
            return default;
        }

        long id = Interlocked.Increment(ref nextId);
        return new GrainMendPresentationSample(
            id,
            tool,
            frameId,
            Stopwatch.GetTimestamp());
    }

    public static void BeginInfrared(string frameId)
    {
        GrainMendPresentationSample sample = Begin(
            GrainMendPresentationTool.Infrared,
            frameId);
        if (!sample.IsEnabled)
        {
            return;
        }

        lock (InfraredGate)
        {
            InfraredSamples[frameId] = sample;
        }
    }

    public static bool TryTakeInfrared(
        string frameId,
        out GrainMendPresentationSample sample)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        lock (InfraredGate)
        {
            if (InfraredSamples.Remove(frameId, out sample))
            {
                return true;
            }
        }

        sample = default;
        return false;
    }

    public static void CancelInfrared(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        lock (InfraredGate)
        {
            InfraredSamples.Remove(frameId);
        }
    }

    public static void Complete(
        GrainMendPresentationSample sample,
        string target,
        long submittedTimestamp,
        long completedTimestamp,
        int width,
        int height)
    {
        if (!sample.IsEnabled || submittedTimestamp < sample.StartedTimestamp ||
            completedTimestamp < submittedTimestamp)
        {
            return;
        }

        double inputToSubmit = Stopwatch.GetElapsedTime(
            sample.StartedTimestamp,
            submittedTimestamp).TotalMilliseconds;
        double submitToComposition = Stopwatch.GetElapsedTime(
            submittedTimestamp,
            completedTimestamp).TotalMilliseconds;
        double inputToComposition = Stopwatch.GetElapsedTime(
            sample.StartedTimestamp,
            completedTimestamp).TotalMilliseconds;
        PreviewTrace.Write(FormattableString.Invariant(
            $"grainmend.presentation id={sample.Id} tool={sample.Tool.ToString().ToLowerInvariant()} frame={sample.FrameId} target={target} input_to_submit_ms={inputToSubmit:F3} submit_to_composition_ms={submitToComposition:F3} input_to_composition_ms={inputToComposition:F3} w={width} h={height}"));
    }
}
