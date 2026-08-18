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
    string? FaultMessage)
{
    internal static PreviewOutcome Refused(DevelopRequestRefusal refusal) =>
        new(DevelopExportOutcomeKind.Refused, null, 0, 0, null, refusal, null);

    internal static PreviewOutcome Faulted(string message) =>
        new(DevelopExportOutcomeKind.Faulted, null, 0, 0, null,
            DevelopRequestRefusal.None, message);

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
    private readonly byte[] pixels;
    private readonly Lock gate = new();

    private readonly Func<double>? displayTargetPixels;
    private readonly bool settleEnabled;
    private int developRevision;

    private bool isRunning;
    private PreviewRequest? pending;
    // The handle for the render currently inside the engine. Held under the same lock as
    // `pending` so a request that queues itself also cancels what it just superseded.
    private DevelopRun? activeRun;
    // Set from the UI thread, read on a worker, so it goes under the same lock as
    // everything else here rather than acquiring its own rule.
    private SoftProofSettings? softProof;
    private bool clippingOverlayEnabled;

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
        pixels = new byte[(long)maximumWidth * maximumHeight * 4];
    }

    private sealed record PreviewRequest(
        LibraryFrameSnapshot Frame,
        Action<PreviewOutcome> OnCompleted);

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
        lock (gate)
        {
            if (isRunning)
            {
                pending = new PreviewRequest(frame, onCompleted);
                // Whatever is in the engine now is already stale. Cancelling is what turns
                // a queued request from "wait out a full render" into "start almost now".
                activeRun?.Cancel();
                return Task.CompletedTask;
            }
            isRunning = true;
            // Created here rather than inside the render so that `activeRun` is never null
            // while `isRunning` is true. Otherwise a request arriving in the gap between
            // the two would find nothing to cancel and sit through a whole stale render.
            run = new DevelopRun();
            activeRun = run;
        }
        return RunLoopAsync(new PreviewRequest(frame, onCompleted), run);
    }

    private async Task RunLoopAsync(PreviewRequest request, DevelopRun run)
    {
        PreviewRequest? current = request;
        DevelopRun currentRun = run;
        try
        {
            while (current is not null)
            {
                PreviewOutcome outcome;
                try
                {
                    outcome = await RenderAsync(current.Frame, currentRun)
                        .ConfigureAwait(false);
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
                if (outcome.Kind != DevelopExportOutcomeKind.Cancelled)
                {
                    Deliver(outcome, current.OnCompleted);
                }
                lock (gate)
                {
                    current = pending;
                    pending = null;
                    if (current is null)
                    {
                        isRunning = false;
                        activeRun = null;
                    }
                    else
                    {
                        currentRun = new DevelopRun();
                        activeRun = currentRun;
                    }
                }
            }
        }
        catch
        {
            lock (gate)
            {
                isRunning = false;
                pending = null;
                activeRun = null;
            }
            throw;
        }
    }

    private async Task<PreviewOutcome> RenderAsync(
        LibraryFrameSnapshot frame,
        DevelopRun run)
    {
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다. 네이티브가 무시하는
        // 자리이므로 frame 옆의 이름을 넣어 두고, 실제로는 아무것도 만들어지지 않습니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".preview.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } developRequest)
        {
            return PreviewOutcome.Refused(built.Refusal);
        }

        // Read once, here, so the whole render uses one proof state even if the property
        // changes while it is inside the engine. That render is superseded anyway.
        SoftProofSettings? proof = SoftProof;
        bool clippingOverlay = ClippingOverlayEnabled;

        try
        {
            uint interactiveEdge = InteractiveEdge();
            int revision = NextRevision();
            PreviewOutcome interactive = await PreviewOnceAsync(
                developRequest,
                interactiveEdge,
                interactiveEdge,
                run,
                proof,
                clippingOverlay).ConfigureAwait(false);
            if (!settleEnabled ||
                interactive.Kind != DevelopExportOutcomeKind.Completed ||
                interactiveEdge >= DevelopPreviewProxy.FullMaxDimension - 0.5)
            {
                return interactive;
            }

            if (!await WaitForSettleAsync(revision, run).ConfigureAwait(false))
            {
                return interactive;
            }

            uint settled = DevelopPreviewProxy.BufferEdge(DevelopPreviewProxy.FullMaxDimension);
            PreviewOutcome settledOutcome = await PreviewOnceAsync(
                developRequest,
                settled,
                settled,
                run,
                proof,
                clippingOverlay).ConfigureAwait(false);
            return settledOutcome.Kind == DevelopExportOutcomeKind.Cancelled
                ? interactive
                : settledOutcome;
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return PreviewOutcome.Faulted(error.Message);
        }
    }

    private uint InteractiveEdge()
    {
        double display = displayTargetPixels?.Invoke() ?? DevelopPreviewProxy.InteractiveMaxDimension;
        return DevelopPreviewProxy.BufferEdge(
            DevelopPreviewProxy.InteractiveProxyDimension(display));
    }

    private int NextRevision()
    {
        lock (gate)
        {
            return ++developRevision;
        }
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

    private async Task<PreviewOutcome> PreviewOnceAsync(
        DevelopExportRequest developRequest,
        uint width,
        uint height,
        DevelopRun run,
        SoftProofSettings? proof,
        bool clippingOverlay)
    {
        DevelopExportResult result = await Task.Run(() => exporter.Preview(
            developRequest,
            width,
            height,
            pixels,
            run,
            proof,
            clippingOverlay)).ConfigureAwait(false);
        if (result.Cancelled)
        {
            return PreviewOutcome.Cancelled();
        }

        return new PreviewOutcome(
            DevelopExportOutcomeKind.Completed,
            result.Succeeded ? pixels : null,
            result.ImageWidth,
            result.ImageHeight,
            result,
            DevelopRequestRefusal.None,
            null);
    }

    private void Deliver(PreviewOutcome outcome, Action<PreviewOutcome> onCompleted)
    {
        if (dispatcher.HasThreadAccess)
        {
            onCompleted(outcome);
            return;
        }
        // 배달에 실패해도 루프는 계속 정리됩니다. 큐가 닫혔다는 뜻이므로 창이 사라지는 중입니다.
        _ = dispatcher.TryEnqueue(() => onCompleted(outcome));
    }
}
