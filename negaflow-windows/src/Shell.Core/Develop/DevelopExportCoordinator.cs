using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>현상 요청을 실제로 실행하는 것. 네이티브 호출을 시험에서 갈아 끼우기 위한 경계입니다.</summary>
public interface IDevelopExporter
{
    DevelopExportResult Run(DevelopExportRequest request);

    /// <param name="run">
    /// 실행 중 취소하고 진행도를 읽는 손잡이입니다. null 이면 끝까지 블로킹합니다.
    /// </param>
    /// <param name="softProof">
    /// 보기용 시뮬레이션입니다. null 이면 프루프 없는 미리보기입니다. <see cref="Run"/> 에는
    /// 대응하는 인자가 없습니다 — 인화물은 시뮬레이션을 담지 않습니다.
    /// </param>
    DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        byte[] pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false);

    /// <summary>
    /// GrainMend 가 무엇을 고칠지 재기만 합니다. 빈 <paramref name="mask"/> 로 부르면 필요한
    /// 크기만 알려 줍니다.
    /// </summary>
    GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        byte[] mask,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null);
}

/// <summary>제품 구현. 블로킹이며 워커 스레드에서만 불러야 합니다.</summary>
public sealed class NativeDevelopExporterAdapter : IDevelopExporter
{
    public DevelopExportResult Run(DevelopExportRequest request) =>
        NativeDevelopExporter.Run(request);

    public DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        byte[] pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false) =>
        NativeDevelopExporter.Preview(
            request,
            maximumWidth,
            maximumHeight,
            pixels,
            run,
            softProof,
            clippingOverlay);

    public GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        byte[] mask,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null) =>
        NativeDevelopExporter.DetectGrainMend(
            request,
            mask,
            rawRoi.X,
            rawRoi.Y,
            rawRoi.Width,
            rawRoi.Height,
            run,
            options);
}

public enum DevelopExportOutcomeKind
{
    /// <summary>네이티브까지 갔고 결과가 있습니다. 성공했다는 뜻은 아닙니다.</summary>
    Completed,

    /// <summary>요청을 만들지 못했습니다. 네이티브를 부르지 않았습니다.</summary>
    Refused,

    /// <summary>네이티브 호출이 예외를 던졌습니다.</summary>
    Faulted,

    /// <summary>이미 현상이 돌고 있어 시작하지 않았습니다.</summary>
    Busy,

    /// <summary>
    /// 더 새로운 요청이 이 실행을 취소했습니다. 실패가 아니며 픽셀도 파일도 남기지 않습니다.
    /// </summary>
    Cancelled,
}

public sealed record DevelopExportOutcome(
    DevelopExportOutcomeKind Kind,
    DevelopExportResult? Result,
    DevelopRequestRefusal Refusal,
    string? FaultMessage)
{
    internal static DevelopExportOutcome Completed(DevelopExportResult result) =>
        new(DevelopExportOutcomeKind.Completed, result, DevelopRequestRefusal.None, null);

    internal static DevelopExportOutcome Refused(DevelopRequestRefusal refusal) =>
        new(DevelopExportOutcomeKind.Refused, null, refusal, null);

    internal static DevelopExportOutcome Faulted(string message) =>
        new(DevelopExportOutcomeKind.Faulted, null, DevelopRequestRefusal.None, message);

    internal static DevelopExportOutcome Busy() =>
        new(DevelopExportOutcomeKind.Busy, null, DevelopRequestRefusal.None, null);
}

/// <summary>
/// Export 버튼 뒤의 스레딩 정책 전부입니다.
/// </summary>
/// <remarks>
/// 규칙 셋입니다.
/// <list type="number">
/// <item>네이티브 호출은 **절대** 호출 스레드에서 돌지 않습니다. 현상 전체 동안 블로킹하므로
/// UI 스레드에서 부르면 앱이 굳습니다.</item>
/// <item>결과는 **항상** dispatcher 를 거쳐 돌아옵니다. 거부와 예외도 같은 길로 갑니다. 성공만
/// dispatcher 를 타면 실패 경로가 백그라운드에서 컨트롤을 건드리게 됩니다.</item>
/// <item>dispatcher 가 콜백을 받지 못해도(창이 닫혀 큐가 종료된 경우) 진행 중 표시는 반드시
/// 풀립니다. 그러지 않으면 앱이 영영 "현상 중" 으로 남습니다.</item>
/// </list>
/// </remarks>
public sealed class DevelopExportCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private int inFlight;

    public DevelopExportCoordinator(IDevelopExporter exporter, IUiDispatcher dispatcher)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        this.exporter = exporter;
        this.dispatcher = dispatcher;
    }

    public bool IsRunning => Volatile.Read(ref inFlight) != 0;

    /// <summary>
    /// 콜백이 배달되거나 배달에 실패한 뒤 완료됩니다. 반환값은 **결과가 UI 로 전달됐는지** 이며,
    /// 현상이 성공했는지가 아닙니다. 성공 여부는 콜백이 받는
    /// <see cref="DevelopExportOutcome"/> 안에 있습니다.
    /// </summary>
    public async Task<bool> StartAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        if (Interlocked.CompareExchange(ref inFlight, 1, 0) != 0)
        {
            // Busy 도 dispatcher 를 거칩니다. 호출자가 경로마다 다른 규칙을 기억하지 않도록.
            return Deliver(DevelopExportOutcome.Busy(), onCompleted);
        }

        try
        {
            DevelopRequestResult built = DevelopRequestFactory.Create(
                frame,
                destinationPath,
                format,
                encoding);
            if (built.Request is not { } request)
            {
                return Deliver(DevelopExportOutcome.Refused(built.Refusal), onCompleted);
            }

            DevelopExportOutcome outcome;
            try
            {
                outcome = DevelopExportOutcome.Completed(
                    await Task.Run(() => exporter.Run(request)).ConfigureAwait(false));
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                // 네이티브 경계에서 나온 예외를 관측하지 않으면 UI 는 영원히 기다립니다.
                outcome = DevelopExportOutcome.Faulted(error.Message);
            }

            return Deliver(outcome, onCompleted);
        }
        finally
        {
            Volatile.Write(ref inFlight, 0);
        }
    }

    private bool Deliver(
        DevelopExportOutcome outcome,
        Action<DevelopExportOutcome> onCompleted)
    {
        // 이미 UI 스레드면 굳이 큐를 한 바퀴 돌지 않습니다. 큐가 종료된 뒤에도 동기 거부는
        // 그대로 전달됩니다.
        if (dispatcher.HasThreadAccess)
        {
            onCompleted(outcome);
            return true;
        }
        return dispatcher.TryEnqueue(() => onCompleted(outcome));
    }
}
