using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS <c>LocalAdjustmentSection</c> — 부분 보정 카드입니다.
/// </summary>
/// <remarks>
/// 마스크 종류(브러시·방사형·선형·다각형) 고르기, 닷지/번, 새로 만들 보정의 양·페더·크기,
/// 그리고 이미 만든 보정 목록을 냅니다. 실제 그리기는 캔버스가 맡고 여기서는
/// <see cref="DrawingToggled"/> 로 알립니다.
/// </remarks>
public sealed partial class DevelopLocalAdjustmentSection : UserControl
{
    private readonly LocalAdjustmentSession session = new();
    private readonly DevelopLocalAdjustmentRows rows = new();
    private DevelopLocalAdjustmentCanvasInput canvasInput = null!;
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopLocalAdjustmentSection()
    {
        using (Negaflow.Shell.Diagnostics.StartupTrace.Measure("  DevelopLocalAdjustmentSection"))
        {
            InitializeComponent();
        }
        // RangeBase 는 현재 Value 보다 큰 Minimum 을 XBF 로딩 중 바로 적용하지 못합니다.
        // 기본값을 유효 범위 안으로 옮긴 뒤 최소값을 완성합니다.
        LocalSizeSlider.Value = 0.005;
        LocalSizeSlider.Minimum = 0.005;
        canvasInput = new DevelopLocalAdjustmentCanvasInput(this);
        Localize();
    }

    /// <summary>보정 목록이 바뀌어 다시 현상해야 할 때입니다.</summary>
    public event EventHandler? AdjustmentsChanged;

    /// <summary>
    /// 그리기가 켜졌거나 꺼졌을 때입니다. macOS 는 켜질 때 크롭·브러시·결함·복제도장·
    /// 베이스 스포이드를 모두 끕니다 — 그 판단은 캔버스를 아는 쪽이 합니다.
    /// </summary>
    public event EventHandler<bool>? DrawingToggled;

    /// <summary>지금 그리는 상태입니다. 캔버스가 읽습니다.</summary>
    public LocalAdjustmentSession Session => session;

    /// <summary>
    /// 안내 캡슐이 다시 그려져야 할 때입니다 — 마스크 종류나 다각형 꼭짓점 수가 바뀐 뒤입니다.
    /// </summary>
    public event EventHandler? PromptChanged;

    /// <summary>macOS `session.deactivate()` — 안내 캡슐의 와 같은 길입니다.</summary>
    public void StopDrawing()
    {
        session.Deactivate();
        canvasInput.Cancel();
        Show();
    }

    /// <summary>캔버스가 점을 찍거나 마스크를 만든 뒤 안내 캡슐을 다시 맞춥니다.</summary>
    internal void NotifyPromptChanged() => PromptChanged?.Invoke(this, EventArgs.Empty);

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
    }

    public void Localize()
    {
        LocalSectionTitleText.Text = AppResources.Get("developLocalTitle", "Text");
        LocalAmountLabel.Text = AppResources.Get("developLocalAmount", "Text");
        LocalFeatherLabel.Text = AppResources.Get("developLocalFeather", "Text");
        LocalSizeLabel.Text = AppResources.Get("developLocalSize", "Text");
        LocalEmptyText.Text = AppResources.Get("developLocalEmpty", "Text");
        SetButtonText(LocalDodgeButton, AppResources.Get("developLocalDodge", "Text"));
        SetButtonText(LocalBurnButton, AppResources.Get("developLocalBurn", "Text"));
        NameMaskButton(LocalBrushButton, "developLocalBrush");
        NameMaskButton(LocalRadialButton, "developLocalRadial");
        NameMaskButton(LocalLinearButton, "developLocalLinear");
        NameMaskButton(LocalPolygonButton, "developLocalPolygon");
        AutomationProperties.SetName(LocalAmountSlider, LocalAmountLabel.Text);
        AutomationProperties.SetName(LocalFeatherSlider, LocalFeatherLabel.Text);
        AutomationProperties.SetName(LocalSizeSlider, LocalSizeLabel.Text);
    }

    /// <summary>세션과 프레임의 보정 목록을 컨트롤에 옮깁니다.</summary>
    public void Show()
    {
        if (LocalAmountSlider is null)
        {
            return;
        }
        isSynchronizing = true;
        try
        {
            LocalAmountSlider.Value = session.Amount;
            LocalFeatherSlider.Value = session.Feather;
            LocalSizeSlider.Value = session.BrushThickness;
        }
        finally
        {
            isSynchronizing = false;
        }
        LocalAmountValue.Text = Percent(session.Amount);
        LocalFeatherValue.Text = Percent(session.Feather);
        LocalSizeValue.Text = Percent(session.BrushThickness);
        // macOS 는 브러시일 때만 크기 줄을 냅니다.
        LocalSizeRow.Visibility = session.MaskKind == LocalDodgeBurnMaskKind.Brush
            ? Visibility.Visible
            : Visibility.Collapsed;
        ApplyMaskSelection();
        ApplyModeSelection();
        rows.Rebuild(this, Adjustments);
    }

    internal IReadOnlyList<LocalDodgeBurnAdjustment> Adjustments =>
        panel?.SelectedFrame?.LocalDodgeBurn ?? [];

    internal string? FrameId => panel?.SelectedFrame?.Id;

    /// <summary>
    /// 방사형 반지름을 사진 기준으로 재려면 원본 크기가 필요합니다. 모르면 0 을 내고
    /// <see cref="LocalAdjustmentMaskFactory"/> 가 정규화 거리를 그대로 씁니다.
    /// </summary>
    internal double ImageWidth => panel?.SelectedFrame?.SourceMetadata?.PixelWidth ?? 0.0;

    internal double ImageHeight => panel?.SelectedFrame?.SourceMetadata?.PixelHeight ?? 0.0;

    /// <summary>사진 위에 그리는 제스처입니다. 캔버스가 포인터를 넘겨 줍니다.</summary>
    internal DevelopLocalAdjustmentCanvasInput CanvasInput => canvasInput;

    /// <summary>목록을 카탈로그에 씁니다. 실패해도 화면은 지금 값을 지킵니다.</summary>
    internal void Replace(IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        if (panel is not { SelectedFrame: { } frame })
        {
            return;
        }
        if (panel.EditLocalDodgeBurn(frame.Id, adjustments) != LibraryFrameError.None)
        {
            return;
        }
        Show();
        AdjustmentsChanged?.Invoke(this, EventArgs.Empty);
    }

    private static string Percent(double unit) =>
        Math.Round(unit * 100.0).ToString("0", System.Globalization.CultureInfo.CurrentCulture);

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
    }

    private static void NameMaskButton(Button button, string key)
    {
        string text = AppResources.Get(key, "Text");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    /// <summary>macOS 는 그리는 중인 종류만 강조색 18% 바탕을 답니다.</summary>
    private void ApplyMaskSelection()
    {
        foreach ((Button button, LocalDodgeBurnMaskKind kind) in MaskButtons())
        {
            bool drawing = FrameId is { } id && session.IsDrawing(id, kind);
            button.Background = drawing
                ? (Brush)Application.Current.Resources["NegaflowAccentSoftBrush"]
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(drawing ? "selected" : "notSelected", "Value"));
        }
    }

    private void ApplyModeSelection()
    {
        foreach ((Button button, LocalDodgeBurnMode mode) in ModeButtons())
        {
            bool selected = session.Mode == mode;
            button.Background = selected
                ? (Brush)Application.Current.Resources["NegaflowAccentSoftBrush"]
                : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            AutomationProperties.SetItemStatus(
                button,
                AppResources.Get(selected ? "selected" : "notSelected", "Value"));
        }
    }

    private IEnumerable<(Button Button, LocalDodgeBurnMaskKind Kind)> MaskButtons()
    {
        yield return (LocalBrushButton, LocalDodgeBurnMaskKind.Brush);
        yield return (LocalRadialButton, LocalDodgeBurnMaskKind.Radial);
        yield return (LocalLinearButton, LocalDodgeBurnMaskKind.Linear);
        yield return (LocalPolygonButton, LocalDodgeBurnMaskKind.Polygon);
    }

    private IEnumerable<(Button Button, LocalDodgeBurnMode Mode)> ModeButtons()
    {
        yield return (LocalDodgeButton, LocalDodgeBurnMode.Dodge);
        yield return (LocalBurnButton, LocalDodgeBurnMode.Burn);
    }

    private void OnMaskKindClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag } ||
            !Enum.TryParse(tag, out LocalDodgeBurnMaskKind kind) ||
            FrameId is not { } frameId)
        {
            return;
        }
        bool drawing = session.ToggleDrawing(frameId, kind, Adjustments);
        if (!drawing)
        {
            canvasInput.Cancel();
        }
        Show();
        DrawingToggled?.Invoke(this, drawing);
        NotifyPromptChanged();
    }

    private void OnModeClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is Button { Tag: string tag } && Enum.TryParse(tag, out LocalDodgeBurnMode mode))
        {
            session.Mode = mode;
            ApplyModeSelection();
        }
    }

    private void OnAmountChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizing)
        {
            return;
        }
        session.Amount = args.NewValue;
        LocalAmountValue.Text = Percent(session.Amount);
    }

    private void OnFeatherChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizing)
        {
            return;
        }
        session.Feather = args.NewValue;
        LocalFeatherValue.Text = Percent(session.Feather);
    }

    private void OnSizeChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        if (isSynchronizing)
        {
            return;
        }
        session.BrushThickness = args.NewValue;
        LocalSizeValue.Text = Percent(session.BrushThickness);
    }
}
