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

    /// <summary>GrainMend 가 무엇을 고칠지 재기만 합니다.</summary>
    GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null);
}

public interface IDefectBakeExporter
{
    DevelopExportResult BakeDefects(DevelopExportRequest request);
}

/// <summary>제품 구현. 블로킹이며 워커 스레드에서만 불러야 합니다.</summary>
public sealed class NativeDevelopExporterAdapter : IDevelopExporter, IDefectBakeExporter
{
    public DevelopExportResult Run(DevelopExportRequest request) =>
        NativeDevelopExporter.Run(request);

    public DevelopExportResult BakeDefects(DevelopExportRequest request) =>
        NativeDevelopExporter.BakeDefects(request);

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

    /// <summary>카탈로그 background 채움 결과를 native raw에 중복 상주시지 않습니다.</summary>
    public DevelopExportResult PreviewBackground(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        byte[] pixels,
        DevelopRun? run = null) =>
        NativeDevelopExporter.PreviewBackground(
            request,
            maximumWidth,
            maximumHeight,
            pixels,
            run);

    public GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        DefectRect rawRoi,
        GrainMendDetectionOptions options,
        DevelopRun? run = null) =>
        NativeDevelopExporter.DetectGrainMend(
            request,
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
    /// 배치가 한 번에 돌릴 수 있는 장 수입니다. macOS
    /// <c>startExportBatch(… maximumConcurrent: 2)</c> 와 같은 값입니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 한 장이 코어를 다 쓰지 않습니다 — frame_1(5088x3401) 실측에서 CPU 5,109ms 를 쓰는 동안
    /// 벽시계는 1,960ms 로, 16 코어에서 병렬도가 2.6 이었습니다. 남는 코어와, 디스크에
    /// 103MB 를 쓰는 동안 노는 CPU 를 두 번째 장이 씁니다.
    /// </para>
    /// <para>
    /// <b>더 늘려도 빨라지지 않습니다.</b> 코어와 설치 메모리로 4 까지 올려 재 봤습니다
    /// (16 코어 · 32GB, 6장 빠른 내보내기): 2 에서 32.6초, 4 에서 36.98초와 34.14초로
    /// <b>오히려 느렸습니다</b>. 남는 것은 코어가 아니라 메모리 대역과 디스크였고, 장을
    /// 더 겹치면 그 둘을 서로 뺏습니다. macOS 가 2 에 멈춘 이유도 같습니다 — 다시 올리려면
    /// 이 수치부터 다시 재십시오.
    /// </para>
    /// </remarks>
    public const int MaximumConcurrentExports = 2;

    /// <summary>
    /// 콜백이 배달되거나 배달에 실패한 뒤 완료됩니다. 반환값은 **결과가 UI 로 전달됐는지** 이며,
    /// 현상이 성공했는지가 아닙니다. 성공 여부는 콜백이 받는
    /// <see cref="DevelopExportOutcome"/> 안에 있습니다.
    /// </summary>
    /// <param name="maximumConcurrent">
    /// 이 호출까지 포함해 동시에 돌아도 되는 장 수입니다. 기본 1 은 지금까지와 같습니다 —
    /// 이미 한 장이 돌고 있으면 <see cref="DevelopExportOutcomeKind.Busy"/> 로 돌려보냅니다.
    /// 배치만 <see cref="MaximumConcurrentExports"/> 를 넘깁니다.
    /// </param>
    public async Task<bool> StartAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null,
        int maximumConcurrent = 1)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        if (!TryEnter(maximumConcurrent))
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
            _ = Interlocked.Decrement(ref inFlight);
        }
    }

    /// <summary>
    /// 지금 도는 수가 <paramref name="limit"/> 보다 적을 때만 자리를 하나 집습니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 0↔1 뿐이라 두 번째 장이 곧바로 <see cref="DevelopExportOutcomeKind.Busy"/> 였고,
    /// 그래서 배치가 순서대로밖에 돌 수 없었습니다. 세는 값으로 바꾸되 <b>기본 한도는 1</b> 이라
    /// 단일 내보내기의 거동은 그대로입니다.
    /// </remarks>
    private bool TryEnter(int limit)
    {
        int allowed = Math.Max(1, limit);
        while (true)
        {
            int current = Volatile.Read(ref inFlight);
            if (current >= allowed)
            {
                return false;
            }
            if (Interlocked.CompareExchange(ref inFlight, current + 1, current) == current)
            {
                return true;
            }
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
