using System.Diagnostics;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public enum InfraredDefectApplyStatus
{
    Applied,
    NoDefects,
    CoverageTooHigh,
    Cancelled,
    UnsupportedFilm,
    InvalidFrame,
    AlreadyApplied,
    SourceMismatch,
    DetectionFailed,
    PersistenceFailed,
}

public sealed record InfraredDefectApplyResult(
    InfraredDefectApplyStatus Status,
    InfraredDetectionResult? Detection,
    DefectRecipeSnapshot? Recipe,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => Status == InfraredDefectApplyStatus.Applied;
}

internal sealed record InfraredDefectDetectionOutcome(
    InfraredDetectionResult? Detection,
    bool IsFaulted);

public static class InfraredDefectRecipeCoordinator
{
    public static InfraredDefectApplyResult Run(
        LibraryDocument document,
        LibraryFrameSnapshot frame,
        DefectSourceIdentity sourceIdentity,
        ReadOnlySpan<float> infrared,
        ReadOnlySpan<float> red,
        uint width,
        uint height,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentNullException.ThrowIfNull(frame);

        if (frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.ColorPositive))
        {
            return Result(InfraredDefectApplyStatus.UnsupportedFilm);
        }
        if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) || frameId == Guid.Empty)
        {
            return Result(InfraredDefectApplyStatus.InvalidFrame);
        }
        if (frame.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true)
        {
            return Result(InfraredDefectApplyStatus.AlreadyApplied);
        }
        if (frame.DefectRecipe?.SourceIdentity is { } currentIdentity &&
            currentIdentity != sourceIdentity)
        {
            return Result(InfraredDefectApplyStatus.SourceMismatch);
        }

        InfraredDetectionResult detection;
        try
        {
            detection = NativeInfraredDefectDetector.Detect(
                infrared, red, width, height, parameters, run);
        }
        catch (Exception error) when (error is
            ArgumentException or OverflowException or NativeBootstrapException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            return Result(InfraredDefectApplyStatus.DetectionFailed);
        }
        return ApplyDetection(document, frame, frameId, sourceIdentity, detection);
    }

    public static InfraredDefectApplyResult RunFiles(
        LibraryDocument document,
        LibraryFrameSnapshot frame,
        DefectSourceIdentity sourceIdentity,
        string visiblePath,
        string infraredPath,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentNullException.ThrowIfNull(frame);
        if (frame.Route.FilmType is not (FilmType.ColorNegative or FilmType.ColorPositive))
        {
            return Result(InfraredDefectApplyStatus.UnsupportedFilm);
        }
        if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) || frameId == Guid.Empty)
        {
            return Result(InfraredDefectApplyStatus.InvalidFrame);
        }
        if (frame.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true)
        {
            return Result(InfraredDefectApplyStatus.AlreadyApplied);
        }
        if (frame.DefectRecipe?.SourceIdentity is { } currentIdentity &&
            currentIdentity != sourceIdentity)
        {
            return Result(InfraredDefectApplyStatus.SourceMismatch);
        }
        InfraredDefectDetectionOutcome outcome = DetectFiles(
            visiblePath,
            infraredPath,
            frame.SourceKind,
            parameters,
            run);
        return outcome.Detection is { } detection && !outcome.IsFaulted
            ? ApplyDetection(document, frame, frameId, sourceIdentity, detection)
            : Result(InfraredDefectApplyStatus.DetectionFailed);
    }

    internal static InfraredDefectDetectionOutcome DetectFiles(
        string visiblePath,
        string infraredPath,
        FrameSourceKind sourceKind = FrameSourceKind.ImportedFile,
        InfraredDetectorParameters? parameters = null,
        DevelopRun? run = null)
    {
        bool trace = InfraredPerformanceTrace.Enabled;
        Stopwatch? timing = trace ? Stopwatch.StartNew() : null;
        try
        {
            InfraredVisibleSourceKind kind = sourceKind == FrameSourceKind.ScannerTiff
                ? InfraredVisibleSourceKind.ScannerTiff
                : InfraredVisibleSourceKind.ImportedFile;
            InfraredDetectionResult detection = OnMultiThreadedApartment(
                () => DetectWithRetry(visiblePath, infraredPath, kind, parameters, run));
            if (trace)
            {
                InfraredPerformanceTrace.Write(
                    $"detect-files total={timing!.Elapsed.TotalMilliseconds:F3} ms");
            }
            return new(detection, false);
        }
        catch (Exception error) when (error is
            ArgumentException or OverflowException or NativeBootstrapException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            // **삼키되 남깁니다.** 앞 판은 여기서 조용히 `DetectionFailed` 로만 돌아갔고,
            // 같은 파일이 밖에서는 멀쩡히 검출되는데 앱 안에서만 실패하는 이유를 알 길이
            // 없었습니다.
            ScannerDiagnosticsLog.Write(
                $"ir detect threw: {error.GetType().Name} {error.Message} " +
                $"visible={visiblePath} infrared={infraredPath} kind={sourceKind}");
            return new(null, true);
        }
    }

    /// <summary>
    /// 검출을 <b>MTA 스레드에서</b> 돌립니다.
    /// </summary>
    /// <remarks>
    /// **WIC 는 STA 스레드에서 이 길을 쓰지 못합니다.**
    ///
    /// 네이티브 디코더는 먼저 <c>CoInitializeEx(COINIT_MULTITHREADED)</c> 를 겁니다. 그
    /// 스레드가 이미 STA 면 COM 이 <c>RPC_E_CHANGED_MODE</c> 를 돌려주고, 디코더는
    /// <c>com_apartment_mismatch</c> 로 물러납니다 - 파일이 멀쩡해도 한 줄도 못 읽습니다.
    /// WinUI 의 UI 스레드가 바로 그 STA 입니다.
    ///
    /// 실기 기록이 그것을 그대로 보여 주었습니다: 배치의 <b>첫 장만</b> 늘 실패했고
    /// (<c>detail=visible-full-decode-failed(밑=4)</c>), 같은 파일을 콘솔에서 읽으면 언제나
    /// <c>Ok</c> 였습니다. 첫 장은 아직 UI 스레드에서 이어지고, 둘째 장부터는 스캔을 기다리며
    /// 한 번 끊긴 뒤라 워커에서 이어지기 때문입니다.
    ///
    /// 47MB TIFF 두 장을 펴는 일은 어차피 UI 스레드에서 할 일이 아닙니다.
    /// </remarks>
    private static InfraredDetectionResult OnMultiThreadedApartment(
        Func<InfraredDetectionResult> work)
    {
        if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
        {
            return work();
        }
        ScannerDiagnosticsLog.Write(
            "ir detect moved off the STA thread - WIC refuses COINIT_MULTITHREADED there");
        return Task.Run(work).GetAwaiter().GetResult();
    }

    /// <summary>
    /// 아직 <b>쓰이는 중</b>인 파일이면 다시 읽습니다. 기다리는 시간을 정해 두지 않습니다.
    /// </summary>
    /// <remarks>
    /// **관측으로 멈춥니다, 시계로 멈추지 않습니다.**
    ///
    /// 앞 판은 실제로 성공했던 한 사례의 간격(2.3초)을 보고 물러나는 시간을 상수로 박았습니다.
    /// 기계마다 디스크도 백신도 다르므로 그 수는 이 기계 밖에서는 아무 뜻이 없습니다. 여기서는
    /// <b>두 파일의 크기와 마지막 쓰기 시각</b>을 보고, 지난번과 달라졌을 때만 - 즉 누군가
    /// 아직 쓰고 있을 때만 - 다시 읽습니다. 아무 것도 안 변했으면 기다릴 이유가 없으므로
    /// 곧바로 그만둡니다. 검출 자체가 수백 ms 걸리므로 그것이 관측 간격이 됩니다.
    ///
    /// 다시 읽는 것은 <b>바이트를 못 읽은 갈래</b>뿐입니다. 결함이 없다거나 정렬이 안 맞는
    /// 것은 파일이 그대로면 답도 그대로입니다.
    /// </remarks>
    private static InfraredDetectionResult DetectWithRetry(
        string visiblePath,
        string infraredPath,
        InfraredVisibleSourceKind kind,
        InfraredDetectorParameters? parameters,
        DevelopRun? run)
    {
        (long, long, long, long) stamp = FileStamp(visiblePath, infraredPath);
        InfraredDetectionResult detection = NativeInfraredDefectDetector.DetectFiles(
            visiblePath, infraredPath, kind, parameters, run);
        while (detection.Status == InfraredDetectionStatus.Unreadable)
        {
            (long, long, long, long) latest = FileStamp(visiblePath, infraredPath);
            if (latest == stamp)
            {
                // 파일이 그대로입니다. 다시 읽어도 같은 답이므로 여기서 멈춥니다.
                return detection;
            }
            ScannerDiagnosticsLog.Write(
                $"ir detect retrying - source still settling detail={detection.FailureDetail} " +
                $"visible={visiblePath} infrared={infraredPath}");
            stamp = latest;
            detection = NativeInfraredDefectDetector.DetectFiles(
                visiblePath, infraredPath, kind, parameters, run);
        }
        return detection;
    }

    /// <summary>두 파일의 크기와 마지막 쓰기 시각입니다. 못 읽으면 -1 로 둡니다.</summary>
    private static (long, long, long, long) FileStamp(string visiblePath, string infraredPath)
    {
        (long length, long written) Look(string path)
        {
            try
            {
                FileInfo info = new(path);
                return info.Exists ? (info.Length, info.LastWriteTimeUtc.Ticks) : (-1L, -1L);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                return (-1L, -1L);
            }
        }
        (long visibleLength, long visibleWritten) = Look(visiblePath);
        (long infraredLength, long infraredWritten) = Look(infraredPath);
        return (visibleLength, visibleWritten, infraredLength, infraredWritten);
    }

    internal static InfraredDefectApplyResult ApplyDetection(
        LibraryDocument document,
        LibraryFrameSnapshot frame,
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        InfraredDetectionResult detection)
    {

        InfraredDefectApplyStatus detectionStatus = detection.Status switch
        {
            InfraredDetectionStatus.Ok => InfraredDefectApplyStatus.Applied,
            InfraredDetectionStatus.NoDefects => InfraredDefectApplyStatus.NoDefects,
            InfraredDetectionStatus.CoverageTooHigh =>
                InfraredDefectApplyStatus.CoverageTooHigh,
            InfraredDetectionStatus.Cancelled => InfraredDefectApplyStatus.Cancelled,
            _ => InfraredDefectApplyStatus.DetectionFailed,
        };
        if (detectionStatus != InfraredDefectApplyStatus.Applied)
        {
            ScannerDiagnosticsLog.Write(
                $"ir detect not applied: native={detection.Status} " +
                $"detail={InfraredFailureDetail.Describe(detection.FailureDetail)} " +
                $"mapped={detectionStatus} " +
                $"components={detection.Components.Count} clusters={detection.Clusters.Count} " +
                $"alignment={detection.AlignmentStatus} coverage={detection.Coverage:F6} " +
                $"size={detection.Width}x{detection.Height} frame={frame.Id} " +
                $"visible={frame.SourcePath} infrared={frame.InfraredPath}");
            return Result(detectionStatus, detection);
        }

        bool trace = InfraredPerformanceTrace.Enabled;
        Stopwatch? timing = trace ? Stopwatch.StartNew() : null;
        DefectRecipeSnapshot recipe;
        try
        {
            recipe = CreateRecipe(
                frameId,
                sourceIdentity,
                frame.DefectRecipe,
                checked(frame.DefectRecipeRevision + 1UL),
                detection);
        }
        catch (ArgumentException error)
        {
            // 레시피로 옮기지 못한 이유는 여기서만 알 수 있습니다 - 밖에서는 그냥
            // `DetectionFailed` 로 보입니다.
            ScannerDiagnosticsLog.Write(
                $"ir recipe refused: {error.Message} native={detection.Status} " +
                $"components={detection.Components.Count} clusters={detection.Clusters.Count} " +
                $"revision={frame.DefectRecipeRevision} " +
                $"existingItems={frame.DefectRecipe?.Items.Count.ToString() ?? "none"}");
            return Result(InfraredDefectApplyStatus.DetectionFailed, detection);
        }
        catch (OverflowException)
        {
            return Result(InfraredDefectApplyStatus.PersistenceFailed, detection);
        }
        double recipeMilliseconds = timing?.Elapsed.TotalMilliseconds ?? 0.0;

        Stopwatch? captureTiming = trace ? Stopwatch.StartNew() : null;
        LibraryUndoSnapshot pendingUndo = document.CapturePendingDefectUndo(
            frame.Id,
            LibraryDefectHistoryMode.PreservingInfrared);
        captureTiming?.Stop();
        Stopwatch? writeTiming = trace ? Stopwatch.StartNew() : null;
        LibraryDefectRecipeWriteResult written = document.WriteDefectRecipe(frame.Id, recipe);
        writeTiming?.Stop();
        if (!written.IsSuccess)
        {
            return new InfraredDefectApplyResult(
                InfraredDefectApplyStatus.PersistenceFailed,
                detection,
                null,
                written.SidecarError,
                written.CatalogError);
        }
        Stopwatch? commitTiming = trace ? Stopwatch.StartNew() : null;
        document.CommitPendingUndo(pendingUndo);
        commitTiming?.Stop();
        if (trace)
        {
            InfraredPerformanceTrace.Write(
                $"apply recipe={recipeMilliseconds:F3} capture={captureTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"write={writeTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"commit={commitTiming!.Elapsed.TotalMilliseconds:F3} " +
                $"total={timing!.Elapsed.TotalMilliseconds:F3} ms");
        }
        return Result(InfraredDefectApplyStatus.Applied, detection, written.Recipe);
    }

    internal static DefectRecipeSnapshot CreateRecipe(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        ulong recipeRevision,
        InfraredDetectionResult detection)
    {
        ArgumentNullException.ThrowIfNull(detection);
        if (detection.Status != InfraredDetectionStatus.Ok ||
            detection.Width == 0 || detection.Height == 0 ||
            detection.Clusters.Count == 0 || detection.Components.Count == 0 ||
            detection.Components.Count > int.MaxValue ||
            recipeRevision == 0 ||
            existing is not null && recipeRevision <= existing.RecipeRevision ||
            existing?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true ||
            existing?.SourceIdentity is { } currentIdentity && currentIdentity != sourceIdentity)
        {
            throw new ArgumentException("The infrared detection cannot become a recipe item.");
        }

        DefectCluster[] clusters = detection.Clusters.Select(cluster => new DefectCluster(
            new DefectRect(cluster.RoiX, cluster.RoiYUp, cluster.Width, cluster.Height),
            new DefectMask(false, cluster.CoreMaskRgba8),
            checked((int)cluster.Width),
            checked((int)cluster.Height),
            new DefectMask(false, cluster.AttenuationR16))).ToArray();

        DefectPreviewComponent[] preview = detection.Components.Select(component =>
            new DefectPreviewComponent(
                MapClassification(component.Classification),
                component.Confidence,
                component.PreviewPoints.Select(point => new DefectPoint(
                    point.X / (double)detection.Width,
                    point.Y / (double)detection.Height)).ToArray())).ToArray();

        DefectClassCount[] counts = detection.Components
            .GroupBy(component => MapClassification(component.Classification))
            .OrderBy(group => group.Key)
            .Select(group => new DefectClassCount(group.Key, group.Count()))
            .ToArray();
        double meanConfidence = detection.Components.Average(component => component.Confidence);
        DefectEditItem item = new(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, detection.Components.Count),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(counts, meanConfidence)),
            new DefectSize(detection.Width, detection.Height),
            preview)
        {
            Clusters = clusters,
        };

        DefectEditItem[] items = existing is null
            ? [item]
            : [.. existing.Items, item];
        return DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision,
            sourceIdentity,
            items);
    }

    private static DefectClassification MapClassification(
        InfraredDefectClass classification) => classification switch
        {
            InfraredDefectClass.Dust => DefectClassification.Dust,
            InfraredDefectClass.ScratchHorizontal => DefectClassification.ScratchHorizontal,
            InfraredDefectClass.ScratchVertical => DefectClassification.ScratchVertical,
            InfraredDefectClass.ScratchDiagonal => DefectClassification.ScratchDiagonal,
            _ => throw new ArgumentOutOfRangeException(nameof(classification)),
        };

    private static InfraredDefectApplyResult Result(
        InfraredDefectApplyStatus status,
        InfraredDetectionResult? detection = null,
        DefectRecipeSnapshot? recipe = null) =>
        new(status, detection, recipe, DefectSidecarError.None, CatalogStoreError.None);
}
