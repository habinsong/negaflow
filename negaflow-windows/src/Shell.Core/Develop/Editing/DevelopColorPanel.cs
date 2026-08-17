using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 색 관련 조작 표면입니다 — 포인트 커브, 컬러 믹서, 컬러 그레이딩, 색상 다섯 축, 원색
/// 캘리브레이션, 흑백 토닝. 톤·베이스·기하와 다른 이유로 바뀝니다.
/// </summary>
/// <remarks>
/// 값을 읽는 자리는 고른 frame 을 그대로 보고, 바꾸는 자리는 실제로 바뀐 뒤에만 다시 고릅니다 —
/// 그 규칙은 <see cref="DevelopPanelState"/> 한 곳에만 있습니다.
/// </remarks>
public sealed class DevelopColorPanel
{
    private readonly DevelopPanelState panel;
    private readonly DevelopColorEditor editor;

    internal DevelopColorPanel(DevelopPanelState panel, DevelopColorEditor editor)
    {
        this.panel = panel;
        this.editor = editor;
    }

    public PointCurveRecipe PointCurves =>
        panel.SelectedFrame?.PointCurves ?? PointCurveRecipe.Identity;

    public ColorMixerRecipe ColorMixer =>
        panel.SelectedFrame?.ColorMixer ?? ColorMixerRecipe.Identity;

    public ColorGradingRecipe ColorGrading =>
        panel.SelectedFrame?.ColorGrading ?? ColorGradingRecipe.Identity;

    public PrimaryCalibrationRecipe PrimaryCalibration =>
        panel.SelectedFrame?.PrimaryCalibration ?? PrimaryCalibrationRecipe.Identity;

    /// <summary>
    /// macOS 색상 섹션의 다섯 축입니다. 원색 세 축은 이 섹션에 없으므로 그대로 둡니다.
    /// </summary>
    public ColorModelRecipe ColorModel =>
        panel.SelectedFrame?.ColorModel ?? ColorModelRecipe.Identity;

    public BwToningRecipe BwToning => panel.SelectedFrame?.BwToning ?? BwToningRecipe.None;

    /// <summary>
    /// macOS 는 흑백 필름에서만 토닝 섹션을 냅니다. 컬러에서는 자리째 사라집니다.
    /// </summary>
    public bool ShowsBwToning => panel.SelectedFrame?.Route.FilmType is
        FilmType.BlackAndWhiteNegative or FilmType.BlackAndWhitePositive;

    /// <summary>
    /// 색상 섹션의 다섯 축만 0 으로 돌립니다. 같은 recipe 에 있는 원색 세 축은 이 섹션의 것이
    /// 아니므로 건드리지 않습니다.
    /// </summary>
    public LibraryFrameError ResetColor() =>
        panel.RefreshAfterEdit(editor.ResetColor(panel.SelectedFrame));

    public LibraryFrameError ResetColorMixer() =>
        panel.RefreshAfterEdit(
            editor.SetColorMixer(panel.SelectedFrame, ColorMixerRecipe.Identity));

    public LibraryFrameError ResetColorGrading() =>
        panel.RefreshAfterEdit(
            editor.SetColorGrading(panel.SelectedFrame, ColorGradingRecipe.Identity));

    public LibraryFrameError ResetPrimaryCalibration() =>
        SetPrimaryCalibration(PrimaryCalibrationRecipe.Identity);

    public LibraryFrameError ResetBwToning() => SetBwToning(BwToningRecipe.None);

    /// <summary>
    /// Point Curve는 Parametric Tone Curve와 별도 recipe로 저장합니다. Catalog writer가
    /// 좌표의 finite/range/중복 조건을 검증해 preview와 export가 같은 값만 받습니다.
    /// </summary>
    public LibraryFrameError SetPointCurves(PointCurveRecipe pointCurves) =>
        panel.RefreshAfterEdit(editor.SetPointCurves(panel.SelectedFrame, pointCurves));

    /// <summary>Color Mixer는 Tone과 별도 recipe로 저장되어 preview/export에 같은 값을 전달합니다.</summary>
    public LibraryFrameError SetColorMixer(ColorMixerRecipe colorMixer) =>
        panel.RefreshAfterEdit(editor.SetColorMixer(panel.SelectedFrame, colorMixer));

    /// <summary>Color Grading은 Tone과 별도 recipe로 저장되어 preview/export에 같은 값을 전달합니다.</summary>
    public LibraryFrameError SetColorGrading(ColorGradingRecipe colorGrading) =>
        panel.RefreshAfterEdit(editor.SetColorGrading(panel.SelectedFrame, colorGrading));

    public LibraryFrameError SetColorModel(ColorModelRecipe colorModel) =>
        panel.RefreshAfterEdit(editor.SetColorModel(panel.SelectedFrame, colorModel));

    public LibraryFrameError SetBwToning(BwToningRecipe bwToning) =>
        panel.RefreshAfterEdit(editor.SetBwToning(panel.SelectedFrame, bwToning));

    /// <summary>
    /// 모드를 고릅니다. 켜는 순간 macOS 처럼 최소 세기를 보장합니다 — 0 인 채로 켜면 아무 일도
    /// 일어나지 않아 고장으로 보입니다. 색조는 그 모드의 기본값에서 시작합니다.
    /// </summary>
    public LibraryFrameError SetBwToningMode(BwToningMode mode) =>
        panel.RefreshAfterEdit(editor.SetBwToningMode(panel.SelectedFrame, mode));

    public LibraryFrameError SetPrimaryCalibration(
        PrimaryCalibrationRecipe primaryCalibration) =>
        panel.RefreshAfterEdit(
            editor.SetPrimaryCalibration(panel.SelectedFrame, primaryCalibration));
}
