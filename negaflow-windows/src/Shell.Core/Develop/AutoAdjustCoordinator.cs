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
/// <para>
/// 자동 톤은 <b>폐루프</b>입니다(macOS <c>AppModel.autoTone</c>). 첫 계산은 슬라이더 전달함수를
/// 모형으로 거꾸로 풀지만 사용자 커브·색 깊이·스캐너 타깃과의 상호작용은 모형 밖입니다. 그래서
/// 계산값을 frame 의 나머지 설정과 함께 한 번 더 그려 다시 재고, 노출과 화이트를 한 번 바로잡습니다.
/// 결정적이라 같은 frame 이면 같은 답입니다.
/// </para>
/// </remarks>
public sealed class AutoAdjustCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly uint sampleExtent;
    private readonly Func<byte[], uint, uint, bool, AutoAdjustSettings> compute;
    private readonly Func<byte[], uint, uint, bool, AutoAdjustSettings, AutoAdjustSettings> refine;
    // 요청 종류마다 따로 셉니다. 같은 종류의 새 요청만 앞 요청을 대체합니다 — 자동 톤을 누른 뒤
    // 자동 화이트밸런스를 누르면 둘 다 반영돼야 합니다(예전: 공유 리비전이라 톤 결과가 버려졌다).
    // 다른 종류는 앞 요청이 반영된 뒤 그 값 위에서 잽니다 — 자동 WB 의 측정은 톤에 따라 달라지므로
    // (macOS 실측 warmth 0.13 vs 0.20) 순서대로 누른 것과 같은 값이 되려면 이어서 돌아야 합니다.
    private readonly long[] revisions = new long[3];
    private readonly object tailGate = new();
    private Task toneTail = Task.CompletedTask;
    private Task balanceTail = Task.CompletedTask;
    private long cancelGeneration;
    private int running;

    public bool IsRunning => Volatile.Read(ref running) != 0;
    public void Cancel() => Interlocked.Increment(ref cancelGeneration);

    public AutoAdjustCoordinator(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        uint sampleExtent = 512U)
        : this(exporter, dispatcher, sampleExtent,
            (pixels, width, height, monochrome) => NativeAutoAdjust.Compute(pixels, width, height, monochrome),
            (pixels, width, height, monochrome, first) =>
                NativeAutoAdjust.Refine(pixels, width, height, monochrome, first)) { }

    /// <summary>계산만 바꿔 끼우는 시험용입니다. 폐루프 보정은 첫 값을 그대로 돌려줍니다.</summary>
    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, AutoAdjustSettings> compute)
        : this(exporter, dispatcher, sampleExtent,
            (pixels, width, height, _) => compute(pixels, width, height),
            (_, _, _, _, first) => first) { }

    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, bool, AutoAdjustSettings> compute,
        Func<byte[], uint, uint, bool, AutoAdjustSettings, AutoAdjustSettings> refine)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentOutOfRangeException.ThrowIfZero(sampleExtent);
        ArgumentNullException.ThrowIfNull(compute);
        ArgumentNullException.ThrowIfNull(refine);

        this.exporter = exporter;
        this.dispatcher = dispatcher;
        this.sampleExtent = sampleExtent;
        this.compute = compute;
        this.refine = refine;
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
            // 채도는 대입하지 않습니다 — 자동 톤은 채도를 계산하지 않으므로 대입하면 사용자 값을
            // 조용히 0 으로 지웁니다(macOS `AppModel.applying` 과 같습니다).
            ColorModel = frame.ColorModel with
            {
                Vibrance = settings.Vibrance,
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
        => await RunAsync(Fixed(frame), AutoAdjustOperation.All, onCompleted).ConfigureAwait(false);

    public Task<bool> RunToneAsync(
        LibraryFrameSnapshot frame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(Fixed(frame), AutoAdjustOperation.Tone, onCompleted);

    public Task<bool> RunWhiteBalanceAsync(
        LibraryFrameSnapshot frame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(Fixed(frame), AutoAdjustOperation.WhiteBalance, onCompleted);

    /// <summary>
    /// 시작할 때 지금 프레임을 읽습니다 — 앞서 누른 다른 종류의 결과가 반영된 프레임입니다.
    /// </summary>
    public Task<bool> RunToneAsync(
        Func<LibraryFrameSnapshot?> currentFrame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(currentFrame, AutoAdjustOperation.Tone, onCompleted);

    public Task<bool> RunWhiteBalanceAsync(
        Func<LibraryFrameSnapshot?> currentFrame,
        Action<AutoAdjustOutcome> onCompleted) =>
        RunAsync(currentFrame, AutoAdjustOperation.WhiteBalance, onCompleted);

    private static Func<LibraryFrameSnapshot?> Fixed(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return () => frame;
    }

    private async Task<bool> RunAsync(
        Func<LibraryFrameSnapshot?> currentFrame,
        AutoAdjustOperation operation,
        Action<AutoAdjustOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(currentFrame);
        ArgumentNullException.ThrowIfNull(onCompleted);
        long requestRevision = Interlocked.Increment(ref revisions[(int)operation]);
        long generation = Volatile.Read(ref cancelGeneration);
        bool IsCurrent() =>
            requestRevision == Volatile.Read(ref revisions[(int)operation]) &&
            generation == Volatile.Read(ref cancelGeneration);
        var settled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task before;
        lock (tailGate)
        {
            before = operation switch
            {
                AutoAdjustOperation.Tone => balanceTail,
                AutoAdjustOperation.WhiteBalance => toneTail,
                _ => Task.WhenAll(toneTail, balanceTail),
            };
            if (operation != AutoAdjustOperation.WhiteBalance) { toneTail = settled.Task; }
            if (operation != AutoAdjustOperation.Tone) { balanceTail = settled.Task; }
        }
        bool handedOff = false;
        Interlocked.Increment(ref running);
        try
        {
            // 앞 요청의 꼬리는 그 완료 처리(대입)가 실제로 돈 뒤에 닫힙니다 — 그 대입이 끝난 프레임을 봅니다.
            await before;
            if (!IsCurrent() || currentFrame() is not { } frame) { return true; }
            AutoAdjustOutcome? outcome;
            try { outcome = await MeasureAsync(frame, operation, IsCurrent).ConfigureAwait(false); }
            catch (OperationCanceledException)
            {
                outcome = new AutoAdjustOutcome(DevelopExportOutcomeKind.Cancelled, null, null,
                    DevelopRequestRefusal.None, null);
            }
            catch (Exception error) { outcome = AutoAdjustOutcome.Faulted(error.Message); }
            // UI 콜백 예외를 측정 실패로 다시 전달하면 같은 완료 처리가 두 번 실행됩니다.
            if (outcome is null) { return true; }
            handedOff = true;
            return Deliver(outcome, onCompleted, IsCurrent, settled);
        }
        finally
        {
            if (!handedOff) { settled.TrySetResult(); }
            Interlocked.Decrement(ref running);
        }
    }

    private async Task<AutoAdjustOutcome?> MeasureAsync(
        LibraryFrameSnapshot frame, AutoAdjustOperation operation, Func<bool> isCurrent)
    {
        LibraryFrameSnapshot neutral = operation switch
        {
            AutoAdjustOperation.Tone => NeutraliseTone(frame),
            AutoAdjustOperation.WhiteBalance => NeutraliseWhiteBalance(frame),
            _ => Neutralise(frame),
        };
        // 노출 숄더의 헤드룸이 흑백 네거티브만 다릅니다(현상 단계와 같은 판정).
        bool monochrome = frame.Route.FilmType == FilmType.BlackAndWhiteNegative;
        Rendered first = await RenderAsync(neutral, frame.SourcePath, isCurrent).ConfigureAwait(false);
        if (first.Outcome is not null || first.Pixels is null) { return first.Outcome; }

        AutoAdjustSettings settings = compute(first.Pixels, first.Width, first.Height, monochrome);
        if (operation != AutoAdjustOperation.WhiteBalance)
        {
            // 폐루프: 계산값을 frame 의 나머지 설정과 함께 실제로 그려 다시 재고 한 번 바로잡습니다.
            // 이 렌더가 실패하면 첫 값을 씁니다(macOS 와 같습니다) — 첫 값도 유효한 답입니다.
            LibraryFrameSnapshot verify = operation == AutoAdjustOperation.Tone
                ? ApplyTone(frame, settings)
                : Apply(frame, settings);
            Rendered verified = await RenderAsync(verify, frame.SourcePath, isCurrent).ConfigureAwait(false);
            if (verified.Pixels is not null)
            {
                settings = refine(verified.Pixels, verified.Width, verified.Height, monochrome, settings);
            }
            else if (verified.Outcome is null)
            {
                return null;   // 더 새 요청에 밀렸습니다.
            }
        }
        LibraryFrameSnapshot applied = operation switch
        {
            AutoAdjustOperation.Tone => ApplyTone(frame, settings),
            AutoAdjustOperation.WhiteBalance => ApplyWhiteBalance(frame, settings),
            _ => Apply(frame, settings),
        };
        return new AutoAdjustOutcome(
            DevelopExportOutcomeKind.Completed,
            applied,
            settings,
            DevelopRequestRefusal.None,
            null);
    }

    /// <summary>한 번의 측정 렌더입니다. 화소가 있거나, 돌려줄 결과(거부·실패)가 있거나, 둘 다 없으면
    /// 더 새 요청에 밀린 것입니다.</summary>
    private readonly record struct Rendered(byte[]? Pixels, uint Width, uint Height, AutoAdjustOutcome? Outcome);

    private async Task<Rendered> RenderAsync(LibraryFrameSnapshot frame, string sourcePath, Func<bool> isCurrent)
    {
        // 미리보기는 파일을 쓰지 않지만 요청 팩토리는 목적지를 요구합니다.
        string unusedDestination = Path.ChangeExtension(sourcePath, ".auto.png");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, unusedDestination);
        if (built.Request is not { } request)
        {
            return new(null, 0, 0, AutoAdjustOutcome.Refused(built.Refusal));
        }

        // 새 감마/배율 요청이 겹쳐도 서로의 중립 렌더를 덮지 않습니다.
        byte[] pixels = new byte[checked((int)((long)sampleExtent * sampleExtent * 4))];
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
            return new(null, 0, 0, AutoAdjustOutcome.Faulted(
                $"The neutral develop failed at {render.FailedStage}: {render.FailureName}."));
        }

        if (!isCurrent()) { return default; }
        if (render.ImageWidth == 0 || render.ImageHeight == 0 ||
            render.ImageWidth > sampleExtent || render.ImageHeight > sampleExtent)
        {
            return new(null, 0, 0, AutoAdjustOutcome.Faulted("Invalid automatic adjustment preview dimensions."));
        }
        return new(pixels, render.ImageWidth, render.ImageHeight, null);
    }

    /// <param name="settled">완료 처리가 돈 뒤(또는 돌지 못하게 된 뒤) 닫는 이 요청의 꼬리입니다.</param>
    private bool Deliver(
        AutoAdjustOutcome outcome, Action<AutoAdjustOutcome> onCompleted, Func<bool> isCurrent,
        TaskCompletionSource settled)
    {
        void Complete()
        {
            try
            {
                if (isCurrent()) { onCompleted(outcome); }
            }
            finally
            {
                settled.TrySetResult();
            }
        }
        if (dispatcher.HasThreadAccess)
        {
            Complete();
            return true;
        }
        bool delivered = dispatcher.TryEnqueue(Complete);
        if (!delivered) { settled.TrySetResult(); }
        return delivered;
    }
}
