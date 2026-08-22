using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 개발자 디버그 구역입니다. macOS <c>DevelopAdjustmentSections.debugSection</c> 자리이며,
/// 설정 · 일반의 "개발자 모드" 가 켜져 있을 때만 나옵니다.
/// </summary>
public sealed partial class DevelopDebugSection : UserControl
{
    private bool isSynchronizing;

    public DevelopDebugSection()
    {
        InitializeComponent();
        BuildStages();
    }

    /// <summary>오버레이나 스테이지가 바뀌었습니다. 미리보기를 다시 그려야 합니다.</summary>
    public event EventHandler? DebugStateChanged;

    public event EventHandler? ToggleRequested;

    public event EventHandler<DisclosureExpansionRequestedEventArgs>? ExpansionRequested;

    public DevelopDebugState State { get; private set; } = new();

    /// <summary>개발자 모드가 꺼지면 구역째 사라지고 오버레이도 함께 꺼집니다.</summary>
    public void SetDeveloperMode(bool enabled)
    {
        DebugSection.Visibility = enabled ? Visibility.Visible : Visibility.Collapsed;
        if (enabled || !State.OverlayEnabled)
        {
            return;
        }
        State = State with { OverlayEnabled = false };
        Synchronize();
        DebugStateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void SetExpanded(bool expanded) => DevelopInspectorSectionChrome.Apply(
        DebugHeaderButton, DebugChevron, DebugControls, expanded);

    public void Localize()
    {
        DebugTitleText.Text = AppResources.Get("developerDebug", "Text");
        OverlayLabelText.Text = AppResources.Get("debugOverlay", "Text");
        StageLabelText.Text = AppResources.Get("developerDebugStage", "Text");
        BuildStages();
    }

    /// <summary>
    /// 마지막 현상이 실제로 잰 값입니다. macOS <c>DevelopDebugMetrics</c> 와 같은 넷 -
    /// baseRGB · dmin · dmaxNorm · blackInput.
    /// </summary>
    /// <remarks>
    /// 재지 않은 값은 적지 않습니다. 포지티브·디지털 원본은 네거티브 반전을 거치지 않아
    /// 지표가 없고, 그 자리에 그럴듯한 숫자를 넣으면 사용자는 그것을 측정값으로 읽습니다.
    /// </remarks>
    public void ShowMetrics(
        ManualBaseRgb? appliedBase,
        Negaflow.Interop.DevelopDebugMetrics? metrics,
        int width,
        int height)
    {
        System.Globalization.CultureInfo culture =
            System.Globalization.CultureInfo.InvariantCulture;
        List<string> lines = [];
        if (appliedBase is { } rgb)
        {
            lines.Add(string.Create(
                culture,
                $"baseRGB     {rgb.Red,8:0.####} {rgb.Green,8:0.####} {rgb.Blue,8:0.####}"));
        }
        if (metrics is { } value)
        {
            lines.Add(string.Create(
                culture,
                $"dmin        {value.DminRed,8:0.####} {value.DminGreen,8:0.####} {value.DminBlue,8:0.####}"));
            lines.Add(string.Create(
                culture,
                $"dmaxNorm    {value.DmaxNormalizedRed,8:0.####} {value.DmaxNormalizedGreen,8:0.####} {value.DmaxNormalizedBlue,8:0.####}"));
            lines.Add(string.Create(
                culture,
                $"blackInput  {value.BlackInputRed,8:0.####} {value.BlackInputGreen,8:0.####} {value.BlackInputBlue,8:0.####}"));
        }
        lines.Add(string.Create(culture, $"size        {width} x {height}"));
        MetricsText.Text = string.Join('\n', lines);
    }

    private void BuildStages()
    {
        isSynchronizing = true;
        StageComboBox.Items.Clear();
        foreach (DevelopDebugStage stage in Enum.GetValues<DevelopDebugStage>())
        {
            StageComboBox.Items.Add(DevelopDebugFrames.DisplayName(stage));
        }
        StageComboBox.SelectedIndex = (int)State.Stage;
        isSynchronizing = false;
    }

    private void Synchronize()
    {
        isSynchronizing = true;
        OverlayToggle.IsOn = State.OverlayEnabled;
        StageComboBox.SelectedIndex = (int)State.Stage;
        StageComboBox.IsEnabled = State.OverlayEnabled;
        isSynchronizing = false;
    }

    private void OnOverlayToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizing)
        {
            return;
        }
        State = State with { OverlayEnabled = OverlayToggle.IsOn };
        StageComboBox.IsEnabled = State.OverlayEnabled;
        DebugStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnStageChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizing || StageComboBox.SelectedIndex < 0)
        {
            return;
        }
        State = State with { Stage = (DevelopDebugStage)StageComboBox.SelectedIndex };
        DebugStateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnHeaderClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ToggleRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnExpansionRequested(
        object? sender,
        DisclosureExpansionRequestedEventArgs args)
    {
        _ = sender;
        ExpansionRequested?.Invoke(this, args);
    }
}
