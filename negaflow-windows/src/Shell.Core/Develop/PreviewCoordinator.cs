using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell;

/// <summary>
/// 미리보기 렌더입니다. Export 와 같은 스레딩 규칙을 따르되, 하나 더 있습니다 —
/// **마지막 요청은 반드시 그려집니다.**
/// </summary>
/// <remarks>
/// <para>
/// 슬라이더는 한 번 움직이는 동안 요청을 여러 번 만듭니다. 도착하는 대로 다 그리면 엔진이
/// 밀리고, 돌고 있을 때 그냥 버리면 마지막 상태가 화면에 안 나타나 사용자가 방금 한 조작이
/// 사라진 것처럼 보입니다. 그래서 진행 중이면 **가장 최근 요청 하나만** 대기시켰다가 끝난 뒤
/// 이어서 그립니다. 중간 요청은 버립니다 — 어차피 이미 지나간 상태입니다.
/// </para>
/// <para>
/// 새 요청이 들어오면 **돌고 있던 렌더를 즉시 취소합니다.** 그 결과는 이미 지나간 상태이므로
/// 끝까지 기다릴 이유가 없습니다. 실제 스캔 해상도에서 이 대기가 슬라이더 지연의 대부분이며,
/// 취소된 렌더는 픽셀을 만들지 않으므로 화면에 배달하지도 않습니다.
/// </para>
/// </remarks>
public sealed partial class PreviewCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly uint maximumWidth;
    private readonly uint maximumHeight;

    /// <summary>
    /// 화소 버퍼 두 장을 번갈아 씁니다.
    /// </summary>
    /// <remarks>
    /// 한 장이면 배달한 버퍼를 <b>다음 렌더가 곧바로 덮어씁니다.</b> 그 버퍼는 배달 뒤에도
    /// 히스토그램 표본(워커 스레드)과 캔버스 스포이드가 계속 읽으므로, 찢어진 화소를 읽어
    /// 화면 색과 적히는 수가 갈렸습니다. 두 장을 번갈아 쓰면 배달된 버퍼는 <b>그 다음</b>
    /// 렌더까지 온전합니다.
    /// </remarks>
    private readonly byte[][] buffers;
    private int bufferIndex;

    /// <summary>
    /// 버퍼 임대입니다. 배달된 버퍼는 <b>UI 스레드가 다 쓸 때까지</b> 다음 렌더가 손대지
    /// 못합니다.
    /// </summary>
    /// <remarks>
    /// 이것이 없으면 버퍼가 두 장이라도 렌더 N+2 가 배달 N 이 아직 큐에 있는 버퍼를
    /// 덮어씁니다. 그러면 화면에 그려지는 화소가 배달의 리비전과 어긋나, 리비전 검사를
    /// 통과한 그림조차 <b>다른 상태의 화소</b>가 됩니다. 임대와 리비전은 둘 다 있어야
    /// 뜻이 있습니다.
    /// </remarks>
    private readonly SemaphoreSlim[] bufferLeases;

    private readonly Lock gate = new();

    private readonly Func<double>? displayTargetPixels;
    private readonly bool settleEnabled;
    private int developRevision;

    private bool isRunning;
    private PreviewRequest? pending;
    // The handle for the render currently inside the engine. Held under the same lock as
    // `pending` so a request that queues itself also cancels what it just superseded.
    private DevelopRun? activeRun;

    /// <summary>
    /// 지금 엔진 안에 있는 것이 정착(3600) 패스인지입니다. 인터랙티브는 끝까지 그리고
    /// 정착만 끊기 위해 필요합니다 — <see cref="RequestAsync"/> 의 주석 참고.
    /// </summary>
    private bool activeRunIsSettled;
    private string? activeFrameId;
    // Set from the UI thread, read on a worker, so it goes under the same lock as
    // everything else here rather than acquiring its own rule.
    private SoftProofSettings? softProof;
    private bool clippingOverlayEnabled;
    private bool uninvertedSource;

    public PreviewCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        uint maximumWidth,
        uint maximumHeight)
        : this(exporter, dispatcher, maximumWidth, maximumHeight, displayTargetPixels: null, settleEnabled: false)
    {
    }

    /// <summary>
    /// macOS <c>renderLatestDevelopment</c> 과 같은 두 패스입니다. 표시 크기 적응 프록시 뒤에
    /// 0.14초 무편집이면 3600 정착을 돌립니다.
    /// </summary>
    public PreviewCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        Func<double> displayTargetPixels)
        : this(
            exporter,
            dispatcher,
            DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension),
            DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension),
            displayTargetPixels,
            settleEnabled: true)
    {
    }

    private PreviewCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        uint maximumWidth,
        uint maximumHeight,
        Func<double>? displayTargetPixels,
        bool settleEnabled)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);

        this.exporter = exporter;
        this.dispatcher = dispatcher;
        this.maximumWidth = maximumWidth;
        this.maximumHeight = maximumHeight;
        this.displayTargetPixels = displayTargetPixels;
        this.settleEnabled = settleEnabled;
        long bufferBytes = (long)maximumWidth * maximumHeight * 4;
        buffers = [new byte[bufferBytes], new byte[bufferBytes]];
        bufferLeases = [new SemaphoreSlim(1, 1), new SemaphoreSlim(1, 1)];
    }

    private sealed record PreviewRequest(
        LibraryFrameSnapshot Frame,
        Action<PreviewOutcome> OnCompleted,
        int Revision);

    /// <summary>렌더 한 번의 결과와, 그 화소가 들어 있는 버퍼의 임대입니다.</summary>
    private readonly record struct LeasedOutcome(PreviewOutcome Outcome, int Lease);

    public bool IsRendering
    {
        get
        {
            lock (gate)
            {
                return isRunning;
            }
        }
    }

    /// <summary>
    /// 화면에 거는 보기용 프루프입니다. null 이면 프루프 없이 그립니다.
    /// </summary>
    /// <remarks>
    /// **다음 렌더부터** 적용됩니다. 바꾼 뒤 <see cref="RequestAsync"/> 를 불러야 화면이
    /// 따라오고, 그 호출이 돌고 있던 렌더를 취소하므로 낡은 프루프 상태의 그림이 뒤늦게
    /// 배달되는 일은 없습니다.
    /// </remarks>
    public SoftProofSettings? SoftProof
    {
        get
        {
            lock (gate)
            {
                return softProof;
            }
        }
        set
        {
            lock (gate)
            {
                softProof = value;
            }
        }
    }

    /// <summary>
    /// macOS <c>selectCompareMode(.raw)</c> — 베이스 스포이드가 켜져 있으면 반전 전
    /// 원본을 그립니다. 다음 렌더부터 적용됩니다.
    /// </summary>
    public bool UninvertedSource
    {
        get
        {
            lock (gate)
            {
                return uninvertedSource;
            }
        }
        set
        {
            lock (gate)
            {
                uninvertedSource = value;
            }
        }
    }

    /// <summary>
    /// 개발자 디버그 오버레이가 보여 줄 단계입니다. <c>null</c> 이면 평소처럼 최종 결과를
    /// 그립니다. macOS <c>ScanFrame.debugOverlayStage</c> 자리이며 다음 렌더부터 적용됩니다.
    /// </summary>
    public DevelopDebugStage? DebugStage
    {
        get
        {
            lock (gate)
            {
                return debugStage;
            }
        }
        set
        {
            lock (gate)
            {
                debugStage = value;
            }
        }
    }

    private DevelopDebugStage? debugStage;

    /// <summary>
    /// macOS <c>clippingOverlayEnabled</c>. 다음 렌더부터 적용됩니다.
    /// </summary>
    public bool ClippingOverlayEnabled
    {
        get
        {
            lock (gate)
            {
                return clippingOverlayEnabled;
            }
        }
        set
        {
            lock (gate)
            {
                clippingOverlayEnabled = value;
            }
        }
    }

    /// <summary>
    /// 렌더를 요청합니다. 이미 돌고 있으면 대기 자리에 넣고, 거기 있던 것은 버립니다. 반환되는
    /// Task 는 **이 호출이 실제로 렌더를 시작했을 때만** 그 렌더가 끝날 때까지 이어집니다.
    /// </summary>
    public Task RequestAsync(
        LibraryFrameSnapshot frame,
        Action<PreviewOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        DevelopRun run;
        PreviewRequest request;
        lock (gate)
        {
            // 요청마다 하나씩 올라가는 번호입니다. 배달된 그림이 어느 편집 상태의 것인지
            // 화면이 판정하는 유일한 근거입니다.
            request = new PreviewRequest(frame, onCompleted, ++developRevision);
            PreviewTrace.Write(
                "RequestAsync rev=" + request.Revision +
                " frame=" + frame.Id +
                " running=" + isRunning +
                " active=" + (activeFrameId ?? "null") +
                " settled=" + activeRunIsSettled);
            if (isRunning)
            {
                pending = request;
                // **같은 사진의 인터랙티브 패스는 취소하지 않습니다.**
                // 앞 판은 새 요청마다 돌고 있던 렌더를 취소했고, `RunLoopAsync` 는
                // 취소된 결과를 버립니다. 그래서 슬라이더를 **계속 끄는 동안에는 어떤
                // 렌더도 완주하지 못해 화면이 한 장도 안 바뀌었습니다** — 손을 멈춰야
                // 비로소 한 장이 나왔습니다. 사용자가 "사진이 바로 반영이 안 된다"고
                // 본 것이 이것입니다.
                //
                // 인터랙티브 한 장은 짧으므로(이 기계 실측 45.9 ms, 상자는 실측
                // 처리량으로 접습니다) 끝까지 그려서 **배달하고** 곧바로 최신 값으로
                // 다음 장을 그립니다. 그러면 끄는 내내 그림이 따라옵니다.
                //
                // 정착 패스(3600)는 반대입니다. 길고 그 결과는 이미 지나간 상태이므로
                // 새 편집이 오면 즉시 끊습니다.
                //
                // 사진을 바꾸면 이전 장의 인터랙티브도 끊습니다. 안 끊으면 새 장이
                // 이전 렌더가 끝날 때까지 줄 서서, 캐시 현상본을 올려 둬도 곧 옛 그림이
                // 덮거나 전환이 한 장만큼 늦습니다.
                bool differentFrame = activeFrameId is not null &&
                    !string.Equals(activeFrameId, frame.Id, StringComparison.Ordinal);
                if (activeRunIsSettled || differentFrame)
                {
                    PreviewTrace.Write(
                        "cancel issued rev=" + request.Revision +
                        " prev=" + (activeFrameId ?? "null") +
                        " settled=" + activeRunIsSettled);
                    activeRun?.Cancel();
                }
                return Task.CompletedTask;
            }
            isRunning = true;
            activeFrameId = frame.Id;
            // Created here rather than inside the render so that `activeRun` is never null
            // while `isRunning` is true. Otherwise a request arriving in the gap between
            // the two would find nothing to cancel and sit through a whole stale render.
            run = new DevelopRun();
            activeRun = run;
            activeRunIsSettled = false;
        }
        return RunLoopAsync(request, run);
    }

    private async Task RunLoopAsync(PreviewRequest request, DevelopRun run)
    {
        PreviewRequest? current = request;
        DevelopRun currentRun = run;
        try
        {
            while (current is not null)
            {
                LeasedOutcome leased;
                try
                {
                    leased = await RenderAsync(current, currentRun).ConfigureAwait(false);
                }
                finally
                {
                    // The engine call has returned, so the shared words are no longer
                    // read by anyone. A Cancel racing in after this is a no-op rather
                    // than a use-after-free, and the request that issued it is queued.
                    currentRun.Dispose();
                }
                // A cancelled render produced no pixels and describes a state the user has
                // already moved on from. Dropping it silently is the point: the request
                // that cancelled it is queued and will deliver the current state instead.
                if (leased.Outcome.Kind != DevelopExportOutcomeKind.Cancelled)
                {
                    Deliver(leased, current.OnCompleted);
                }
                else
                {
                    ReleaseLease(leased.Lease);
                }
                lock (gate)
                {
                    current = pending;
                    pending = null;
                    if (current is null)
                    {
                        isRunning = false;
                        activeRun = null;
                        activeRunIsSettled = false;
                        activeFrameId = null;
                    }
                    else
                    {
                        currentRun = new DevelopRun();
                        activeRun = currentRun;
                        activeRunIsSettled = false;
                        activeFrameId = current.Frame.Id;
                    }
                }
            }
        }
        catch
        {
            // 예외로 pending 을 지우면 방금 고른 사진의 렌더가 영영 안 옵니다.
            // 썸네일 자리표시자가 고해상도로 안 바뀌던 경로입니다.
            PreviewRequest? retry;
            lock (gate)
            {
                retry = pending;
                pending = null;
                if (retry is null)
                {
                    isRunning = false;
                    activeRun = null;
                    activeRunIsSettled = false;
                    activeFrameId = null;
                }
            }
            if (retry is null)
            {
                throw;
            }
            DevelopRun retryRun = new();
            lock (gate)
            {
                isRunning = true;
                activeRun = retryRun;
                activeRunIsSettled = false;
                activeFrameId = retry.Frame.Id;
            }
            await RunLoopAsync(retry, retryRun).ConfigureAwait(false);
        }
    }
}
