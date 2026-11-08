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
/// 계산값을 frame의 나머지 설정과 함께 다시 그려 노출과 화이트 후보를 구합니다. 확인 렌더는 중립
/// 현상본과 칸마다 맞대어 새로 날아간 채널을 셉니다. 후보도 렌더해, 채널 한도를 넘는 양이 적은 쪽을
/// 먼저 고르고 같으면 톤 점수가 좋아질 때만 채택합니다. 고른 결과에서도 한도를 넘으면 밝히는 몫을
/// 실제로 그려 이분합니다(최대 3 회). 색 조정은 유지합니다.
/// 결정적이라 같은 frame 이면 같은 답입니다.
/// </para>
/// </remarks>
public sealed class AutoAdjustCoordinator
{
    private readonly IDevelopExporter exporter;
    private readonly IUiDispatcher dispatcher;
    private readonly uint sampleExtent;
    private readonly Func<byte[], uint, uint, bool, AutoAdjustSettings> compute;
    private readonly Func<ToneBitmap, ToneBitmap, bool, AutoAdjustSettings, AutoAdjustSettings> refine;
    private readonly Func<byte[], uint, uint, bool, double> quality;
    private readonly Func<ToneBitmap, ToneBitmap, double?> channelExcess;
    private readonly Func<ToneBitmap, bool, AutoAdjustSettings, (double ExposureFloor, double KeyBudgetStops)> channelLimits;
    private readonly Func<ToneBitmap, double> sceneKey;
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
            (neutral, measured, monochrome, first) => NativeAutoAdjust.Refine(
                neutral.Pixels, neutral.Width, neutral.Height, measured.Pixels, measured.Width, measured.Height,
                monochrome, first),
            (pixels, width, height, adjustMid) => NativeAutoAdjust.ToneScore(pixels, width, height, adjustMid),
            (neutral, measured) => NativeAutoAdjust.ChannelExcess(
                neutral.Pixels, neutral.Width, neutral.Height, measured.Pixels, measured.Width, measured.Height),
            (neutral, monochrome, first) => NativeAutoAdjust.ChannelLimits(
                neutral.Pixels, neutral.Width, neutral.Height, monochrome, first.Exposure),
            bitmap => NativeAutoAdjust.SceneKey(bitmap.Pixels, bitmap.Width, bitmap.Height)) { }

    /// <summary>계산만 바꿔 끼우는 시험용입니다. 폐루프 보정은 첫 값을 그대로 돌려줍니다.</summary>
    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, AutoAdjustSettings> compute)
        : this(exporter, dispatcher, sampleExtent,
            (pixels, width, height, _) => compute(pixels, width, height),
            (_, _, _, _, first) => first) { }

    /// <summary>폐루프 보정이 확인 렌더만 보는 시험용입니다. 채널 한도는 걸지 않습니다.</summary>
    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, bool, AutoAdjustSettings> compute,
        Func<byte[], uint, uint, bool, AutoAdjustSettings, AutoAdjustSettings> refine,
        Func<byte[], uint, uint, bool, double>? quality = null)
        : this(exporter, dispatcher, sampleExtent, compute,
            (_, measured, monochrome, first) => refine(measured.Pixels, measured.Width, measured.Height, monochrome, first),
            quality ?? ((_, _, _, _) => 0),
            (_, _) => null) { }

    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, bool, AutoAdjustSettings> compute,
        Func<ToneBitmap, ToneBitmap, bool, AutoAdjustSettings, AutoAdjustSettings> refine,
        Func<byte[], uint, uint, bool, double> quality,
        Func<ToneBitmap, ToneBitmap, double?> channelExcess)
        : this(exporter, dispatcher, sampleExtent, compute, refine, quality, channelExcess,
            (_, _, _) => (double.NegativeInfinity, double.PositiveInfinity), _ => 1.0) { }

    internal AutoAdjustCoordinator(
        IDevelopExporter exporter, IUiDispatcher dispatcher, uint sampleExtent,
        Func<byte[], uint, uint, bool, AutoAdjustSettings> compute,
        Func<ToneBitmap, ToneBitmap, bool, AutoAdjustSettings, AutoAdjustSettings> refine,
        Func<byte[], uint, uint, bool, double> quality,
        Func<ToneBitmap, ToneBitmap, double?> channelExcess,
        Func<ToneBitmap, bool, AutoAdjustSettings, (double ExposureFloor, double KeyBudgetStops)> channelLimits,
        Func<ToneBitmap, double> sceneKey)
    {
        ArgumentNullException.ThrowIfNull(exporter);
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentOutOfRangeException.ThrowIfZero(sampleExtent);
        ArgumentNullException.ThrowIfNull(compute);
        ArgumentNullException.ThrowIfNull(refine);
        ArgumentNullException.ThrowIfNull(quality);
        ArgumentNullException.ThrowIfNull(channelExcess);
        ArgumentNullException.ThrowIfNull(channelLimits);
        ArgumentNullException.ThrowIfNull(sceneKey);

        this.exporter = exporter;
        this.dispatcher = dispatcher;
        this.sampleExtent = sampleExtent;
        this.compute = compute;
        this.refine = refine;
        this.quality = quality;
        this.channelExcess = channelExcess;
        this.channelLimits = channelLimits;
        this.sceneKey = sceneKey;
    }

    /// <summary>측정 렌더 한 장(BGRA8)입니다.</summary>
    internal readonly record struct ToneBitmap(byte[] Pixels, uint Width, uint Height);

    // 채널 한도가 폐루프 뒤에도 넘칠 때 더 그려 보는 최대 횟수(macOS `AutoAdjust.channelRefinementLimit`).
    private const int ChannelRefinementLimit = 3;

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
        bool waits;
        lock (tailGate)
        {
            before = operation switch
            {
                AutoAdjustOperation.Tone => balanceTail,
                AutoAdjustOperation.WhiteBalance => toneTail,
                _ => Task.WhenAll(toneTail, balanceTail),
            };
            waits = !before.IsCompleted;
            if (operation != AutoAdjustOperation.WhiteBalance) { toneTail = settled.Task; }
            if (operation != AutoAdjustOperation.Tone) { balanceTail = settled.Task; }
        }
        bool handedOff = false;
        Interlocked.Increment(ref running);
        try
        {
            // 앞 요청의 꼬리는 그 완료 처리(대입)가 실제로 돈 뒤에 닫힙니다 — 그 대입이 끝난 프레임을 봅니다.
            await before;
            // 기다렸으면 macOS 처럼 지금을 기준으로 다시 잡습니다(`request = AutoAdjustRequest(frame)`).
            // 앞 결과를 반영하며 건 취소(그 결과의 미리보기 요청)에 이 요청이 버려지지 않습니다.
            if (waits) { generation = Volatile.Read(ref cancelGeneration); }
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
            LibraryFrameSnapshot Applied(AutoAdjustSettings proposal) => operation == AutoAdjustOperation.Tone
                ? ApplyTone(frame, proposal)
                : Apply(frame, proposal);
            LibraryFrameSnapshot verify = Applied(settings);
            Rendered verified = await RenderAsync(verify, frame.SourcePath, isCurrent).ConfigureAwait(false);
            if (verified.Pixels is not null)
            {
                // 중립 현상본과 칸마다 맞대어 새로 날아간 채널을 실제 결과(타깃·커브 포함)로 셉니다(macOS
                // `AutoAdjust.closedLoopTone` 과 같은 순서).
                ToneBitmap neutralBitmap = new(first.Pixels, first.Width, first.Height);
                ToneBitmap chosenBitmap = new(verified.Pixels, verified.Width, verified.Height);
                AutoAdjustSettings chosen = settings;
                ToneBitmap measuredBitmap = chosenBitmap;
                // 채널을 지키느라 어두워지는 몫의 바닥: 확인 렌더의 장면 키에서 남은 예산(1 스톱 − 첫 계산이 이미 내준
                // 노출)만큼 아래. 노출이 아니라 잰 키로 거는 것은 스캐너 타깃의 톤 곡선이 노출 변화를 키워서입니다.
                (double exposureFloor, double keyBudget) = channelLimits(neutralBitmap, monochrome, settings);
                double keyFloor = sceneKey(measuredBitmap) * Math.Pow(2, -keyBudget);
                AutoAdjustSettings candidate = refine(neutralBitmap, chosenBitmap, monochrome, settings);
                if (RefinementDistance(settings, candidate) > 0.02)
                {
                    Rendered checkedRender = await RenderAsync(Applied(candidate), frame.SourcePath, isCurrent).ConfigureAwait(false);
                    if (checkedRender.Pixels is not null)
                    {
                        ToneBitmap checkedBitmap = new(checkedRender.Pixels, checkedRender.Width, checkedRender.Height);
                        if (channelExcess(neutralBitmap, measuredBitmap) is 0.0 &&
                            channelExcess(neutralBitmap, checkedBitmap) is > 0)
                        {
                            // 더 밝힌 후보가 한도를 넘었습니다 — 첫 제안(맞음)과 후보 사이를 그려 맞는 가장 밝은 점을 찾고,
                            // 그 점을 점수로 첫 제안과 견줍니다.
                            Bisection? raised = await BisectChannelsAsync(
                                settings, candidate, checkedBitmap, neutralBitmap, keyFloor, Applied, frame.SourcePath,
                                isCurrent).ConfigureAwait(false);
                            if (raised is null) { return null; }
                            if (raised.Value.Fit is { } inside &&
                                quality(inside.Bitmap.Pixels, inside.Bitmap.Width, inside.Bitmap.Height, true) <
                                quality(measuredBitmap.Pixels, measuredBitmap.Width, measuredBitmap.Height, true))
                            {
                                chosen = inside.Settings;
                                chosenBitmap = inside.Bitmap;
                            }
                        }
                        else if (sceneKey(checkedBitmap) >= keyFloor && Prefers(neutralBitmap, checkedBitmap, chosenBitmap))
                        {
                            chosen = candidate;
                            chosenBitmap = checkedBitmap;
                        }
                    }
                    else if (checkedRender.Outcome is null) { return null; }
                }
                // 고른 결과에서도 새로 날아간 채널이 한도를 넘으면, 고른 제안과 그 바닥(흰색의 밝히는 몫을 빼고 노출은
                // 채널 한도의 바닥까지) 사이를 그려 이분해 맞는 가장 밝은 점을 씁니다. 맞는 점이 없으면 초과가 가장 적은
                // 점입니다.
                if (channelExcess(neutralBitmap, chosenBitmap) is > 0)
                {
                    // 노출은 채널 한도의 바닥(채널을 보지 않고 푼 노출 − 1 스톱)까지만 내립니다 — 그 아래는 클리핑을
                    // 받아들입니다(macOS `AutoAdjust.channelExposureBudget`).
                    double floor = Math.Min(chosen.Exposure, Math.Max(Math.Min(chosen.Exposure, 0), exposureFloor));
                    AutoAdjustSettings bottom = WithExposureAndWhites(chosen, floor, Math.Min(chosen.Whites, 0));
                    if (RefinementDistance(chosen, bottom) > 0.005)
                    {
                        Bisection? lowered = await BisectChannelsAsync(
                            bottom, chosen, chosenBitmap, neutralBitmap, keyFloor, Applied, frame.SourcePath, isCurrent)
                            .ConfigureAwait(false);
                        if (lowered is null) { return null; }
                        chosen = lowered.Value.Fit?.Settings ?? lowered.Value.Least.Settings;
                    }
                }
                settings = chosen;
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

    private readonly record struct Measured(AutoAdjustSettings Settings, ToneBitmap Bitmap);

    private readonly record struct Bisection(Measured? Fit, Measured Least);

    /// <summary>
    /// <paramref name="fitting"/>(맞는다고 보는 끝)에서 <paramref name="exceeding"/>(넘친다고 잰 끝)으로 가는 노출·흰색
    /// 선분을 그려 이분합니다(최대 3 회). 장면 키가 <paramref name="keyFloor"/> 보다 어두운 점은 너무 어두운 것으로 보고 더
    /// 밝은 쪽을 찾습니다. <c>Fit</c> 은 맞는 가장 밝은 점, <c>Least</c> 는 키 바닥을 지킨 잰 점 가운데 가장 나은 점입니다
    /// (macOS <c>AutoAdjust.bisectChannels</c>). 더 새 요청에 밀렸으면 <see langword="null"/> 입니다.
    /// </summary>
    private async Task<Bisection?> BisectChannelsAsync(
        AutoAdjustSettings fitting, AutoAdjustSettings exceeding, ToneBitmap exceedingBitmap, ToneBitmap neutral,
        double keyFloor, Func<AutoAdjustSettings, LibraryFrameSnapshot> applied, string sourcePath, Func<bool> isCurrent)
    {
        double low = 0, high = 1;
        Measured? fit = null;
        Measured least = new(exceeding, exceedingBitmap);
        for (int round = 0; round < ChannelRefinementLimit; ++round)
        {
            double t = 0.5 * (low + high);
            AutoAdjustSettings trial = WithExposureAndWhites(
                exceeding,
                fitting.Exposure + ((exceeding.Exposure - fitting.Exposure) * t),
                fitting.Whites + ((exceeding.Whites - fitting.Whites) * t));
            Rendered render = await RenderAsync(applied(trial), sourcePath, isCurrent).ConfigureAwait(false);
            if (render.Pixels is null)
            {
                if (render.Outcome is null) { return null; }
                break;
            }
            ToneBitmap bitmap = new(render.Pixels, render.Width, render.Height);
            if (sceneKey(bitmap) < keyFloor)
            {
                low = t;   // 장면 키가 바닥보다 어둡습니다 — 더 밝은 쪽을 찾습니다.
            }
            else if (channelExcess(neutral, bitmap) is 0.0)
            {
                low = t;
                fit = new Measured(trial, bitmap);
            }
            else
            {
                high = t;
                if (Prefers(neutral, bitmap, least.Bitmap)) { least = new Measured(trial, bitmap); }
            }
        }
        return new Bisection(fit, least);
    }

    /// <summary>
    /// 확인 렌더 둘 중 후보를 받을지입니다. 새로 날아간 채널이 한도를 넘는 양이 적은 쪽이 낫고, 같으면 톤 점수가
    /// 정합니다(macOS <c>AutoAdjust.prefersCandidate</c>). 노출은 양방향으로 장면 키를 맞추므로 중간(로그 평균)
    /// 오차를 늘 봅니다.
    /// </summary>
    private bool Prefers(ToneBitmap neutral, ToneBitmap candidate, ToneBitmap current)
    {
        if (channelExcess(neutral, current) is { } excessNow && channelExcess(neutral, candidate) is { } excessCandidate &&
            Math.Abs(excessNow - excessCandidate) > 1e-9)
        {
            return excessCandidate < excessNow;
        }
        return quality(candidate.Pixels, candidate.Width, candidate.Height, true) <
               quality(current.Pixels, current.Width, current.Height, true);
    }

    private static AutoAdjustSettings WithExposureAndWhites(AutoAdjustSettings source, double exposure, double whites) =>
        new(exposure, source.Contrast, source.Highlights, source.Shadows, whites, source.Blacks, source.Density,
            source.Vibrance, source.Warmth, source.Tint);

    private static double RefinementDistance(AutoAdjustSettings first, AutoAdjustSettings second) =>
        Math.Abs(first.Exposure - second.Exposure) + 0.5 * Math.Abs(first.Whites - second.Whites);

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
