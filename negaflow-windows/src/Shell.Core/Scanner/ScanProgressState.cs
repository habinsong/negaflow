namespace Negaflow.Shell;

/// <summary>스캔이 지나가는 단계입니다. macOS <c>ScanPhase</c> 와 같은 차례·같은 이름입니다.</summary>
public enum ScanPhase
{
    Idle,
    Connecting,
    WarmingLamp,
    Ready,
    PreviewScanning,
    WaitingForFilmHolder,
    ScanningRGB,
    ScanningIR,
    ProcessingNegative,
    RenderingLook,
    Exporting,
    Complete,
    ScannerBusy,
    Disconnected,
    Error,
    BackendFallbackActive,
}

/// <summary>플러그인이 보내는 진행 한 줄입니다.</summary>
/// <param name="Phase">단계입니다.</param>
/// <param name="Fraction">0…1 입니다. 없으면 <see langword="null"/> 이고 단계에서 유추합니다.</param>
/// <param name="Message">오류 단계에서만 쓰는 원문입니다.</param>
public readonly record struct ScanProgressReport(ScanPhase Phase, double? Fraction, string Message);

/// <summary>
/// 화면에 보이는 진행 상태입니다. macOS <c>AppModel+ScanProgress</c> 를 그대로 옮겼습니다.
/// </summary>
/// <remarks>
/// 값을 만들어 내지 않습니다 — 단계별 되돌아감 방지, 되짚기 문턱, 배치 환산까지 원본과 같은
/// 규칙입니다. 문구만 셸의 <c>Resources.resw</c> 에서 옵니다.
/// </remarks>
public sealed class ScanProgressState
{
    private double lastFraction;
    private ScanPhase lastPhase = ScanPhase.Idle;
    private string lastMessage = string.Empty;
    private DateTimeOffset lastUpdatedAt = DateTimeOffset.MinValue;

    /// <summary>지금 단계입니다.</summary>
    public ScanPhase Phase { get; private set; } = ScanPhase.Idle;

    /// <summary>이 컷의 진행률입니다.</summary>
    public double Fraction { get; private set; }

    /// <summary>상태줄에 적을 말의 리소스 키입니다. 오류면 원문이 <see cref="ErrorMessage"/> 에 있습니다.</summary>
    public string MessageKey { get; private set; } = "scanProgressIdle";

    /// <summary>플러그인이 보낸 오류 원문입니다. 없으면 빈 문자열입니다.</summary>
    public string ErrorMessage { get; private set; } = string.Empty;

    /// <summary>스캔이 도는 중인가.</summary>
    public bool IsScanning { get; private set; }

    /// <summary>이번 배치에서 몇 번째 컷인가(0 부터).</summary>
    public int BatchIndex { get; private set; }

    /// <summary>이번 배치의 전체 컷 수입니다.</summary>
    public int BatchTotal { get; private set; }

    /// <summary>진행이 바뀌었습니다.</summary>
    public event EventHandler? Changed;

    /// <summary>배치를 엽니다. macOS 가 <c>batchIndex</c>/<c>batchTotal</c> 을 세우는 자리입니다.</summary>
    public void BeginBatch(int total)
    {
        BatchTotal = Math.Max(total, 0);
        BatchIndex = 0;
        IsScanning = true;
        Phase = ScanPhase.Connecting;
        Fraction = 0.0;
        MessageKey = "scanProgressConnecting";
        ErrorMessage = string.Empty;
        lastFraction = 0.0;
        lastPhase = ScanPhase.Connecting;
        lastMessage = MessageKey;
        lastUpdatedAt = DateTimeOffset.MinValue;
        Raise();
    }

    /// <summary>다음 컷으로 넘어갑니다. 컷 안의 진행률은 0 부터 다시 셉니다.</summary>
    public void BeginFrame(int index)
    {
        BatchIndex = Math.Max(index, 0);
        Fraction = 0.0;
        lastFraction = 0.0;
        Raise();
    }

    /// <summary>배치가 끝났습니다.</summary>
    public void EndBatch(bool completed)
    {
        IsScanning = false;
        Phase = completed ? ScanPhase.Complete : ScanPhase.Idle;
        Fraction = completed ? 1.0 : Fraction;
        MessageKey = completed ? "scanProgressComplete" : "scanProgressIdle";
        Raise();
    }

    /// <summary>
    /// 플러그인이 보낸 진행 한 줄을 받습니다. macOS <c>update(_:sessionID:)</c> 와 같습니다.
    /// </summary>
    /// <remarks>
    /// 원본과 같은 네 가지 문턱을 지킵니다 — 단계가 바뀌었거나, 말이 바뀌었거나, 진행률이
    /// 0.015 넘게 움직였거나, 0.20 초가 지났을 때만 화면을 건드립니다. 그러지 않으면 초당
    /// 수십 줄이 그대로 UI 갱신이 됩니다.
    /// </remarks>
    public void Report(ScanProgressReport report, DateTimeOffset now)
    {
        if (!IsScanning)
        {
            return;
        }
        double next = Normalized(report);
        string messageKey = MessageKeyFor(report.Phase);
        bool phaseChanged = report.Phase != lastPhase;
        bool messageChanged = !string.Equals(messageKey, lastMessage, StringComparison.Ordinal);
        bool fractionMoved = Math.Abs(next - lastFraction) >= 0.015;
        bool timeElapsed = now - lastUpdatedAt >= TimeSpan.FromMilliseconds(200);
        if (!phaseChanged && !messageChanged && !fractionMoved && !timeElapsed)
        {
            return;
        }
        lastUpdatedAt = now;
        lastFraction = next;
        lastPhase = report.Phase;
        lastMessage = messageKey;
        Phase = report.Phase;
        Fraction = next;
        MessageKey = messageKey;
        ErrorMessage = report.Phase == ScanPhase.Error ? report.Message : string.Empty;
        Raise();
    }

    /// <summary>
    /// 화면에 그릴 진행률입니다. 배치가 여러 컷이면 <b>배치 전체</b> 기준으로 환산합니다.
    /// </summary>
    /// <remarks>
    /// macOS 주석 그대로입니다 — 컷 하나의 진행률만 보여 주면 실제로는 정상인데 실패처럼
    /// 보입니다. 백엔드는 본 획득을 0.92 까지만 매핑하고, 앱이 획득 직후 1 로 올리지만 그
    /// 대입과 다음 컷의 0 초기화 사이에 중단 지점이 없어 100% 가 화면에 그려지는 일이
    /// 없습니다. 그래서 매 컷이 92% 에서 멈췄다가 0% 로 튀는 것처럼 보입니다.
    /// </remarks>
    public double DisplayedFraction()
    {
        double frame = Math.Clamp(Fraction, 0.0, 1.0);
        double result;
        if (BatchTotal > 1)
        {
            double completed = Math.Clamp(BatchIndex, 0, BatchTotal - 1);
            result = Math.Clamp((completed + frame) / BatchTotal, 0.0, 1.0);
        }
        else
        {
            result = frame;
        }
        return IsScanning ? result : (Phase == ScanPhase.Complete ? 1.0 : result);
    }

    private double Normalized(ScanProgressReport report)
    {
        if (report.Phase == ScanPhase.Complete)
        {
            return 1.0;
        }
        double fallback = FallbackFraction(report.Phase);
        double explicitValue = report.Fraction is { } value ? Math.Clamp(value, 0.0, 1.0) : fallback;
        return Math.Min(0.995, Math.Max(Fraction, explicitValue));
    }

    /// <summary>단계만 알고 진행률을 모를 때 쓰는 값입니다. macOS 표와 한 자리도 다르지 않습니다.</summary>
    private double FallbackFraction(ScanPhase phase) => phase switch
    {
        ScanPhase.Idle => 0.0,
        ScanPhase.Connecting => 0.06,
        ScanPhase.WarmingLamp => 0.18,
        ScanPhase.Ready => 0.22,
        ScanPhase.PreviewScanning => 0.35,
        ScanPhase.WaitingForFilmHolder => 0.24,
        ScanPhase.ScanningRGB => 0.42,
        ScanPhase.ScanningIR => 0.70,
        ScanPhase.ProcessingNegative => 0.88,
        ScanPhase.RenderingLook => 0.94,
        ScanPhase.Exporting => 0.96,
        ScanPhase.Complete => 1.0,
        _ => Fraction,
    };

    /// <summary>단계 이름의 리소스 키입니다.</summary>
    public static string PhaseKeyFor(ScanPhase phase) => "scanPhase" + phase.ToString();

    private static string MessageKeyFor(ScanPhase phase) => "scanProgress" + phase.ToString();

    /// <summary>플러그인이 보낸 단계 이름을 옮깁니다. 모르는 이름은 <see langword="null"/> 입니다.</summary>
    public static ScanPhase? Parse(string? phase) => phase switch
    {
        "idle" => ScanPhase.Idle,
        "connecting" => ScanPhase.Connecting,
        "warmingLamp" => ScanPhase.WarmingLamp,
        "ready" => ScanPhase.Ready,
        "previewScanning" => ScanPhase.PreviewScanning,
        "waitingForFilmHolder" => ScanPhase.WaitingForFilmHolder,
        "scanningRGB" => ScanPhase.ScanningRGB,
        "scanningIR" => ScanPhase.ScanningIR,
        "processingNegative" => ScanPhase.ProcessingNegative,
        "renderingLook" => ScanPhase.RenderingLook,
        "exporting" => ScanPhase.Exporting,
        "complete" => ScanPhase.Complete,
        "scannerBusy" => ScanPhase.ScannerBusy,
        "disconnected" => ScanPhase.Disconnected,
        "error" => ScanPhase.Error,
        "backendFallbackActive" => ScanPhase.BackendFallbackActive,
        _ => null,
    };

    private void Raise() => Changed?.Invoke(this, EventArgs.Empty);
}
