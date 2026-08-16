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

internal sealed class FakeExporter : IDevelopExporter
{
    private readonly Func<DevelopExportRequest, DevelopExportResult> behaviour;
    private readonly ManualResetEventSlim? gate;

    public FakeExporter(
        Func<DevelopExportRequest, DevelopExportResult> behaviour,
        ManualResetEventSlim? gate = null)
    {
        this.behaviour = behaviour;
        this.gate = gate;
    }

    public int CallCount;
    public int LastThreadId;
    public int CancelledCount;
    public int DetectCallCount;
    public int DetectThreadId;
    public DefectRect? LastDetectRoi;
    public GrainMendDetectionOptions? LastDetectOptions;
    public Func<byte[], GrainMendDetectionResult>? DetectBehaviour;
    public SoftProofSettings? LastSoftProof;

    public GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        byte[] mask,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null)
    {
        LastDetectRoi = rawRoi;
        LastDetectOptions = options;
        ++DetectCallCount;
        DetectThreadId = Environment.CurrentManagedThreadId;
        return DetectBehaviour is null
            ? new GrainMendDetectionResult(
                DevelopTestResults.FailedResult("detector_unavailable"),
                0U,
                0U,
                0UL,
                0UL)
            : DetectBehaviour(mask);
    }

    public DevelopExportResult Run(DevelopExportRequest request)
    {
        Interlocked.Increment(ref CallCount);
        LastThreadId = Environment.CurrentManagedThreadId;
        gate?.Wait();
        return behaviour(request);
    }

    public DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        byte[] pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null)
    {
        _ = maximumWidth;
        _ = maximumHeight;
        Interlocked.Increment(ref CallCount);
        LastThreadId = Environment.CurrentManagedThreadId;
        LastSoftProof = softProof;

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
