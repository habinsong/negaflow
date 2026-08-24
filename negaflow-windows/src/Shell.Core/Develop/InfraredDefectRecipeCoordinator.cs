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
            InfraredDetectionResult detection = NativeInfraredDefectDetector.DetectFiles(
                    visiblePath,
                    infraredPath,
                    sourceKind == FrameSourceKind.ScannerTiff
                        ? InfraredVisibleSourceKind.ScannerTiff
                        : InfraredVisibleSourceKind.ImportedFile,
                    parameters,
                    run);
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
            return new(null, true);
        }
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
        catch (ArgumentException)
        {
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
