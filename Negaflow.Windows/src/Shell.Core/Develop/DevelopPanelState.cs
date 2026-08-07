using System.Globalization;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// Develop 패널이 들고 있는 것 전부입니다. XAML 코드비하인드가 아니라 여기 두어야 슬라이더의
/// clamp 와 결과 문구가 UI 없이 시험됩니다.
/// </summary>
public sealed class DevelopPanelState
{
    private readonly LibraryHostService host;
    private readonly ToneLimits limits;

    private readonly NegativeLimits negativeLimits;

    public DevelopPanelState(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);
        this.host = host;
        this.limits = limits;
        this.negativeLimits = negativeLimits;
    }

    public double MinimumManualDmin => negativeLimits.MinimumManualDmin;

    public double MaximumManualDmin => negativeLimits.MaximumManualDmin;

    /// <summary>
    /// 아직 base 를 고르지 않은 frame 의 슬라이더 시작 위치입니다. **이 값이 catalog 에 저장되지는
    /// 않습니다.** 사용자가 슬라이더를 움직여야 저장되며, 그전까지 frame 은 현상 불가 상태로
    /// 남습니다. 화면에 뭔가 보여 주는 것과 사용자가 고른 것을 구별합니다.
    /// </summary>
    public double SuggestedManualDmin =>
        negativeLimits.ClampChannel((MinimumManualDmin + MaximumManualDmin) / 4.0);

    public ManualBaseRgb? ManualBase => SelectedFrame?.ManualBase;

    /// <summary>
    /// 수동 필름 base 를 설정합니다. 범위는 엔진이 알려 준 것이며, 엔진은 벗어난 값을 거부하지
    /// 않고 조용히 clamp 하므로 여기서 먼저 묶어 저장된 값과 쓰인 값이 같게 합니다.
    /// </summary>
    public LibraryFrameError SetManualBase(double red, double green, double blue)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        ManualBaseRgb clamped = new(
            negativeLimits.ClampChannel(red),
            negativeLimits.ClampChannel(green),
            negativeLimits.ClampChannel(blue));
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(frame.Tone, clamped));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public LibraryFrameSnapshot? SelectedFrame { get; private set; }

    public double MaximumExposureStops => limits.MaximumExposureStops;

    public double Exposure => SelectedFrame?.Tone.Exposure ?? 0.0;

    public bool CanExport => SelectedFrame is { CanDevelop: true } && !host.IsExporting;

    public bool Select(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            if (string.Equals(frame.Id, frameId, StringComparison.Ordinal))
            {
                SelectedFrame = frame;
                return true;
            }
        }
        SelectedFrame = null;
        return false;
    }

    /// <summary>
    /// 노출을 바꿉니다. 범위는 엔진이 알려 준 값이고, clamp 를 통과한 값은 엔진이 받습니다.
    /// 저장은 하지 않습니다 — <see cref="Save"/> 를 부르십시오.
    /// </summary>
    public LibraryFrameError SetExposure(double stops)
    {
        if (SelectedFrame is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        ToneAdjustment tone = frame.Tone with { Exposure = limits.ClampExposure(stops) };
        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(tone, frame.ManualBase));
        if (error == LibraryFrameError.None)
        {
            // 편집 뒤 snapshot 은 새 객체이므로 선택을 다시 잡습니다.
            Select(frame.Id);
        }
        return error;
    }

    public CatalogStoreError Save() => host.Save();

    public Task<bool> ExportAsync(
        string destinationPath,
        DevelopExportFormat format,
        Action<DevelopExportOutcome> onCompleted)
    {
        ArgumentNullException.ThrowIfNull(onCompleted);
        if (SelectedFrame is not { } frame)
        {
            onCompleted(new DevelopExportOutcome(
                DevelopExportOutcomeKind.Refused,
                null,
                DevelopRequestRefusal.MissingManualBase,
                null));
            return Task.FromResult(true);
        }
        return host.ExportAsync(frame, destinationPath, format, onCompleted);
    }

    /// <summary>
    /// 결과를 사용자에게 보여 줄 한 줄로 만듭니다. 실패는 어느 단계에서 왜 멈췄는지를 남깁니다 —
    /// "Export failed" 만 보여 주면 스캔을 다시 하는 것 말고 할 수 있는 일이 없습니다.
    /// </summary>
    public static string Describe(DevelopExportOutcome outcome)
    {
        ArgumentNullException.ThrowIfNull(outcome);
        switch (outcome.Kind)
        {
            case DevelopExportOutcomeKind.Completed when outcome.Result is { } result:
                if (!result.Succeeded)
                {
                    return $"Develop stopped at {Humanize(result.FailedStage)}: {result.FailureName}";
                }
                double milliseconds = result.WallMicroseconds / 1000.0;
                return string.Create(
                    CultureInfo.CurrentCulture,
                    $"Exported {result.ImageWidth}×{result.ImageHeight} in {milliseconds:F0} ms");

            case DevelopExportOutcomeKind.Refused:
                return outcome.Refusal switch
                {
                    DevelopRequestRefusal.MissingManualBase =>
                        "Set the film base (Dmin) before developing this frame.",
                    DevelopRequestRefusal.UnsupportedDigitalSource =>
                        "This frame is a rendered digital source, which cannot be developed yet.",
                    DevelopRequestRefusal.InvalidDestination =>
                        "Choose a full path to export to.",
                    DevelopRequestRefusal.UnknownOutputFormat =>
                        "That export format is not supported.",
                    _ => "The develop request was refused.",
                };

            case DevelopExportOutcomeKind.Faulted:
                return $"The engine failed: {outcome.FaultMessage}";

            case DevelopExportOutcomeKind.Busy:
                return "A develop is already running.";

            default:
                return "The develop produced no result.";
        }
    }

    private static string Humanize(DevelopExportStage stage) => stage switch
    {
        DevelopExportStage.RequestValidation => "request validation",
        DevelopExportStage.ObserveSourceBefore => "reading the source file",
        DevelopExportStage.Decode => "decoding",
        DevelopExportStage.ObserveSourceAfter => "re-checking the source file",
        DevelopExportStage.FilmLookWorkspace => "preparing the Film Look",
        DevelopExportStage.Develop => "developing",
        DevelopExportStage.ToneAdjust => "tone adjustment",
        DevelopExportStage.FilmLook => "the Film Look",
        DevelopExportStage.Output => "writing the file",
        _ => "an unknown stage",
    };
}
