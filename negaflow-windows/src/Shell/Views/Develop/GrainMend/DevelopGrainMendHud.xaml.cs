using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.GrainMend;

/// <summary>
/// 캔버스 위의 GrainMend 캡슐입니다. macOS <c>RegionDefectOverlay</c> 의 컨트롤 바와 종류별
/// 칩을 그대로 옮긴 것이며, 무엇을 낼지는 <see cref="GrainMendHudProjection"/> 이 정합니다.
/// </summary>
public sealed partial class DevelopGrainMendHud : UserControl
{
    private bool updatingSensitivity;
    private bool updatingMicroSpecks;

    public DevelopGrainMendHud() => InitializeComponent();

    /// <summary>슬라이더를 끄는 동안 계속 옵니다. 값만 저장하고 재검출하지 않습니다.</summary>
    public event Action<double>? SensitivityChanged;

    /// <summary>슬라이더를 놓았습니다. macOS 도 이때에만 같은 ROI 로 재검출합니다.</summary>
    public event Action? SensitivityCommitted;

    public event Action<bool>? MicroSpecksToggled;

    public event Action? CancelRequested;

    public event Action? RemoveRequested;

    /// <summary>칩 하나를 눌렀습니다. 그 종류 전체를 제외↔포함합니다.</summary>
    public event Action<DefectClassification>? ClassToggled;

    /// <summary>
    /// 지금 상태를 화면에 옮깁니다. 여는 순서와 여백은 macOS 컨트롤 바와 같습니다.
    /// </summary>
    /// <param name="state">무엇을 낼지.</param>
    /// <param name="sensitivity">검토 중인 모드의 슬라이더 값.</param>
    /// <param name="microSpecks">검토 중인 모드의 미세 입자 설정.</param>
    /// <param name="isRemoving">"결함 제거"가 도는 중인지.</param>
    /// <param name="classNames">분류 이름표. 레이어 목록과 같은 표를 씁니다.</param>
    public void Update(
        GrainMendHudState state,
        double sensitivity,
        bool microSpecks,
        bool isRemoving,
        IReadOnlyDictionary<DefectClassification, string> classNames)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(classNames);
        HudRoot.Visibility = state.IsVisible ? Visibility.Visible : Visibility.Collapsed;
        if (!state.IsVisible)
        {
            return;
        }

        bool detecting = state.Mode == GrainMendHudMode.Detecting;
        bool reviewing = state.Mode == GrainMendHudMode.Reviewing;
        DetectingRing.IsActive = detecting;
        DetectingRing.Visibility = detecting ? Visibility.Visible : Visibility.Collapsed;
        StatusText.Text = Status(state);

        FirstDivider.Visibility = Show(reviewing);
        SensitivityGroup.Visibility = Show(reviewing);
        SecondDivider.Visibility = Show(reviewing);
        CancelButton.Visibility = Show(reviewing);
        RemoveButton.Visibility = Show(reviewing);
        // macOS 는 검출 중에만 컨트롤을 숨깁니다 — 기다리는 중에도 미세 입자는 바꿀 수 있습니다.
        MicroSpecksCheck.Visibility = Show(!detecting);

        SensitivitySlider.IsEnabled = state.TuningEnabled && !isRemoving;
        MicroSpecksCheck.IsEnabled = state.TuningEnabled || state.Mode == GrainMendHudMode.Waiting;
        CancelButton.IsEnabled = !isRemoving;
        RemoveButton.IsEnabled = state.RemoveEnabled && !isRemoving;
        // macOS 는 제거가 도는 동안 단추 안을 프로그래스로 바꿉니다.
        RemoveIcon.Visibility = Show(!isRemoving);
        RemoveText.Visibility = Show(!isRemoving);
        RemovingRing.IsActive = isRemoving;
        RemovingRing.Visibility = Show(isRemoving);

        if (reviewing)
        {
            updatingSensitivity = true;
            SensitivitySlider.Value = sensitivity;
            updatingSensitivity = false;
        }
        updatingMicroSpecks = true;
        MicroSpecksCheck.IsChecked = microSpecks;
        updatingMicroSpecks = false;

        Localize();
        UpdateChips(state, classNames);
    }

    /// <summary>말이 바뀌면 다시 짓습니다. macOS 도 표시 시점에 현재 언어로 짓습니다.</summary>
    public void Localize()
    {
        string microSpecks = AppResources.Get("developGrainMendMicroSpecks", "Text");
        MicroSpecksText.Text = microSpecks;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(MicroSpecksCheck, microSpecks);
        RemoveText.Text = AppResources.Get("developGrainMendRemove", "Content");
        string sensitivity = AppResources.Get("developGrainMendSensitivity", "Text");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(SensitivitySlider, sensitivity);
        ToolTipService.SetToolTip(SensitivitySlider, sensitivity);
        string cancel = AppResources.Get("developCropCancel", "Text");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(CancelButton, cancel);
        ToolTipService.SetToolTip(CancelButton, cancel);
        string remove = AppResources.Get("developGrainMendRemove", "Content");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(RemoveButton, remove);
        ToolTipService.SetToolTip(RemoveButton, remove);
    }

    /// <summary>
    /// macOS <c>detectSummary</c> 와 같습니다 — 없으면 "결함 없음", 제외한 것이 있으면 그 수까지.
    /// </summary>
    private static string Status(GrainMendHudState state) => state.Mode switch
    {
        GrainMendHudMode.Detecting => AppResources.Get("developGrainMendDetecting", "Text"),
        // macOS `detectSummary` 의 첫 분기입니다 — 위험 플래그가 서면 개수 대신 경고만
        // 냅니다. 결과는 그대로 남고 제외는 사용자가 클릭으로 합니다.
        GrainMendHudMode.Reviewing when state.FalsePositiveRisk =>
            AppResources.Get("developGrainMendFalsePositiveRisk", "Text"),
        GrainMendHudMode.Reviewing when state.Total == 0 =>
            AppResources.Get("developGrainMendNoDefects", "Text"),
        GrainMendHudMode.Reviewing when state.Excluded > 0 => AppResources.FormatIntegers(
            "developGrainMendDefectsExcludedFormat", "Value", state.Total, state.Excluded),
        GrainMendHudMode.Reviewing => AppResources.FormatInteger(
            "developGrainMendDefectsFormat", "Value", state.Total),
        // 자동은 누르는 즉시 검출로 넘어가므로 기다리는 안내는 가이드의 것입니다.
        _ => AppResources.Get("developGrainMendDragRegion", "Text"),
    };

    private void UpdateChips(
        GrainMendHudState state,
        IReadOnlyDictionary<DefectClassification, string> classNames)
    {
        if (state.Chips.Count == 0)
        {
            ChipsCapsule.Visibility = Visibility.Collapsed;
            ClassChips.ItemsSource = null;
            return;
        }
        ClassChips.ItemsSource = state.Chips
            .Select(chip => new GrainMendClassChipView(
                chip,
                classNames.TryGetValue(chip.Classification, out string? name)
                    ? name
                    : chip.Classification.ToString()))
            .ToArray();
        ChipsCapsule.Visibility = Visibility.Visible;
    }

    private static Visibility Show(bool visible) =>
        visible ? Visibility.Visible : Visibility.Collapsed;

    private void OnSensitivityValueChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (updatingSensitivity)
        {
            return;
        }
        SensitivityChanged?.Invoke(args.NewValue);
    }

    private void OnSensitivityCommitted(object sender, PointerRoutedEventArgs args)
    {
        _ = sender;
        args.Handled = true;
        SensitivityCommitted?.Invoke();
    }

    private void OnSensitivityKeyUp(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SensitivityCommitted?.Invoke();
    }

    private void OnMicroSpecksToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (updatingMicroSpecks)
        {
            return;
        }
        MicroSpecksToggled?.Invoke(MicroSpecksCheck.IsChecked == true);
    }

    private void OnCancelClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CancelRequested?.Invoke();
    }

    private void OnRemoveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        RemoveRequested?.Invoke();
    }

    private void OnChipClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is Button { Tag: DefectClassification classification })
        {
            ClassToggled?.Invoke(classification);
        }
    }
}
