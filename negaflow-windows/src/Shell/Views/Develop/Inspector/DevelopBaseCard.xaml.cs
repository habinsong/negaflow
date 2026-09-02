using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// 필름 베이스 추정 모드와 수동 Dmin 입니다. 미리보기·내보내기 상태 갱신은
/// <see cref="RecipeChanged"/> 와 <see cref="ManualBaseCommitted"/> 로 뷰가 맡습니다.
/// </summary>
public sealed partial class DevelopBaseCard : UserControl
{
    private DevelopPanelState? panel;
    private bool isSynchronizing;

    public DevelopBaseCard() => InitializeComponent();

    /// <summary>모드·필름·광원·스캐너가 바뀐 뒤 목록과 미리보기를 맞출 때 올립니다.</summary>
    public event EventHandler? RecipeChanged;

    /// <summary>수동 Dmin 슬라이더를 놓은 뒤 선택 행과 미리보기를 맞출 때 올립니다.</summary>
    public event EventHandler? ManualBaseCommitted;

    /// <summary>
    /// macOS <c>basePickerMode</c> — 캔버스 스포이드가 켜졌는지입니다. 캔버스가 이 값을 보고
    /// 클릭을 받습니다.
    /// </summary>
    public bool IsBasePickerActive { get; private set; }

    /// <summary>스포이드 토글이 바뀌면 올립니다. 캔버스 오버레이를 켜고 끄는 자리입니다.</summary>
    public event EventHandler? BasePickerModeChanged;

    /// <summary>macOS <c>resetManualBase</c> — 수동 Dmin 을 제안값으로 되돌립니다.</summary>
    public event EventHandler? ManualBaseResetRequested;

    /// <summary>스포이드 모드를 끕니다. 클릭을 받았거나 도구를 떠날 때 캔버스가 부릅니다.</summary>
    public void CancelBasePicker()
    {
        if (!IsBasePickerActive)
        {
            return;
        }
        IsBasePickerActive = false;
        ApplyBasePickerVisual();
        BasePickerModeChanged?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>macOS 메뉴 <c>basePickerTool</c> — 스포이드 단추와 같은 토글입니다.</summary>
    public void ToggleBasePickerFromMenu()
    {
        IsBasePickerActive = !IsBasePickerActive;
        ApplyBasePickerVisual();
        BasePickerModeChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
        FilmStockSelector.ItemsSource = BundledFilmBaseOptions.FilmStocks;
        LightSourceSelector.ItemsSource = BundledFilmBaseOptions.LightSources;
        ScannerProfileSelector.ItemsSource = ScannerProfileChoices();
    }

    /// <summary>
    /// 수동 베이스 슬라이더의 범위입니다. macOS
    /// <c>BaseControlSection.swift</c> 는 <c>InspectorSlider(…, range: 0...1)</c> 로 <b>0…1</b> 을
    /// 씁니다 — 엔진 한계(<c>clampedDmin</c> 의 1e-3)는 슬라이더가 아니라 반전이 거는 것입니다.
    /// 엔진 한계를 슬라이더 최소로 쓰면 눈금이 0.001 씩 밀려 macOS 와 다른 값이 됩니다.
    /// </summary>
    public void ConfigureRanges()
    {
        foreach (InspectorSlider slider in new[] { BaseRedControl, BaseGreenControl, BaseBlueControl })
        {
            slider.Minimum = 0.0;
            slider.Maximum = 1.0;
        }
    }

    public void Localize()
    {
        string baseTitle = AppResources.Get("developTabBase", "Value");
        BaseSectionTitleText.Text = baseTitle;
        AutomationProperties.SetName(BaseControlCard, baseTitle);
        // 앞 판은 XAML 에 "Film base mode" 가 박혀 있어 어떤 언어에서도 그대로였습니다.
        // macOS `SegmentedPicker` 에는 따로 이름이 없으므로 구역 이름을 그대로 씁니다.
        AutomationProperties.SetName(BaseModeControl, baseTitle);
        SetRadioText(BaseAutoModeButton, AppResources.Get("developBaseModeAuto", "Content"));
        SetRadioText(BaseFilmModeButton, AppResources.Get("developBaseModeFilm", "Content"));
        SetRadioText(BaseManualModeButton, AppResources.Get("developBaseModeManual", "Content"));
        FilmStockLabel.Text = AppResources.Get("developFilmStock", "Text");
        AutomationProperties.SetName(FilmStockSelector, FilmStockLabel.Text);
        LightSourceLabel.Text = AppResources.Get("developLightSource", "Text");
        AutomationProperties.SetName(LightSourceSelector, LightSourceLabel.Text);
        ScannerProfileLabel.Text = AppResources.Get("developScannerProfile", "Text");
        AutomationProperties.SetName(ScannerProfileSelector, ScannerProfileLabel.Text);
        BaseRedControl.Label = AppResources.Get("developBaseRed", "Text");
        BaseGreenControl.Label = AppResources.Get("developBaseGreen", "Text");
        BaseBlueControl.Label = AppResources.Get("developBaseBlue", "Text");
        BasePickerText.Text = AppResources.Get("developPickBase", "Text");
        string pickHelp = AppResources.Get("developPickBaseHelp", "Value");
        AutomationProperties.SetName(BasePickerButton, pickHelp);
        ToolTipService.SetToolTip(BasePickerButton, pickHelp);
        string reset = AppResources.Get("developReset", "Value");
        AutomationProperties.SetName(BasePickerResetButton, reset);
        ToolTipService.SetToolTip(BasePickerResetButton, reset);
        // 고름 표시(선택됨/선택되지 않음)도 리소스에서 옵니다.
        ApplyBasePickerVisual();
    }

    private void OnBasePickerToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        IsBasePickerActive = !IsBasePickerActive;
        ApplyBasePickerVisual();
        BasePickerModeChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnBasePickerResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ManualBaseResetRequested?.Invoke(this, EventArgs.Empty);
    }

    /// <summary>
    /// macOS <c>InspectorActionPill</c>: 켜져 있으면 강조색 0.18 바탕에 0.45 테두리,
    /// 꺼져 있으면 primary 0.06 바탕에 0.12 테두리입니다.
    /// </summary>
    private void ApplyBasePickerVisual()
    {
        BasePickerPill.Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            IsBasePickerActive ? "NegaflowSelectionBrush" : "NegaflowSubtleFillBrush"];
        BasePickerPill.BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[
            IsBasePickerActive ? "NegaflowSelectionBrush" : "NegaflowDividerBrush"];
        AutomationProperties.SetItemStatus(
            BasePickerButton,
            AppResources.Get(IsBasePickerActive ? "selected" : "notSelected", "Value"));
    }

    public void Sync()
    {
        if (panel is null)
        {
            return;
        }

        bool canEdit = panel.CanEditBase;
        BaseAutoModeButton.IsEnabled = canEdit;
        BaseFilmModeButton.IsEnabled = canEdit;
        BaseManualModeButton.IsEnabled = canEdit;
        isSynchronizing = true;
        BaseAutoModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Auto;
        BaseFilmModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Preset;
        BaseManualModeButton.IsChecked = panel.BaseMode == BaseEstimationMode.Manual;
        FilmStockSelector.SelectedItem = BundledFilmBaseOptions.FilmStocks.FirstOrDefault(
            option => option.Id == panel.SelectedFrame?.Base.FilmStockDminId);
        LightSourceSelector.SelectedItem = BundledFilmBaseOptions.LightSources.FirstOrDefault(
            option => option.Id == panel.SelectedFrame?.Base.LightSourceProfileId);
        ScannerProfileSelector.SelectedItem = ScannerProfileSelector.Items
            .OfType<ScannerProfileChoice>()
            .FirstOrDefault(choice => choice.Id == panel.SelectedFrame?.Base.ScannerProfileId);
        isSynchronizing = false;
        FilmBaseControls.Visibility = canEdit && panel.BaseMode == BaseEstimationMode.Preset
            ? Visibility.Visible
            : Visibility.Collapsed;
        FilmStockSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        LightSourceSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        ScannerProfileSelector.IsEnabled = canEdit && panel.BaseMode == BaseEstimationMode.Preset;
        // macOS 는 `if frame.params.baseEstimationMode == .manual` 안에서 스포이드 필과
        // R/G/B 슬라이더를 함께 냅니다.
        bool manual = canEdit && panel.BaseMode == BaseEstimationMode.Manual;
        ManualBaseControls.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        BasePickerPill.Visibility = manual ? Visibility.Visible : Visibility.Collapsed;
        if (!manual)
        {
            CancelBasePicker();
        }
        ApplyBasePickerVisual();
        UpdateManualBaseText();
    }

    public void ShowManualValues(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            // macOS `manualBaseBinding` 의 get:
            //     frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
            // 앞 판은 세 칸에 모두 같은 "제안값"(0.25) 을 넣었습니다 — macOS 에 없는 값입니다.
            ManualBaseRgb shown = hostPanel.ManualBaseForDisplay;
            BaseRedControl.Value = shown.Red;
            BaseGreenControl.Value = shown.Green;
            BaseBlueControl.Value = shown.Blue;
        }
        finally
        {
            isSynchronizing = false;
        }
    }

    private void UpdateManualBaseText()
    {
        // macOS `baseReadout` — `frame.baseRGB` 가 있을 때만 `baseReadoutFormat` 을 씁니다.
        // 모드 이름·필름 이름을 지어내지 않습니다.
        if (panel?.LastAppliedBase is not { } applied)
        {
            ManualBaseValueText.Text = string.Empty;
            return;
        }

        ManualBaseValueText.Text = DevelopBaseReadout.Format(
            AppResources.Get("developBaseReadoutFormat", "Value"),
            applied);
    }

    /// <summary>
    /// 프로파일 목록입니다. macOS 처럼 이름 뒤에 검증 상태를 붙입니다 — 같은 스캐너의 프로파일이
    /// 여럿일 때 무엇으로 만들어진 것인지가 고르는 근거입니다.
    /// </summary>
    private static IReadOnlyList<ScannerProfileChoice> ScannerProfileChoices()
    {
        List<ScannerProfileChoice> choices =
        [
            new(null, AppResources.Get("developScannerProfileNone", "Text")),
        ];
        foreach (ScannerProfileOption option in BundledFilmBaseOptions.ScannerProfiles)
        {
            choices.Add(new ScannerProfileChoice(
                option.Id,
                $"{option.DisplayName} · {StatusLabel(option.Status)}"));
        }
        return choices;
    }

    private static string StatusLabel(ScannerProfileValidationStatus status) =>
        AppResources.Get(status switch
        {
            ScannerProfileValidationStatus.Draft => "developProfileStatusDraft",
            ScannerProfileValidationStatus.PairedSmoke => "developProfileStatusPairedSmoke",
            ScannerProfileValidationStatus.PairedValidated =>
                "developProfileStatusPairedValidated",
            _ => "developProfileStatusRealOnly",
        }, "Text");

    private void OnBaseAutoModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Auto);
    }

    private void OnBaseManualModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Manual);
    }

    private void OnBaseFilmModeChecked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SetBaseMode(BaseEstimationMode.Preset);
    }

    private void OnFilmStockSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing ||
            panel.SetFilmStock((FilmStockSelector.SelectedItem as FilmStockOption)?.Id) != LibraryFrameError.None)
        {
            return;
        }
        RecipeChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnScannerProfileSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing ||
            panel.SetScannerProfile(
                (ScannerProfileSelector.SelectedItem as ScannerProfileChoice)?.Id) !=
                LibraryFrameError.None)
        {
            return;
        }
        RecipeChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnLightSourceSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing ||
            panel.SetLightSourceProfile((LightSourceSelector.SelectedItem as LightSourceOption)?.Id) != LibraryFrameError.None)
        {
            return;
        }
        RecipeChanged?.Invoke(this, EventArgs.Empty);
    }

    private void SetBaseMode(BaseEstimationMode mode)
    {
        if (panel is null || isSynchronizing || panel.SetBaseMode(mode) != LibraryFrameError.None)
        {
            return;
        }

        ShowManualValues(panel);
        RecipeChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnManualBaseChanged(object? sender, InspectorSliderValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (panel is null || isSynchronizing)
        {
            return;
        }

        panel.SetManualBase(
            BaseRedControl.Value,
            BaseGreenControl.Value,
            BaseBlueControl.Value);
        Sync();
        ManualBaseCommitted?.Invoke(this, EventArgs.Empty);
    }

    private static void SetRadioText(RadioButton radio, string text)
    {
        radio.Content = text;
        AutomationProperties.SetName(radio, text);
    }
}
