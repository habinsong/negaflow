using System.Globalization;
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

    public void Bind(DevelopPanelState hostPanel)
    {
        ArgumentNullException.ThrowIfNull(hostPanel);
        panel = hostPanel;
        FilmStockSelector.ItemsSource = BundledFilmBaseOptions.FilmStocks;
        LightSourceSelector.ItemsSource = BundledFilmBaseOptions.LightSources;
        ScannerProfileSelector.ItemsSource = ScannerProfileChoices();
    }

    public void ConfigureRanges(double minimum, double maximum)
    {
        foreach (InspectorSlider slider in new[] { BaseRedControl, BaseGreenControl, BaseBlueControl })
        {
            slider.Minimum = minimum;
            slider.Maximum = maximum;
        }
    }

    public void Localize()
    {
        string baseTitle = AppResources.Get("developTabBase", "Value");
        BaseSectionTitleText.Text = baseTitle;
        AutomationProperties.SetName(BaseControlCard, baseTitle);
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
        ManualBaseControls.Visibility = canEdit && panel.BaseMode == BaseEstimationMode.Manual
            ? Visibility.Visible
            : Visibility.Collapsed;
        UpdateManualBaseText();
    }

    public void ShowManualValues(DevelopPanelState hostPanel)
    {
        isSynchronizing = true;
        try
        {
            ManualBaseRgb shown = hostPanel.ManualBase ?? new ManualBaseRgb(
                hostPanel.SuggestedManualDmin,
                hostPanel.SuggestedManualDmin,
                hostPanel.SuggestedManualDmin);
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
        if (panel?.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto)
        {
            ManualBaseValueText.Text = "Auto";
            return;
        }
        if (panel?.SelectedFrame?.Base.Mode == BaseEstimationMode.Preset)
        {
            FilmStockOption? filmStock = BundledFilmBaseOptions.FilmStocks.FirstOrDefault(
                option => option.Id == panel.SelectedFrame.Base.FilmStockDminId);
            ManualBaseValueText.Text = filmStock?.Id is not null
                ? filmStock.DisplayName
                : panel.SelectedFrame.Base.FilmStockDminId is null
                    ? "Select film stock"
                    : "Film preset unavailable";
            return;
        }
        if (panel?.ManualBase is { } manualBase)
        {
            ManualBaseValueText.Text = string.Create(
                CultureInfo.CurrentCulture,
                $"{manualBase.Red:F3} / {manualBase.Green:F3} / {manualBase.Blue:F3}");
            return;
        }
        ManualBaseValueText.Text = "not set";
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
