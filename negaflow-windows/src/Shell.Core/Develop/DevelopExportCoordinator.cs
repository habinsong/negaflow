using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

/// <summary>현상 요청을 실제로 실행하는 것. 네이티브 호출을 시험에서 갈아 끼우기 위한 경계입니다.</summary>
public interface IDevelopExporter
{
    /// <param name="run">
    /// 실행 중 취소하고 <b>진행도를 읽는</b> 손잡이입니다. null 이면 끝까지 블로킹합니다 —
    /// 그러면 화면은 끝날 때까지 0% 에 붙박입니다. 네이티브 쪽은 처음부터 이 인자를
    /// 받고 있었고(<c>NativeDevelopExportCommand.Run</c>), 이 경계에만 빠져 있었습니다.
    /// </param>
    DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null);

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
    public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) =>
        NativeDevelopExporter.Run(request, run);

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
    /// 배치가 한 번에 돌릴 수 있는 장 수입니다. **기계에서 뽑습니다.**
    /// </summary>
    /// <remarks>
    /// <para>
    /// 예전에는 2 로 고정돼 있었고, 그 근거는 스캐너 TIFF 측정이었습니다 — 그 자료에서는
    /// 남는 것이 코어가 아니라 디스크였고 4 로 올리면 오히려 느렸습니다. 카메라 RAW 은
    /// 반대입니다. 디코드가 CPU 를 먹으므로 겹칠수록 빨라집니다. 실측(제조사별 RAW 8 장,
    /// TIFF16, 회차마다 새 프로세스, 16 코어):
    /// </para>
    /// <code>
    ///   스캔 TIFF 12 장                     카메라 RAW 12 장
    ///   동시 1장  17.1초  장당 1.43  401MB   37.6초  장당 3.13
    ///   동시 2장  12.8초  장당 1.07  672MB   25.0초  장당 2.08
    ///   동시 3장  11.1초  장당 0.92  945MB   21.2초  장당 1.76
    ///   동시 4장   9.9초  장당 0.83  958MB   19.7초  장당 1.64
    ///   동시 6장  10.1초  장당 0.84 1224MB   22.1초  장당 1.84
    ///   동시 8장   9.8초  장당 0.82 1500MB   17.3초  장당 1.44
    /// </code>
    /// <para>
    /// **무릎은 4 입니다.** 그 위로는 시간이 평평하고 메모리만 오릅니다. 예전에는 상한이 6
    /// 이었는데, 그 값은 <b>한 장의 현상이 코어 하나만 쓰던 때</b>의 것입니다. 지금은 필름
    /// 룩·인코딩·색 커널이 전부 행 블록으로 쪼개져 돌고 GPU 까지 쓰므로, 한 장이 이미 기계를
    /// 거의 채웁니다 — 여섯을 겹치면 같은 자원을 여섯으로 나눠 갖고 경합만 늘어납니다.
    /// </para>
    /// <para>
    /// 코어에서 뽑은 값과 설치 메모리에서 뽑은 값 중 작은 쪽을 씁니다 — 코어가 많아도
    /// 메모리가 작으면 겹치는 만큼 스왑으로 갑니다. 한 장이 도는 동안 원본 디코드와
    /// working 이미지가 함께 상주합니다.
    /// </para>
    /// <para>
    /// **기울기는 장당 약 1,070MB 입니다.** 예전 값 400MB 는 내보내기가 CPU 로만 돌던 때의
    /// 것입니다. 지금은 맥과 같이 GPU 로 내므로 단계마다 업로드·다운로드 버퍼가 함께
    /// 떠 있습니다 — 사진 80 장을 여섯 칸으로 돌린 실측이 최대 6,418MB 였고(CPU 판은
    /// 3,193MB), 여섯으로 나누면 칸당 약 1,070MB 입니다. 이 값을 낮게 잡으면 메모리가
    /// 적은 기계가 제 능력보다 많은 칸을 열어 스왑으로 갑니다.
    /// </para>
    /// <para>
    /// GPU 가 없거나 내장이면 색 단계까지 CPU 가 지므로 한 칸 줄입니다. 그 판정은
    /// <see cref="GpuCacheBridge"/> 가 엔진에서 읽어 옵니다 — 여기서 짐작하지 않습니다.
    /// </para>
    /// </remarks>
    public static int MaximumConcurrentExports { get; } = ResolveMaximumConcurrentExports();

    /// <summary>한 칸이 도는 동안 쓰는 양입니다. 실측 기울기입니다(위 설명).</summary>
    private const long ExportSlotBytes = 1070L * 1024 * 1024;

    /// <summary>
    /// 캐시도 GPU 풀도 아닌 몫입니다 — 코드·.NET 힙·WinUI·D3D11 스테이징.
    /// </summary>
    /// <remarks>
    /// 엔진이 같은 자리를 재어 남긴 값입니다: 코드 432MB, D3D11 스테이징 297MB
    /// (<c>frame_cache_budget.cpp</c> 의 "캐시가 아닌 몫"). 합쳐 1GB 로 둡니다.
    /// </remarks>
    private const long ProcessBaselineBytes = 1024L * 1024 * 1024;

    /// <summary>
    /// 내장 그래픽의 작업 텍스처는 **같은 RAM 에서 나옵니다.** 엔진이 설치 RAM 의 이 몫을
    /// GPU 풀 상한으로 씁니다(<c>gpu_cache_budget.h</c> 의 <c>integrated_system_fraction</c>).
    /// 여기서 빼 두지 않으면 같은 바이트를 두 번 쓰게 됩니다.
    /// </summary>
    private const double IntegratedGpuFraction = 0.15;

    /// <summary>
    /// 실측으로 시간이 평평해지는 자리입니다(위 표). 넘겨 봐야 메모리만 오릅니다.
    /// </summary>
    private const int MaximumUsefulSlots = 4;

    private static int ResolveMaximumConcurrentExports() =>
        ResolveMaximumConcurrentExports(
            Environment.ProcessorCount,
            (ulong)Math.Max(0L, GC.GetGCMemoryInfo().TotalAvailableMemoryBytes),
            GpuCacheBridge.TryRead());

    /// <summary>
    /// 칸 수를 정하는 규칙입니다. **인자는 전부 기계에서 옵니다** — 상수는 실측 기울기뿐입니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// 램 8GB · 내장 그래픽 노트북에서도 돌아야 합니다. 예전 규칙은 예약이 1GB 고정이라
    /// 그런 기계에서 코어가 여덟이면 세 칸을 열었고, 앱의 프레임 캐시(그 크기에서는 890MB)와
    /// 내장 GPU 풀(설치 RAM 의 15% = 1,229MB)이 <b>같은 8GB</b> 를 나눠 쓰는 것을 아무도 세지
    /// 않아 합계가 6.3GB 가 됐습니다. 그 기계는 스왑으로 갑니다.
    /// </para>
    /// <para>
    /// 그래서 예약을 기계에서 뽑습니다 — 프레임 캐시 예산(<see cref="FrameCacheBudget"/>,
    /// 엔진과 같은 규칙) + 내장이면 GPU 풀 몫 + 프로세스 바탕. 그 위에 프로세스 전체가 설치
    /// 메모리의 <see cref="FrameCacheBudget.ManualMemoryFraction"/> 를 넘지 않게 묶습니다 —
    /// 이 저장소가 이미 "이 기계에서 우리가 가져도 되는 최대" 로 쓰는 값입니다.
    /// </para>
    /// </remarks>
    internal static int ResolveMaximumConcurrentExports(
        int processorCount,
        ulong installedBytes,
        GpuCacheInfo? gpu)
    {
        int byCores = Math.Max(1, processorCount / 2);
        if (installedBytes == 0UL)
        {
            // 설치 메모리를 못 읽었습니다. 모르는 것을 근거로 여러 칸을 열지 않습니다.
            return 1;
        }

        bool hasDiscreteGpu = gpu is { HasGpu: true, IsIntegrated: false };
        FrameCacheLimits cache = FrameCacheBudget.AutomaticLimits(installedBytes);
        long cacheBytes = (long)(FrameCacheBudget.EstimatedResidentMegabytes(cache) * 1024 * 1024);
        long integratedGpuBytes = hasDiscreteGpu
            ? 0L
            : (long)(installedBytes * IntegratedGpuFraction);
        long reserve = cacheBytes + integratedGpuBytes + ProcessBaselineBytes;

        long ceiling = (long)(installedBytes * FrameCacheBudget.ManualMemoryFraction);
        long forSlots = ceiling - reserve;
        int byMemory = forSlots >= ExportSlotBytes ? (int)(forSlots / ExportSlotBytes) : 1;

        int slots = Math.Min(byCores, byMemory);
        if (!hasDiscreteGpu)
        {
            // 전용 GPU 가 없으면 색·룩 단계도 CPU 가 집니다. 디코드와 서로 코어를 뺏습니다.
            slots -= 1;
        }
        return Math.Clamp(slots, 1, MaximumUsefulSlots);
    }

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
    /// <param name="onProgress">
    /// 이 한 장이 얼마나 갔는지(0~1)를 <b>도는 동안</b> 알립니다. 엔진이
    /// <c>progress_permille</c> 로 내는 값이며, 없으면 화면은 끝날 때까지 0% 에
    /// 붙박입니다. 워커 스레드에서 부르므로 받는 쪽이 UI 스레드로 넘겨야 합니다.
    /// </param>
    public async Task<bool> StartAsync(
        LibraryFrameSnapshot frame,
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted,
        ExportEncodingOptions? encoding = null,
        int maximumConcurrent = 1,
        Action<double>? onProgress = null)
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
            ExportCargoTrace.Write(frame, built);
            if (built.Request is not { } request)
            {
                return Deliver(DevelopExportOutcome.Refused(built.Refusal), onCompleted);
            }

            DevelopExportOutcome outcome;
            try
            {
                if (onProgress is null)
                {
                    outcome = DevelopExportOutcome.Completed(
                        await Task.Run(() => exporter.Run(request)).ConfigureAwait(false));
                }
                else
                {
                    // 엔진은 단계가 끝날 때마다 상태 칸에 진행도를 씁니다. 그 칸을 짧은
                    // 간격으로 읽어 넘깁니다 — 엔진 쪽에 콜백을 새로 만들지 않습니다.
                    using DevelopRun run = new();
                    using CancellationTokenSource polling = new();
                    Task watcher = PollProgressAsync(run, onProgress, polling.Token);
                    try
                    {
                        outcome = DevelopExportOutcome.Completed(
                            await Task.Run(() => exporter.Run(request, run)).ConfigureAwait(false));
                    }
                    finally
                    {
                        polling.Cancel();
                        try
                        {
                            await watcher.ConfigureAwait(false);
                        }
                        catch (OperationCanceledException)
                        {
                        }
                    }
                    onProgress(1.0);
                }
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
    /// 도는 동안 엔진의 진행도를 읽어 넘깁니다.
    /// </summary>
    /// <remarks>
    /// 간격은 사람이 "움직인다" 고 느끼는 최소치에 맞춥니다. 더 짧게 잡으면 읽는 값이
    /// 같은 채로 UI 만 깨우고, 더 길게 잡으면 8 초짜리 내보내기에서 눈금이 몇 칸밖에
    /// 안 움직입니다.
    /// </remarks>
    private static async Task PollProgressAsync(
        DevelopRun run,
        Action<double> onProgress,
        CancellationToken token)
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(120), token).ConfigureAwait(false);
                onProgress(run.Progress);
            }
        }
        catch (OperationCanceledException)
        {
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
