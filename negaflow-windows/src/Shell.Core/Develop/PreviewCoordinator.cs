using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public sealed record PreviewOutcome(
    DevelopExportOutcomeKind Kind,
    byte[]? Pixels,
    uint Width,
    uint Height,
    DevelopExportResult? Result,
    DevelopRequestRefusal Refusal,
    string? FaultMessage,
    /// <summary>
    /// macOS <c>fullMaxDimension</c> 정착 패스의 결과입니다. 썸네일·인화가 기억하는
    /// <c>ScanFrame.developedImage</c> 는 정착본에서만 만들어집니다 — 인터랙티브 패스는
    /// 끄는 동안 수십 번 오므로 그때마다 34MB 를 복사하면 UI 스레드가 멎습니다.
    /// </summary>
    bool Settled = false,
    /// <summary>
    /// 이 그림이 어느 편집 상태의 것인지입니다. 요청마다 하나씩 올라갑니다.
    /// </summary>
    /// <remarks>
    /// ☠️ 화면은 <b>자기가 그린 것보다 낮은 리비전을 버려야</b> 합니다. 배달은
    /// <c>dispatcher.TryEnqueue</c> 로 UI 큐에 실리므로 두 장이 연달아 실릴 수 있고,
    /// 그러면 나중에 처리되는 쪽이 <b>더 옛 그림</b>일 수 있습니다. 실제로 그 때문에
    /// 노출을 올렸다 내리면 내려간 그림이 화면에 안 남았습니다.
    /// </remarks>
    int Revision = 0,
    /// <summary>이 그림이 어느 프레임의 것인지입니다. 사진 전환 뒤 옛 장 배달을 버립니다.</summary>
    string? FrameId = null)
{
    internal static PreviewOutcome Refused(DevelopRequestRefusal refusal, int revision) =>
        new(DevelopExportOutcomeKind.Refused, null, 0, 0, null, refusal, null, false, revision);

    internal static PreviewOutcome Faulted(string message, int revision) =>
        new(DevelopExportOutcomeKind.Faulted, null, 0, 0, null,
            DevelopRequestRefusal.None, message, false, revision);

    internal static PreviewOutcome Cancelled() =>
        new(DevelopExportOutcomeKind.Cancelled, null, 0, 0, null,
            DevelopRequestRefusal.None, null);
}

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
public sealed class PreviewCoordinator
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
    /// ☠️ 이것이 없으면 버퍼가 두 장이라도 렌더 N+2 가 배달 N 이 아직 큐에 있는 버퍼를
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
                // ☠️ **같은 사진의 인터랙티브 패스는 취소하지 않습니다.**
                //    앞 판은 새 요청마다 돌고 있던 렌더를 취소했고, `RunLoopAsync` 는
                //    취소된 결과를 버립니다. 그래서 슬라이더를 **계속 끄는 동안에는 어떤
                //    렌더도 완주하지 못해 화면이 한 장도 안 바뀌었습니다** — 손을 멈춰야
                //    비로소 한 장이 나왔습니다. 사용자가 "사진이 바로 반영이 안 된다"고
                //    본 것이 이것입니다.
                //
                //    인터랙티브 한 장은 짧으므로(이 기계 실측 45.9 ms, 상자는 실측
                //    처리량으로 접습니다) 끝까지 그려서 **배달하고** 곧바로 최신 값으로
                //    다음 장을 그립니다. 그러면 끄는 내내 그림이 따라옵니다.
                //
                //    정착 패스(3600)는 반대입니다. 길고 그 결과는 이미 지나간 상태이므로
                //    새 편집이 오면 즉시 끊습니다.
                //
                //    사진을 바꾸면 이전 장의 인터랙티브도 끊습니다. 안 끊으면 새 장이
                //    이전 렌더가 끝날 때까지 줄 서서, 캐시 현상본을 올려 둬도 곧 옛 그림이
                //    덮거나 전환이 한 장만큼 늦습니다.
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

    private async Task<LeasedOutcome> RenderAsync(PreviewRequest request, DevelopRun run)
    {
        LibraryFrameSnapshot frame = request.Frame;
        int revision = request.Revision;
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다. 네이티브가 무시하는
        // 자리이므로 frame 옆의 이름을 넣어 두고, 실제로는 아무것도 만들어지지 않습니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".preview.png");
        bool rawSource;
        lock (gate)
        {
            rawSource = uninvertedSource;
        }
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            unusedDestination,
            uninvertedSource: rawSource);
        if (built.Request is not { } developRequest)
        {
            PreviewTrace.Write("RenderAsync refused " + built.Refusal + " rev=" + revision);
            return new LeasedOutcome(PreviewOutcome.Refused(built.Refusal, revision), -1);
        }

        // Read once, here, so the whole render uses one proof state even if the property
        // changes while it is inside the engine. That render is superseded anyway.
        SoftProofSettings? proof = SoftProof;
        bool clippingOverlay = ClippingOverlayEnabled;

        try
        {
            uint interactiveEdge = InteractiveEdge();
            PreviewTrace.Write("RenderAsync start rev=" + revision + " edge=" + interactiveEdge);
            // 인터랙티브 상자가 이미 정착 치수면 뒤따르는 정착 패스가 없습니다. 그때는
            // 이 결과가 곧 정착본입니다 — macOS `cachedPreviewRaw` 의 정착 갈래와 같은 판정.
            bool interactiveIsFinal = !settleEnabled ||
                interactiveEdge >= DevelopPreviewProxy.FullMaxDimension - 0.5;
            lock (gate)
            {
                activeRunIsSettled = false;
            }
            LeasedOutcome interactive = await PreviewOnceAsync(
                developRequest,
                frame.Id,
                interactiveEdge,
                interactiveEdge,
                run,
                proof,
                clippingOverlay,
                settled: interactiveIsFinal,
                revision: revision).ConfigureAwait(false);
            PreviewTrace.Write(
                "RenderAsync interactive kind=" + interactive.Outcome.Kind +
                " final=" + interactiveIsFinal +
                " edge=" + interactiveEdge +
                " w=" + interactive.Outcome.Width +
                " h=" + interactive.Outcome.Height +
                " cancel=" + run.IsCancelRequested);
            if (interactiveIsFinal ||
                interactive.Outcome.Kind != DevelopExportOutcomeKind.Completed)
            {
                return interactive;
            }

            // 이미 더 새 요청이 있으면 이 장(옛 노출·옛 사진)을 화면에 올리지 않습니다.
            // 올리면 마지막 값이 한 박자 늦게 오거나, 정착이 그 위에 덮어 안 바뀐 것처럼 보입니다.
            lock (gate)
            {
                if (pending is not null)
                {
                    PreviewTrace.Write("RenderAsync skip stale pending rev=" + revision);
                    ReleaseLease(interactive.Lease);
                    return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
                }
            }

            // ☠️ 인터랙티브를 **여기서 곧바로 배달합니다.** macOS 도 인터랙티브 패스가
            //    끝나면 그 자리에서 `frame.developedImage` 를 갈아 끼웁니다
            //    (`AppModel+DevelopRendering.swift:81-84`). 앞 판은 결과를 하나만
            //    돌려줬기 때문에, 손을 멈춰 정착이 성립하면 인터랙티브 그림은 버려지고
            //    정착본이 나올 때까지(이 기계 3600 에서 약 300 ms) 화면이 옛 그림이었습니다.
            Deliver(interactive, request.OnCompleted);

            if (!await WaitForSettleAsync(revision, run).ConfigureAwait(false))
            {
                // 이미 배달했습니다. 다시 돌려주면 같은 그림을 두 번 그립니다.
                return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
            }

            uint settled = DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension);
            lock (gate)
            {
                if (pending is not null || developRevision != revision || run.IsCancelRequested)
                {
                    return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
                }
                activeRunIsSettled = true;
            }
            // 정착이 끊겼으면 화면에는 이미 인터랙티브가 올라가 있습니다. 그것을 다시
            // 배달할 이유가 없습니다.
            return await PreviewOnceAsync(
                developRequest,
                frame.Id,
                settled,
                settled,
                run,
                proof,
                clippingOverlay,
                settled: true,
                revision: revision).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            // 취소는 예외가 아니라 다음 요청이 이겼다는 뜻입니다. 여기서 던지면
            // RunLoop 가 pending 을 지워 마지막 미리보기가 화면에 안 남습니다.
            return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
        }
        catch (Exception error)
        {
            PreviewTrace.Write("RenderAsync fault rev=" + revision + " " + error);
            return new LeasedOutcome(
                PreviewOutcome.Faulted(error.Message ?? error.GetType().Name, revision),
                -1);
        }
    }

    /// <summary>
    /// macOS <c>interactiveProxyDimension(displayTargetPixels:)</c> 그대로입니다.
    /// </summary>
    /// <remarks>
    /// ☠️ 한때 여기서 실측 처리량으로 상자를 접었습니다. 속도는 붙었지만 **끄는 동안 그림이
    /// 뭉개져 보였고**, 사용자가 그것을 바로 잡아냈습니다. 해상도를 깎아 얻는 속도는 답이
    /// 아닙니다 — 캔버스가 쓰는 디바이스 픽셀 그대로 그리고, 속도는 파이프라인에서 냅니다.
    /// </remarks>
    private uint InteractiveEdge()
    {
        // 두 번째 렌더는 RunLoop 가 워커에서 이어집니다. 캔버스 ActualWidth 를
        // 그 스레드에서 읽으면 WinUI 가 던지고, 성공한 첫 장을 skip stale 한 뒤
        // 빈 Faulted 가 화면에 남았습니다(preview-trace 실측).
        double display = DevelopPreviewProxy.InteractiveMaxDimension;
        if (displayTargetPixels is not null && dispatcher.HasThreadAccess)
        {
            display = displayTargetPixels();
        }
        return DevelopPreviewProxy.BufferEdge(
            DevelopPreviewProxy.InteractiveProxyDimension(display));
    }

    /// <summary>macOS <c>waitForDevelopSettle</c> — 0.14초 동안 새 요청이 없으면 true.</summary>
    private async Task<bool> WaitForSettleAsync(int revision, DevelopRun run)
    {
        DateTime deadline = DateTime.UtcNow + DevelopPreviewProxy.SettleWindow;
        while (DateTime.UtcNow < deadline)
        {
            if (run.IsCancelRequested)
            {
                return false;
            }

            lock (gate)
            {
                if (pending is not null || developRevision != revision)
                {
                    return false;
                }
            }

            try
            {
                await Task.Delay(25).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return false;
            }
        }

        lock (gate)
        {
            return pending is null && developRevision == revision && !run.IsCancelRequested;
        }
    }

    private async Task<LeasedOutcome> PreviewOnceAsync(
        DevelopExportRequest developRequest,
        string frameId,
        uint width,
        uint height,
        DevelopRun run,
        SoftProofSettings? proof,
        bool clippingOverlay,
        bool settled,
        int revision)
    {
        // 배달된 버퍼는 UI 스레드가 다 쓸 때까지 임대 중입니다. 여기서 기다리는 것이
        // "그리는 화소"와 "배달한 리비전"이 어긋나지 않게 하는 유일한 방법입니다.
        int lease = bufferIndex;
        bufferIndex ^= 1;
        await bufferLeases[lease].WaitAsync().ConfigureAwait(false);
        byte[] pixels = buffers[lease];
        DevelopExportResult result;
        try
        {
            PreviewTrace.Write(
                "PreviewOnce start frame=" + frameId +
                " " + width + "x" + height +
                " settled=" + settled +
                " rev=" + revision);
            System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
            result = await Task.Run(() => exporter.Preview(
                developRequest,
                width,
                height,
                pixels,
                run,
                proof,
                clippingOverlay)).ConfigureAwait(false);
            PreviewTrace.Write(
                "PreviewOnce end ok=" + result.Succeeded +
                " cancel=" + result.Cancelled +
                " fail=" + (result.FailureName ?? "") +
                " w=" + result.ImageWidth +
                " h=" + result.ImageHeight +
                " ms=" + clock.ElapsedMilliseconds);
        }
        catch
        {
            ReleaseLease(lease);
            throw;
        }
        if (result.Cancelled || run.IsCancelRequested)
        {
            ReleaseLease(lease);
            return new LeasedOutcome(PreviewOutcome.Cancelled(), -1);
        }
        if (!result.Succeeded)
        {
            ReleaseLease(lease);
            return new LeasedOutcome(
                PreviewOutcome.Faulted(result.FailureName ?? "preview_failed", revision) with { FrameId = frameId },
                -1);
        }

        return new LeasedOutcome(
            new PreviewOutcome(
                DevelopExportOutcomeKind.Completed,
                pixels,
                result.ImageWidth,
                result.ImageHeight,
                result,
                DevelopRequestRefusal.None,
                null,
                settled,
                revision,
                frameId),
            lease);
    }

    private void ReleaseLease(int lease)
    {
        if (lease >= 0)
        {
            bufferLeases[lease].Release();
        }
    }

    private void Deliver(LeasedOutcome leased, Action<PreviewOutcome> onCompleted)
    {
        if (dispatcher.HasThreadAccess)
        {
            try
            {
                onCompleted(leased.Outcome);
            }
            finally
            {
                ReleaseLease(leased.Lease);
            }
            return;
        }
        // 배달에 실패해도 루프는 계속 정리됩니다. 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다.
        // 임대는 **어느 쪽이든 반드시** 돌려줍니다 — 안 돌려주면 다음 렌더가 영영 멈춥니다.
        if (!dispatcher.TryEnqueue(() =>
            {
                try
                {
                    onCompleted(leased.Outcome);
                }
                finally
                {
                    ReleaseLease(leased.Lease);
                }
            }))
        {
            ReleaseLease(leased.Lease);
        }
    }
}
