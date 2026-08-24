using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

internal sealed class FakeDispatcher(bool accepts) : IUiDispatcher
{
    private readonly int ownerThreadId = Environment.CurrentManagedThreadId;

    public bool Accepts { get; set; } = accepts;

    public int EnqueueCount { get; private set; }

    public bool HasThreadAccess => Environment.CurrentManagedThreadId == ownerThreadId;

    public bool TryEnqueue(Action callback)
    {
        ++EnqueueCount;
        if (!Accepts)
        {
            return false;
        }
        callback();
        return true;
    }
}

internal sealed class FakeExporter : IDevelopExporter, IDefectBakeExporter
{
    private readonly Func<DevelopExportRequest, DevelopExportResult> behaviour;
    private readonly Func<DevelopExportRequest, DevelopExportResult> bakeBehaviour;
    private readonly ManualResetEventSlim? gate;

    public FakeExporter(
        Func<DevelopExportRequest, DevelopExportResult> behaviour,
        ManualResetEventSlim? gate = null,
        Func<DevelopExportRequest, DevelopExportResult>? bakeBehaviour = null)
    {
        this.behaviour = behaviour;
        this.bakeBehaviour = bakeBehaviour ?? behaviour;
        this.gate = gate;
    }

    public int CallCount;
    public int LastThreadId;
    public int CancelledCount;
    public int DetectCallCount;
    public int BakeCallCount;
    public int BakeThreadId;
    public DevelopExportRequest? LastBakeRequest;
    public int DetectThreadId;
    public DefectRect? LastDetectRoi;
    public GrainMendDetectionOptions? LastDetectOptions;
    public DevelopRun? LastDetectRun;
    public Func<GrainMendDetectionResult>? DetectBehaviour;
    public SoftProofSettings? LastSoftProof;
    public bool LastClippingOverlay;
    public readonly List<uint> PreviewMaximumWidths = [];

    public GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null)
    {
        LastDetectRoi = rawRoi;
        LastDetectOptions = options;
        LastDetectRun = run;
        ++DetectCallCount;
        DetectThreadId = Environment.CurrentManagedThreadId;
        return DetectBehaviour is null
            ? new GrainMendDetectionResult(
                DevelopTestResults.FailedResult("detector_unavailable"),
                0U,
                0U,
                0UL,
                0UL)
            : DetectBehaviour();
    }

    public DevelopExportResult Run(DevelopExportRequest request)
    {
        Interlocked.Increment(ref CallCount);
        LastThreadId = Environment.CurrentManagedThreadId;
        gate?.Wait();
        return behaviour(request);
    }

    public DevelopExportResult BakeDefects(DevelopExportRequest request)
    {
        Interlocked.Increment(ref BakeCallCount);
        BakeThreadId = Environment.CurrentManagedThreadId;
        LastBakeRequest = request;
        return bakeBehaviour(request);
    }

    public DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        byte[] pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false)
    {
        PreviewMaximumWidths.Add(maximumWidth);
        _ = maximumHeight;
        Interlocked.Increment(ref CallCount);
        LastThreadId = Environment.CurrentManagedThreadId;
        LastSoftProof = softProof;
        LastClippingOverlay = clippingOverlay;

        if (gate is not null)
        {
            while (!gate.IsSet)
            {
                if (run is { IsCancelRequested: true })
                {
                    Interlocked.Increment(ref CancelledCount);
                    return DevelopTestResults.CancelledResult();
                }
                Thread.Yield();
            }
        }
        if (run is { IsCancelRequested: true })
        {
            Interlocked.Increment(ref CancelledCount);
            return DevelopTestResults.CancelledResult();
        }
        if (pixels.Length > 0)
        {
            pixels[0] = 0xFF;
        }
        return behaviour(request);
    }
}

internal sealed class FakeGrainMendReviewProposal : IGrainMendReviewProposal
{
    private bool disposed;

    public FakeGrainMendReviewProposal(
        uint width,
        uint height,
        IReadOnlyList<GrainMendComponent> components,
        uint sourceWidth = 0U,
        uint sourceHeight = 0U,
        uint roiX = 0U,
        uint roiY = 0U,
        uint roiWidth = 0U,
        uint roiHeight = 0U)
    {
        Width = width;
        Height = height;
        Components = components;
        SourceWidth = sourceWidth == 0U ? width : sourceWidth;
        SourceHeight = sourceHeight == 0U ? height : sourceHeight;
        RoiX = roiX;
        RoiY = roiY;
        RoiWidth = roiWidth == 0U ? SourceWidth : roiWidth;
        RoiHeight = roiHeight == 0U ? SourceHeight : roiHeight;
    }

    public uint Width { get; }

    public uint Height { get; }

    public uint SourceWidth { get; }

    public uint SourceHeight { get; }

    public uint RoiX { get; }

    public uint RoiY { get; }

    public uint RoiWidth { get; }

    public uint RoiHeight { get; }

    public IReadOnlyList<GrainMendComponent> Components { get; }

    public int DisposeCount { get; private set; }

    public int BuildAcceptedCount { get; private set; }

    public int BuildAcceptedThreadId { get; private set; }

    public Exception? BuildAcceptedFailure { get; init; }

    public bool ReturnEmptyAcceptance { get; init; }

    public ulong? AcceptedIncludedCount { get; init; }

    public Action? OnBuildAccepted { get; init; }

    public bool TryHit(int x, int y, uint radius, out int componentIndex)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        componentIndex = -1;
        long bestDistance = long.MaxValue;
        for (int component = 0; component < Components.Count; ++component)
        {
            foreach (GrainMendPreviewPoint point in Components[component].Points)
            {
                long dx = (long)point.X - x;
                long dy = (long)point.Y - y;
                if (Math.Abs(dx) > radius || Math.Abs(dy) > radius)
                {
                    continue;
                }
                long distance = (dx * dx) + (dy * dy);
                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    componentIndex = component;
                }
            }
        }
        return componentIndex >= 0;
    }

    public GrainMendAcceptedRegion? BuildAccepted(ReadOnlySpan<byte> excludedComponents)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (excludedComponents.Length != Components.Count)
        {
            throw new ArgumentException(
                "The exclusion array must match the component count.",
                nameof(excludedComponents));
        }
        ++BuildAcceptedCount;
        BuildAcceptedThreadId = Environment.CurrentManagedThreadId;
        OnBuildAccepted?.Invoke();
        if (BuildAcceptedFailure is not null)
        {
            throw BuildAcceptedFailure;
        }
        if (ReturnEmptyAcceptance)
        {
            return null;
        }
        ulong included = 0UL;
        byte[] rgba = new byte[checked((int)((ulong)Width * Height * 4UL))];
        for (int component = 0; component < Components.Count; ++component)
        {
            if (excludedComponents[component] != 0)
            {
                continue;
            }
            ++included;
            foreach (GrainMendPreviewPoint point in Components[component].Points)
            {
                if (point.X >= Width || point.Y >= Height)
                {
                    continue;
                }
                int offset = checked((int)(((ulong)point.Y * Width + point.X) * 4UL));
                rgba[offset] = rgba[offset + 1] = rgba[offset + 2] = rgba[offset + 3] = 255;
            }
        }
        return included == 0UL
            ? null
            : new GrainMendAcceptedRegion(
                0U,
                0U,
                Width,
                Height,
                rgba,
                AcceptedIncludedCount ?? included);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        ++DisposeCount;
    }
}

internal static class DevelopTestResults
{
    public static DevelopExportResult CancelledResult() => new(
        succeeded: false,
        DevelopExportStage.Decode,
        "cancelled",
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.Identity,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 1,
        cancelled: true);

    public static DevelopExportResult FailedResult(string failureName) => new(
        succeeded: false,
        DevelopExportStage.GrainMend,
        failureName,
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.FilmScanEmulation,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 0);

    public static DevelopExportResult FailedResult(
        DevelopExportStage stage,
        string failureName) => new(
        succeeded: false,
        stage,
        failureName,
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 0,
        imageHeight: 0,
        FilmLookRoute.Invalid,
        filmLookColorApplied: false,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 0,
        outputFileBytes: 0,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 0);

    public static DevelopExportResult OkResult() => new(
        succeeded: true,
        DevelopExportStage.None,
        "ok",
        nativeErrorCode: 0,
        cleanupErrorCode: 0,
        imageWidth: 100,
        imageHeight: 50,
        FilmLookRoute.FilmScanEmulation,
        filmLookColorApplied: true,
        filmLookAcutanceApplied: false,
        sourceFileBytes: 1024,
        outputFileBytes: 2048,
        filmLookWorkspaceBytes: 0,
        wallMicroseconds: 1234);
}
