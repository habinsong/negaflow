using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 현상 인스펙터의 공통 조정 스택입니다. 빠른 동작과 톤·색·디테일 섹션을 담습니다.
/// </summary>
public sealed partial class DevelopAdjustmentStack : UserControl
{
    public DevelopAdjustmentStack()
    {
        using (Negaflow.Shell.Diagnostics.StartupTrace.Measure("  DevelopAdjustmentStack"))
        {
            InitializeComponent();
        }
        Tone.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.Tone);
        Tone.ExpansionRequested += (_, args) => RaiseExpansion(DevelopInspectorSection.Tone, args);
        Tone.PreviewRequested += OnChildPreview;
        Tone.ResetRequested += OnReset;
        ToneCurve.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.ToneCurve);
        ToneCurve.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.ToneCurve, args);
        ToneCurve.PreviewRequested += OnChildPreview;
        ToneCurve.ResetRequested += OnReset;
        Color.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.Color);
        Color.ExpansionRequested += (_, args) => RaiseExpansion(DevelopInspectorSection.Color, args);
        Color.PreviewRequested += OnChildPreview;
        Color.ResetRequested += OnReset;
        Mixer.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.ColorMixer);
        Mixer.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.ColorMixer, args);
        Mixer.PreviewRequested += OnChildPreview;
        Mixer.ResetRequested += OnReset;
        Grading.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.ColorGrading);
        Grading.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.ColorGrading, args);
        Grading.PreviewRequested += OnChildPreview;
        Grading.ResetRequested += OnReset;
        BwToning.ToggleRequested += (_, _) =>
            RaiseToggle(DevelopInspectorSection.BlackAndWhiteToning);
        BwToning.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.BlackAndWhiteToning, args);
        BwToning.PreviewRequested += OnChildPreview;
        BwToning.RefreshRequested += OnChildRefresh;
        Calibration.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.Calibration);
        Calibration.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.Calibration, args);
        Calibration.PreviewRequested += OnChildPreview;
        Calibration.ResetRequested += OnReset;
        Detail.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.DetailAndEffects);
        Detail.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.DetailAndEffects, args);
        Detail.PreviewRequested += OnChildPreview;
        Detail.RefreshRequested += OnChildRefresh;
        Detail.ResetRequested += OnReset;
        Debug.ToggleRequested += (_, _) => RaiseToggle(DevelopInspectorSection.Debug);
        Debug.ExpansionRequested += (_, args) =>
            RaiseExpansion(DevelopInspectorSection.Debug, args);
        Debug.DebugStateChanged += (_, _) => DebugStateChanged?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoColorToggled += (_, _) => AutoColorToggled?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoLevelsToggled += (_, _) => AutoLevelsToggled?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoToneClicked += (_, _) => AutoToneClicked?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoWhiteBalanceClicked += (_, _) =>
            AutoWhiteBalanceClicked?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoToneResetClicked += (_, _) =>
            AutoToneResetClicked?.Invoke(this, EventArgs.Empty);
        QuickActions.AutoWhiteBalanceResetClicked += (_, _) =>
            AutoWhiteBalanceResetClicked?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>디버그 오버레이나 단계가 바뀌었습니다. 미리보기를 다시 그려야 합니다.</summary>
    public event EventHandler? DebugStateChanged;

    /// <summary>지금 오버레이 상태입니다. 미리보기가 읽습니다.</summary>
    public Negaflow.Shell.Develop.DevelopDebugState DebugState => Debug.State;

    /// <summary>설정 · 일반의 개발자 모드를 구역에 겁니다.</summary>
    public void SetDeveloperMode(bool enabled) => Debug.SetDeveloperMode(enabled);

    /// <summary>마지막 현상이 실제로 쓴 값을 적습니다.</summary>
    public void ShowDebugMetrics(
        Negaflow.Catalog.ManualBaseRgb? appliedBase,
        Negaflow.Interop.DevelopDebugMetrics? metrics,
        int width,
        int height) => Debug.ShowMetrics(appliedBase, metrics, width, height);

    /// <summary>macOS QuickActionPill 의 되돌리기 단추입니다.</summary>
    public event EventHandler? AutoToneResetClicked;

    public event EventHandler? AutoWhiteBalanceResetClicked;

    public event EventHandler? PreviewRequested;

    public event EventHandler? RefreshRequested;

    public event EventHandler<Func<DevelopPanelState, LibraryFrameError>>? ResetRequested;

    public event EventHandler<DevelopInspectorSection>? SectionToggleRequested;

    public event EventHandler<DevelopInspectorSectionExpansion>? SectionExpansionRequested;

    public event EventHandler? AutoColorToggled;

    public event EventHandler? AutoLevelsToggled;

    public event EventHandler? AutoToneClicked;

    public event EventHandler? AutoWhiteBalanceClicked;

    public bool AutoColorIsOn => QuickActions.AutoColorIsOn;

    public bool AutoLevelsIsOn => QuickActions.AutoLevelsIsOn;

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        Tone.Bind(hostPanel);
        ToneCurve.Bind(hostPanel);
        Color.Bind(hostPanel);
        Mixer.Bind(hostPanel);
        Grading.Bind(hostPanel);
        BwToning.Bind(hostPanel);
        Calibration.Bind(hostPanel);
        Detail.Bind(hostPanel);
    }

    public void ConfigureRanges(
        double exposureStops,
        double toneControl,
        double endpointToneControl)
    {
        Tone.ConfigureRanges(exposureStops, toneControl, endpointToneControl);
        ToneCurve.ConfigureRanges(toneControl);
        Calibration.ConfigureRanges(toneControl);
        Detail.ConfigureRanges(toneControl);
    }

    public void Localize()
    {
        QuickActions.Localize();
        Tone.Localize();
        ToneCurve.Localize();
        Color.Localize();
        Mixer.Localize();
        Grading.Localize();
        BwToning.Localize();
        Calibration.Localize();
        Detail.Localize();
        Debug.Localize();
    }

    public void Show(DevelopPanelState hostPanel)
    {
        Tone.Show(hostPanel);
        ToneCurve.Show(hostPanel);
        Color.Show(hostPanel);
        Mixer.Show(hostPanel);
        Grading.Show(hostPanel);
        BwToning.Show(hostPanel);
        Calibration.Show(hostPanel);
        Detail.Show(hostPanel);
        QuickActions.Show(hostPanel);
    }

    public void SetEnabled(bool canEdit, bool canAutoAdjust)
    {
        Tone.SetEnabled(canEdit);
        ToneCurve.SetEnabled(canEdit);
        Mixer.SetEnabled(canEdit);
        Grading.SetEnabled(canEdit);
        Calibration.SetEnabled(canEdit);
        Detail.SetEnabled(canEdit);
        QuickActions.SetAutoAdjustEnabled(canAutoAdjust);
    }

    public void Apply(DevelopInspectorPresentationState presentation)
    {
        Visibility = presentation.ShowsAdjustmentSections
            ? Visibility.Visible
            : Visibility.Collapsed;
        Tone.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.Tone);
        ToneCurve.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.ToneCurve);
        Color.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.Color);
        Mixer.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.ColorMixer);
        Grading.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.ColorGrading);
        BwToning.ApplyExpanded(
            presentation.ExpandedSection == DevelopInspectorSection.BlackAndWhiteToning);
        Calibration.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.Calibration);
        Detail.ApplyExpanded(presentation.ExpandedSection == DevelopInspectorSection.DetailAndEffects);
        Debug.SetExpanded(presentation.ExpandedSection == DevelopInspectorSection.Debug);
    }

    public void SetAutoAdjustStatus(string text) => QuickActions.SetStatus(text);

    public void SetAutoAdjustEnabled(bool enabled) => QuickActions.SetAutoAdjustEnabled(enabled);

    private void RaiseToggle(DevelopInspectorSection kind) =>
        SectionToggleRequested?.Invoke(this, kind);

    private void RaiseExpansion(
        DevelopInspectorSection kind,
        DisclosureExpansionRequestedEventArgs args) =>
        SectionExpansionRequested?.Invoke(
            this,
            new DevelopInspectorSectionExpansion(kind, args.IsExpanded));

    private void OnChildPreview(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        PreviewRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnChildRefresh(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        RefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnReset(object? sender, Func<DevelopPanelState, LibraryFrameError> reset)
    {
        _ = sender;
        ResetRequested?.Invoke(this, reset);
    }
}

/// <summary>인스펙터 섹션의 펼침 요청입니다.</summary>
public readonly record struct DevelopInspectorSectionExpansion(
    DevelopInspectorSection Section,
    bool IsExpanded);
