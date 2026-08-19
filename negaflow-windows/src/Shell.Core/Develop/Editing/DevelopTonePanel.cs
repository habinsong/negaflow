using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 기본 톤과 톤 커브 네 축의 조작 표면입니다. 베이스·색·기하와 다른 이유로 바뀌므로
/// <see cref="DevelopPanelState"/> 가 전부 떠안지 않고 여기로 나눕니다.
/// </summary>
/// <remarks>
/// 값을 읽는 자리는 고른 frame 을 그대로 보고, 바꾸는 자리는 실제로 바뀐 뒤에만 다시 고릅니다 —
/// 그 규칙은 <see cref="DevelopPanelState"/> 한 곳에만 있습니다.
/// </remarks>
public sealed class DevelopTonePanel
{
    private readonly DevelopPanelState panel;
    private readonly DevelopToneEditor editor;

    internal DevelopTonePanel(DevelopPanelState panel, DevelopToneEditor editor)
    {
        this.panel = panel;
        this.editor = editor;
    }

    public double MaximumExposureStops => editor.MaximumExposureStops;

    public double MaximumToneControl => editor.MaximumToneControl;

    public double MaximumEndpointToneControl => editor.MaximumEndpointToneControl;

    public bool CanEdit => panel.SelectedFrame is not null;

    public double Exposure => panel.SelectedFrame?.Tone.Exposure ?? 0.0;

    public double Contrast => panel.SelectedFrame?.Tone.Contrast ?? 0.0;

    public double Highlights => panel.SelectedFrame?.Tone.Highlight ?? 0.0;

    public double Shadows => panel.SelectedFrame?.Tone.Shadow ?? 0.0;

    public double Whites => panel.SelectedFrame?.Tone.Whites ?? 0.0;

    public double Blacks => panel.SelectedFrame?.Tone.Blacks ?? 0.0;

    public double Density => panel.SelectedFrame?.Tone.Density ?? 0.0;

    public double CurveHighlights => panel.SelectedFrame?.Tone.CurveHighlights ?? 0.0;

    public double CurveLights => panel.SelectedFrame?.Tone.CurveLights ?? 0.0;

    public double CurveDarks => panel.SelectedFrame?.Tone.CurveDarks ?? 0.0;

    public double CurveShadows => panel.SelectedFrame?.Tone.CurveShadows ?? 0.0;

    /// <summary>
    /// 노출을 바꿉니다. 범위는 엔진이 알려 준 값이고, clamp 를 통과한 값은 엔진이 받습니다.
    /// 저장은 하지 않습니다 — <see cref="DevelopPanelState.Save"/> 를 부르십시오.
    /// </summary>
    public LibraryFrameError SetExposure(double stops) =>
        panel.RefreshAfterEdit(editor.SetExposure(panel.SelectedFrame, stops));

    public LibraryFrameError SetContrast(double value) =>
        panel.RefreshAfterEdit(editor.SetContrast(panel.SelectedFrame, value));

    public LibraryFrameError SetHighlights(double value) =>
        panel.RefreshAfterEdit(editor.SetHighlights(panel.SelectedFrame, value));

    public LibraryFrameError SetShadows(double value) =>
        panel.RefreshAfterEdit(editor.SetShadows(panel.SelectedFrame, value));

    public LibraryFrameError SetWhites(double value) =>
        panel.RefreshAfterEdit(editor.SetWhites(panel.SelectedFrame, value));

    public LibraryFrameError SetBlacks(double value) =>
        panel.RefreshAfterEdit(editor.SetBlacks(panel.SelectedFrame, value));

    public LibraryFrameError SetDensity(double value) =>
        panel.RefreshAfterEdit(editor.SetDensity(panel.SelectedFrame, value));

    public LibraryFrameError SetCurveHighlights(double value) =>
        panel.RefreshAfterEdit(editor.SetCurveHighlights(panel.SelectedFrame, value));

    public LibraryFrameError SetCurveLights(double value) =>
        panel.RefreshAfterEdit(editor.SetCurveLights(panel.SelectedFrame, value));

    public LibraryFrameError SetCurveDarks(double value) =>
        panel.RefreshAfterEdit(editor.SetCurveDarks(panel.SelectedFrame, value));

    public LibraryFrameError SetCurveShadows(double value) =>
        panel.RefreshAfterEdit(editor.SetCurveShadows(panel.SelectedFrame, value));

    public LibraryFrameError ResetBasicTone() =>
        panel.RefreshAfterEdit(editor.ResetBasicTone(
            panel.SelectedFrame,
            DevelopInspectorResetter.NeutralPresetId));

    public LibraryFrameError ResetToneCurve() =>
        panel.RefreshAfterEdit(editor.ResetToneCurve(panel.SelectedFrame));

    public LibraryFrameError ApplyAutoTone(AutoAdjustSettings settings) =>
        panel.RefreshAfterEdit(editor.ApplyAutoTone(panel.SelectedFrame, settings));

    public LibraryFrameError ApplyAutoWhiteBalance(AutoAdjustSettings settings) =>
        panel.RefreshAfterEdit(editor.ApplyAutoWhiteBalance(panel.SelectedFrame, settings));
}
