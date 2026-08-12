using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

public enum AutoAdjustOperation
{
    Tone,
    WhiteBalance,
    All,
}

public sealed record AutoAdjustOutcome(
    DevelopExportOutcomeKind Kind,
    LibraryFrameSnapshot? Frame,
    AutoAdjustSettings? Settings,
    DevelopRequestRefusal Refusal,
    string? FaultMessage)
{
    internal static AutoAdjustOutcome Refused(DevelopRequestRefusal refusal) =>
        new(DevelopExportOutcomeKind.Refused, null, null, refusal, null);

    internal static AutoAdjustOutcome Faulted(string message) =>
        new(DevelopExportOutcomeKind.Faulted, null, null, DevelopRequestRefusal.None, message);
}

/// <summary>
/// 자동 보정 한 번입니다. 중립 현상본을 렌더해 통계를 재고, 나온 값을 frame 에 **대입한**
/// 사본을 돌려줍니다.
/// </summary>
/// <remarks>
/// <para>
/// 핵심은 <b>중립 현상본</b>입니다. 이미 보정이 들어간 그림을 재면 그 위에 보정을 또 얹는 값이
/// 나오고, 버튼을 누를 때마다 결과가 흘러갑니다. 그래서 톤과 ColorModel 의 warmth/tint 를 0 으로
/// 되돌린 사본으로 렌더한 뒤, 그 결과를 원래 frame 에 대입합니다 — 누적이 아니라 대입이라
/// 두 번 눌러도 한 번 누른 것과 같습니다.
/// </para>
/// <para>
/// 필름 base 와 나머지 recipe 는 그대로 둡니다. 자동 보정이 고치려는 것은 톤과 화이트밸런스이지
/// base 추정이 아닙니다.
/// </para>
/// </remarks>
public sealed class AutoAdjustCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly uint sampleExtent;
    private readonly byte[] pixels;

    public AutoAdjustCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        uint sampleExtent = 512U)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentOutOfRangeException.ThrowIfZero(sampleExtent);

        this.exporter = exporter;
        this.dispatcher = dispatcher;
        this.sampleExtent = sampleExtent;
        pixels = new byte[(long)sampleExtent * sampleExtent * 4];
    }

    /// <summary>
    /// 톤과 화이트밸런스를 0 으로 되돌린 사본입니다. 자동 보정이 재야 하는 것은 이 그림입니다.
    /// </summary>
    internal static LibraryFrameSnapshot Neutralise(LibraryFrameSnapshot frame) =>
        frame with
        {
            Tone = ToneAdjustment.Neutral,
            ColorModel = frame.ColorModel with { Warmth = 0.0, Tint = 0.0 },
        };

    internal static LibraryFrameSnapshot NeutraliseTone(LibraryFrameSnapshot frame) =>
        frame with
        {
            Tone = ToneAdjustment.Neutral,
            ColorModel = frame.ColorModel with { ColorDepth = 0.0, Vibrance = 0.0, Saturation = 0.0 },
        };

    internal static LibraryFrameSnapshot NeutraliseWhiteBalance(LibraryFrameSnapshot frame) =>
        frame with { ColorModel = frame.ColorModel with { Warmth = 0.0, Tint = 0.0 } };

    /// <summary>
    /// 계산한 값을 대입한 사본입니다. 나머지 recipe 는 건드리지 않습니다.
    /// </summary>
    internal static LibraryFrameSnapshot Apply(
        LibraryFrameSnapshot frame,
        AutoAdjustSettings settings) =>
        frame with
        {
            Tone = frame.Tone with
            {
                Exposure = settings.Exposure,
                Contrast = settings.Contrast,
                Highlight = settings.Highlights,
                Shadow = settings.Shadows,
                Whites = settings.Whites,
                Blacks = settings.Blacks,
                Density = settings.Density,
            },
            ColorModel = frame.ColorModel with
            {
                Warmth = settings.Warmth,
                Tint = settings.Tint,
                Vibrance = settings.Vibrance,
            },
        };

    internal static LibraryFrameSnapshot ApplyTone(
        LibraryFrameSnapshot frame,
        AutoAdjustSettings settings) =>
        frame with
        {
            Tone = frame.Tone with
            {
                Exposure = settings.Exposure,
                Contrast = settings.Contrast,
                Highlight = settings.Highlights,
                Shadow = settings.Shadows,
                Whites = settings.Whites,
                Blacks = settings.Blacks,
                Density = settings.Density,
            },
            ColorModel = frame.ColorModel with
            {
                Vibrance = settings.Vibrance,
                Saturation = 0.0,
            },
        };

    internal static LibraryFrameSnapshot ApplyWhiteBalance(
        LibraryFrameSnapshot frame,
        AutoAdjustSettings settings) =>
        frame with
        {
            ColorModel = frame.ColorModel with
            {
                Warmth = settings.Warmth,
                Tint = settings.Tint,
            },
        };

    /// <summary>
    /// 결과는 항상 dispatcher 를 거쳐 돌아옵니다 — 거부와 예외도 같은 길입니다.
    /// </summary>
    public async Task<bool> RunAsync(
        LibraryFrameSnapshot frame,
        Action<AutoAdjustOutcome> onCompleted)
        => await RunAsync(frame, AutoAdjustOperation.All, onCompleted).ConfigureAwait(false);

    public Task<bool> RunToneAsync(
        LibraryFrameSnapshot frame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(frame, AutoAdjustOperation.Tone, onCompleted);

    public Task<bool> RunWhiteBalanceAsync(
        LibraryFrameSnapshot frame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(frame, AutoAdjustOperation.WhiteBalance, onCompleted);

    private async Task<bool> RunAsync(
        LibraryFrameSnapshot frame,
        AutoAdjustOperation operation,
        Action<AutoAdjustOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(onCompleted);

        LibraryFrameSnapshot neutral = operation switch
        {
            AutoAdjustOperation.Tone => NeutraliseTone(frame),
            AutoAdjustOperation.WhiteBalance => NeutraliseWhiteBalance(frame),
            _ => Neutralise(frame),
        };
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다.
        string unusedDestination = Path.ChangeExtension(frame.SourcePath, ".auto.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(neutral, unusedDestination);
        if (built.Request is not { } request)
        {
            return Deliver(AutoAdjustOutcome.Refused(built.Refusal), onCompleted);
        }

        try
        {
            // No soft proof. Automatic adjustment measures the develop, not a simulation of
            // what some printer would make of it; proofing the input would bake the paper's
            // dimness and cast into the tone and white balance it proposes.
            DevelopExportResult render = await Task.Run(() => exporter.Preview(
                request,
                sampleExtent,
                sampleExtent,
                pixels)).ConfigureAwait(false);
            if (!render.Succeeded)
            {
                return Deliver(
                    AutoAdjustOutcome.Faulted(
                        $"The neutral develop failed at {render.FailedStage}: {render.FailureName}."),
                    onCompleted);
            }

            AutoAdjustSettings settings = NativeAutoAdjust.Compute(
                pixels,
                render.ImageWidth,
                render.ImageHeight);
            LibraryFrameSnapshot applied = operation switch
            {
                AutoAdjustOperation.Tone => ApplyTone(frame, settings),
                AutoAdjustOperation.WhiteBalance => ApplyWhiteBalance(frame, settings),
                _ => Apply(frame, settings),
            };
            return Deliver(
                new AutoAdjustOutcome(
                    DevelopExportOutcomeKind.Completed,
                    applied,
                    settings,
                    DevelopRequestRefusal.None,
                    null),
                onCompleted);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            return Deliver(AutoAdjustOutcome.Faulted(error.Message), onCompleted);
        }
    }

    private bool Deliver(AutoAdjustOutcome outcome, Action<AutoAdjustOutcome> onCompleted)
    {
        if (dispatcher.HasThreadAccess)
        {
            onCompleted(outcome);
            return true;
        }
        return dispatcher.TryEnqueue(() => onCompleted(outcome));
    }
}
