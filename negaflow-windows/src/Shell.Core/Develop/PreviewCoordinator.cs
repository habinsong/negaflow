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
}

/// <summary>
/// 미리보기 렌더입니다. Export 와 같은 스레딩 규칙을 따르되, 하나 더 있습니다 —
/// **마지막 요청은 반드시 그려집니다.**
/// </summary>
/// <remarks>
/// 슬라이더는 한 번 움직이는 동안 요청을 여러 번 만듭니다. 도착하는 대로 다 그리면 엔진이
/// 밀리고, 돌고 있을 때 그냥 버리면 마지막 상태가 화면에 안 나타나 사용자가 방금 한 조작이
/// 사라진 것처럼 보입니다. 그래서 진행 중이면 **가장 최근 요청 하나만** 대기시켰다가 끝난 뒤
/// 이어서 그립니다. 중간 요청은 버립니다 — 어차피 이미 지나간 상태입니다.
/// </remarks>
public sealed class PreviewCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly uint maximumWidth;
    private readonly uint maximumHeight;
    private readonly byte[] pixels;
    private readonly Lock gate = new();

    private bool isRunning;
    private PreviewRequest? pending;

    public PreviewCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        uint maximumWidth,
        uint maximumHeight)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);

        this.exporter = exporter;
        this.dispatcher = dispatcher;
        this.maximumWidth = maximumWidth;
        this.maximumHeight = maximumHeight;
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
    /// 렌더를 요청합니다. 이미 돌고 있으면 대기 자리에 넣고, 거기 있던 것은 버립니다. 반환되는
    /// Task 는 **이 호출이 실제로 렌더를 시작했을 때만** 그 렌더가 끝날 때까지 이어집니다.
    /// </summary>
    public Task RequestAsync(
        LibraryFrameSnapshot frame,
        Action<PreviewOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        lock (gate)
        {
            if (isRunning)
            {
                pending = new PreviewRequest(frame, onCompleted);
                return Task.CompletedTask;
            }
            isRunning = true;
        }
        return RunLoopAsync(new PreviewRequest(frame, onCompleted));
    }

    private async Task RunLoopAsync(PreviewRequest request)
    {
        PreviewRequest? current = request;
        try
        {
            while (current is not null)
            {
                Deliver(await RenderAsync(current.Frame).ConfigureAwait(false),
                    current.OnCompleted);
                lock (gate)
                {
                    current = pending;
                    pending = null;
                    if (current is null)
                    {
                        isRunning = false;
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
            }
            throw;
        }
    }

    private async Task<PreviewOutcome> RenderAsync(LibraryFrameSnapshot frame)
    {
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다. 네이티브가 무시하는
        // 자리이므로 frame 옆의 이름을 넣어 두고, 실제로는 아무것도 만들어지지 않습니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".preview.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } developRequest)
        {
            return PreviewOutcome.Refused(built.Refusal);
        }

        try
        {
            DevelopExportResult result = await Task.Run(() => exporter.Preview(
                developRequest,
                maximumWidth,
                maximumHeight,
                pixels)).ConfigureAwait(false);
            return new PreviewOutcome(
                DevelopExportOutcomeKind.Completed,
                result.Succeeded ? pixels : null,
                result.ImageWidth,
                result.ImageHeight,
                result,
                DevelopRequestRefusal.None,
                null);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return PreviewOutcome.Faulted(error.Message);
        }
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
