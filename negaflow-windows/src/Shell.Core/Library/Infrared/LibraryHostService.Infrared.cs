using System.Diagnostics;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

public sealed partial class LibraryHostService
{
    private readonly HashSet<string> infraredCleanAttempted = new(StringComparer.Ordinal);

    public event Action<string, InfraredCleanStatus>? InfraredCleanStatusChanged;

    public void ScheduleInfraredCleanForSelection(string? frameId)
    {
        if (frameId is null || document is null)
        {
            return;
        }
        LibraryFrameSnapshot? frame = Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        if (InfraredCleanPolicy.ShouldRun(
                frame,
                infraredCleanAttempted.Contains(frameId)))
        {
            GrainMendPresentationTrace.BeginInfrared(frameId);
            infraredClean.Schedule(frameId);
        }
    }

    public bool YieldInfraredCleanToManualTool(string frameId)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        return infraredClean.YieldToManualTool(frameId);
    }

    private void OnImportedInfraredAttached(string frameId)
    {
        RearmInfraredClean(frameId);
        FrameEdited?.Invoke(this, EventArgs.Empty);
        if (string.Equals(ActiveFrameId, frameId, StringComparison.Ordinal))
        {
            ScheduleInfraredCleanForSelection(frameId);
        }
    }

    private void OnStrayInfraredFramesRemoved(StrayInfraredFrameRepairPlan repair)
    {
        HashSet<string> removed = repair.RemovedFrameIds.ToHashSet(StringComparer.Ordinal);
        string? active = ActiveFrameId;
        bool activeWasRemoved = active is not null && removed.Contains(active);
        List<string> selected = [.. SelectedFrameIds.Where(id => !removed.Contains(id))];
        if (activeWasRemoved && active is not null &&
            repair.ReplacementFrameIdByRemovedFrameId.TryGetValue(active, out string? replacement) &&
            Frames.Any(frame => string.Equals(frame.Id, replacement, StringComparison.Ordinal)))
        {
            if (!selected.Contains(replacement, StringComparer.Ordinal))
            {
                selected.Add(replacement);
            }
            active = replacement;
        }
        selection.Set(Frames, selected, active);
        if (activeWasRemoved)
        {
            ScheduleInfraredCleanForSelection(ActiveFrameId);
        }
        FrameEdited?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// 스캐너 게시가 IR 굽기를 시작했습니다. <b>알림은 UI 스레드로 넘깁니다.</b>
    /// </summary>
    /// <remarks>
    /// 배치 스캔은 워커 스레드에서 돕니다. 여기서 곧바로 알림을 올리면 구독자가 그 스레드
    /// 에서 XAML 을 건드리고, WinUI 가 던진 <c>COMException</c> 이
    /// <c>ScannerFramePublisher.Publish</c> 밖으로 그대로 올라가 <b>롤을 통째로 끊습니다</b> —
    /// 실기 기록: <c>batch publish threw at index=1: COMException</c>, 그 사진은 IR 까지
    /// 적용된 뒤였습니다(`defects=1`).
    /// </remarks>
    private void BeginScannerInfraredClean(string frameId)
    {
        infraredCleanAttempted.Add(frameId);
        OnUiThread(() => PublishInfraredCleanStatus(frameId, InfraredCleanStatus.Detecting));
    }

    private void CompleteScannerInfraredClean(
        string frameId,
        InfraredDefectApplyResult result)
    {
        if (InfraredCleanPolicy.ShouldRearm(result.Status))
        {
            RearmInfraredClean(frameId);
        }
        InfraredCleanStatus status = InfraredCleanStatus.From(result);
        bool edited = result.IsSuccess;
        OnUiThread(() =>
        {
            PublishInfraredCleanStatus(frameId, status);
            if (edited)
            {
                FrameEdited?.Invoke(this, EventArgs.Empty);
            }
        });
    }

    /// <summary>
    /// UI 스레드에서 돌립니다. 큐가 닫혔으면(창이 닫히는 중) 그냥 넘어갑니다 - 그때는
    /// 알릴 화면도 없습니다.
    /// </summary>
    private void OnUiThread(Action work)
    {
        if (dispatcher.HasThreadAccess)
        {
            work();
            return;
        }
        _ = dispatcher.TryEnqueue(work);
    }

    private LibraryInfraredCleanWork? PrepareScheduledInfraredClean(string frameId)
    {
        if (document is null)
        {
            return null;
        }
        LibraryFrameSnapshot? frame = Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        if (!InfraredCleanPolicy.ShouldRun(
                frame,
                infraredCleanAttempted.Contains(frameId)) ||
            frame is null)
        {
            return null;
        }

        infraredCleanAttempted.Add(frameId);
        if (!Guid.TryParseExact(frameId, "D", out Guid frameGuid) || frameGuid == Guid.Empty ||
            !DefectSourceIdentityReader.TryRead(
                frame.SourcePath,
                out DefectSourceIdentity identity,
                out DefectSourceObservation observation) ||
            frame.InfraredPath is not { } infraredPath)
        {
            PublishInfraredCleanStatus(
                frameId,
                InfraredCleanStatus.From(FailedInfraredClean()));
            return null;
        }

        PublishInfraredCleanStatus(frameId, InfraredCleanStatus.Detecting);
        return new LibraryInfraredCleanWork(
            frameId,
            frameGuid,
            identity,
            frame.SourcePath,
            infraredPath,
            frame.SourceKind,
            frame.DefectRecipeRevision,
            observation);
    }

    private void CompleteScheduledInfraredClean(
        LibraryInfraredCleanWork work,
        InfraredDefectDetectionOutcome outcome)
    {
        bool trace = InfraredPerformanceTrace.Enabled;
        Stopwatch? timing = trace ? Stopwatch.StartNew() : null;
        if (document is not { } open ||
            Frames.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, work.FrameId, StringComparison.Ordinal)) is not { } frame ||
            frame.DefectRecipeRevision != work.RecipeRevision ||
            frame.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true ||
            !string.Equals(frame.SourcePath, work.VisiblePath, StringComparison.Ordinal))
        {
            RearmInfraredClean(work.FrameId);
            return;
        }
        double guardMilliseconds = timing?.Elapsed.TotalMilliseconds ?? 0.0;
        Stopwatch? identityTiming = trace ? Stopwatch.StartNew() : null;
        if (work.SourceObservation is not { } expectedObservation ||
            !DefectSourceIdentityReader.TryObserve(
                frame.SourcePath,
                out DefectSourceObservation currentObservation) ||
            currentObservation != expectedObservation)
        {
            RearmInfraredClean(work.FrameId);
            return;
        }
        identityTiming?.Stop();

        Stopwatch? applyTiming = trace ? Stopwatch.StartNew() : null;
        InfraredDefectApplyResult result = outcome is { IsFaulted: false, Detection: { } detection }
            ? InfraredDefectRecipeCoordinator.ApplyDetection(
                open,
                frame,
                work.FrameGuid,
                work.SourceIdentity,
                detection)
            : FailedInfraredClean();
        applyTiming?.Stop();
        if (InfraredCleanPolicy.ShouldRearm(result.Status))
        {
            RearmInfraredClean(work.FrameId);
        }
        Stopwatch? publishTiming = trace ? Stopwatch.StartNew() : null;
        PublishInfraredCleanStatus(work.FrameId, InfraredCleanStatus.From(result));
        if (result.IsSuccess)
        {
            FrameEdited?.Invoke(this, EventArgs.Empty);
        }
        publishTiming?.Stop();
        if (trace)
        {
            InfraredPerformanceTrace.Write(
                $"host guard={guardMilliseconds:F3} identity={identityTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"apply={applyTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"publish={publishTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"total={timing!.Elapsed.TotalMilliseconds:F3} ms");
        }
    }

    private void RearmInfraredClean(string frameId)
    {
        LibraryFrameSnapshot? frame = Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        if (frame?.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) != true)
        {
            infraredCleanAttempted.Remove(frameId);
        }
    }

    private void PublishInfraredCleanStatus(string frameId, InfraredCleanStatus status) =>
        InfraredCleanStatusChanged?.Invoke(frameId, status);

    private static InfraredDefectApplyResult FailedInfraredClean() => new(
        InfraredDefectApplyStatus.DetectionFailed,
        null,
        null,
        DefectSidecarError.None,
        CatalogStoreError.None);
}
