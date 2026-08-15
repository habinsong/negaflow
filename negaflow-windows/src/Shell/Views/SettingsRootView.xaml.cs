using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using System.IO;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class SettingsRootView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isUpdating;
    // 파일 선택기는 자기가 어느 창에 붙을지 알아야 합니다.
    private Microsoft.UI.WindowId? pickerWindowId;

    public SettingsRootView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(
        WorkspacePresentationState state,
        Microsoft.UI.WindowId? windowId = null)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        pickerWindowId = windowId;
        state.Changed += OnStateChanged;
        UpdateState(state.Current);
        BuildShortcutGroups();
        BuildShortcutRows();
        Unloaded += OnUnloaded;
    }

    private void OnCategoryClick(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is Button { Tag: string value } &&
            Enum.TryParse(value, out SettingsCategory category))
        {
            workspaceState?.SelectSettingsCategory(category);
        }
    }

    private void OnAppearanceSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        AppearanceMode appearance = AppearanceComboBox.SelectedIndex switch
        {
            1 => AppearanceMode.Dark,
            2 => AppearanceMode.Light,
            _ => AppearanceMode.System,
        };
        workspaceState?.SetAppearance(appearance);
    }

    private void OnExportColorSpaceChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        ExportColorSpace space = ExportColorSpaceComboBox.SelectedIndex switch
        {
            1 => ExportColorSpace.DisplayP3,
            2 => ExportColorSpace.AdobeRgb,
            _ => ExportColorSpace.Srgb,
        };
        workspaceState?.UpdateExport(settings => settings with { ColorSpace = space });
    }

    private void OnSoftProofToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        workspaceState?.UpdateSoftProof(value => value with { IsEnabled = SoftProofToggle.IsOn });
    }

    private void OnSoftProofSimulationChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        SoftProofSimulation simulation = SoftProofSimulationComboBox.SelectedIndex == 1
            ? SoftProofSimulation.PaperAndBlackInk
            : SoftProofSimulation.ProfileOnly;
        workspaceState?.UpdateSoftProof(value => value with { Simulation = simulation });
    }

    private void OnGamutWarningToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        workspaceState?.UpdateSoftProof(
            value => value with { GamutWarningEnabled = GamutWarningToggle.IsOn });
    }

    private async void OnChooseSoftProofProfile(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is null || pickerWindowId is null)
        {
            return;
        }

        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(pickerWindowId.Value);
        picker.FileTypeFilter.Add(".icc");
        picker.FileTypeFilter.Add(".icm");

        SoftProofChooseProfileButton.IsEnabled = false;
        try
        {
            if (await picker.PickSingleFileAsync() is not { } file)
            {
                return;
            }

            // 프로파일을 **고를 때 한 번만** 읽습니다. RGB 프루프에 쓸 수 없는 프로파일이면
            // 고른 것을 반영하지 않고 이유를 보여줍니다 — 쓸 수 없는 것을 고른 채로 두면
            // 프루프가 조용히 다른 값을 씁니다.
            // 읽어 보는 것이 곧 검사입니다. RGB 출력 프로파일이 아니면 null 이 돌아옵니다.
            bool usable = SoftProofProfileReader.Read(file.Path) is not null;
            SoftProofProfileError.Visibility = usable ? Visibility.Collapsed : Visibility.Visible;
            if (usable)
            {
                // 이름과 **자리**를 함께 담습니다. 이름만 담으면 다음 실행에서 용지 흰색을
                // 다시 읽을 수 없어 프루프가 중립 흰색으로 돌아갑니다.
                workspaceState.UpdateSoftProof(value => value with
                {
                    ProfileName = Path.GetFileName(file.Path),
                    ProfilePath = file.Path,
                });
            }
        }
        finally
        {
            SoftProofChooseProfileButton.IsEnabled = true;
        }
    }

    private void OnResetSoftProofProfile(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SoftProofProfileError.Visibility = Visibility.Collapsed;
        workspaceState?.UpdateSoftProof(value => value with
        {
            ProfileName = string.Empty,
            ProfilePath = string.Empty,
        });
    }

    /// <summary>
    /// 인화 대상이 쓸 출력 프로파일입니다. macOS 처럼 프루프 프로파일과 따로 둡니다 — 화면을
    /// 보는 목적지와 종이에 찍는 목적지는 같지 않습니다.
    /// </summary>
    private async void OnChoosePrinterProfile(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is null || pickerWindowId is null)
        {
            return;
        }
        Microsoft.Windows.Storage.Pickers.FileOpenPicker picker = new(pickerWindowId.Value);
        picker.FileTypeFilter.Add(".icc");
        picker.FileTypeFilter.Add(".icm");
        PrinterProfileButton.IsEnabled = false;
        try
        {
            if (await picker.PickSingleFileAsync() is not { } file)
            {
                return;
            }
            bool usable = SoftProofProfileReader.Read(file.Path) is not null;
            PrinterProfileError.Visibility = usable ? Visibility.Collapsed : Visibility.Visible;
            if (usable)
            {
                workspaceState.UpdateSoftProof(value => value with
                {
                    PrinterProfilePath = file.Path,
                });
            }
        }
        finally
        {
            PrinterProfileButton.IsEnabled = true;
        }
    }

    private void OnResetPrinterProfile(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        PrinterProfileError.Visibility = Visibility.Collapsed;
        workspaceState?.UpdateSoftProof(value => value with { PrinterProfilePath = string.Empty });
    }

    private void OnImageHashToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }

        workspaceState?.SetImageContentHashMode(
            ImageHashToggle.IsOn ? ImageContentHashMode.Sha256 : ImageContentHashMode.Off);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        isUpdating = true;
        AppearanceComboBox.SelectedIndex = preferences.Appearance switch
        {
            AppearanceMode.Dark => 1,
            AppearanceMode.Light => 2,
            _ => 0,
        };
        ImageHashToggle.IsOn = preferences.ImageContentHash == ImageContentHashMode.Sha256;
        ExportColorSpaceComboBox.SelectedIndex = preferences.Export.ColorSpace switch
        {
            ExportColorSpace.DisplayP3 => 1,
            ExportColorSpace.AdobeRgb => 2,
            _ => 0,
        };
        // 요약 줄은 고른 값이 아니라 형식이 실제로 낼 수 있는 값을 적습니다 — JPEG 을 고른 채
        // "Adobe RGB" 라고 적혀 있으면 파일과 화면이 어긋나기 때문입니다.
        ExportColorSpaceSummary.Text = ColorSpaceLabel(preferences.Export.EffectiveColorSpace);

        SoftProofPreferences proof = preferences.SoftProof;
        SoftProofToggle.IsOn = proof.IsEnabled;
        // macOS 는 프루프가 꺼져 있으면 아래 줄들을 아예 그리지 않습니다.
        SoftProofDetailPanel.Visibility = proof.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
        SoftProofSimulationComboBox.SelectedIndex =
            proof.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1 : 0;
        // 계산할 수 없는 경고는 켤 수 있게 두지 않습니다. ICM 이 이 색공간으로 gamut-check
        // 변환을 만들 수 있을 때만 살아납니다 — macOS 도 같은 조건으로 끕니다.
        bool gamutAvailable = NativeGamutCheck.IsSupported(preferences.Export.EffectiveColorSpace);
        GamutWarningToggle.IsEnabled = gamutAvailable;
        GamutUnavailableReason.Visibility =
            gamutAvailable ? Visibility.Collapsed : Visibility.Visible;
        GamutWarningToggle.IsOn = gamutAvailable && proof.GamutWarningEnabled;
        // 프로파일을 고르지 않았으면 내보내기 색공간의 이름을 씁니다 — macOS 도 프로파일이
        // 없으면 같은 값을 보여줍니다.
        string profileName = proof.ProfileName.Length != 0
            ? proof.ProfileName
            : ColorSpaceLabel(preferences.Export.EffectiveColorSpace);
        SoftProofProfileName.Text = profileName;
        // 되돌릴 것이 있을 때만 되돌리기를 보여줍니다. macOS 도 같은 조건입니다.
        SoftProofResetProfileButton.Visibility =
            proof.ProfileName.Length != 0 ? Visibility.Visible : Visibility.Collapsed;
        PrinterProfileName.Text = proof.PrinterProfilePath.Length != 0
            ? Path.GetFileName(proof.PrinterProfilePath)
            : AppResources.Get("settingsColorUnassigned", "Text");
        PrinterProfileResetButton.Visibility =
            proof.PrinterProfilePath.Length != 0 ? Visibility.Visible : Visibility.Collapsed;
        SoftProofSummary.Text = proof.IsEnabled
            ? $"{profileName} · {SimulationLabel(proof.Simulation)}"
            : AppResources.Get("settingsColorOff", "Text");
        ScannerEmulationSummary.Text = AppResources.Get("settingsColorUnassigned", "Text");
        SelectCategory(preferences.SelectedSettingsCategory);
        isUpdating = false;
    }

    private static string SimulationLabel(SoftProofSimulation simulation) =>
        simulation == SoftProofSimulation.PaperAndBlackInk
            ? AppResources.Get("settingsSoftProofPaperAndBlack", "Content")
            : AppResources.Get("settingsSoftProofProfileOnly", "Content");

    // macOS ExportColorSpace.uiLabel 과 같은 문자열입니다. 색공간 이름은 번역하지 않습니다.
    private static string ColorSpaceLabel(ExportColorSpace space) => space switch
    {
        ExportColorSpace.DisplayP3 => "Display P3",
        ExportColorSpace.AdobeRgb => "Adobe RGB",
        _ => "sRGB",
    };

    private void SelectCategory(SettingsCategory category)
    {
        SetPageState(GeneralButton, GeneralPage, category == SettingsCategory.General);
        SetPageState(InterfaceButton, InterfacePage, category == SettingsCategory.Interface);
        SetPageState(WorkflowButton, WorkflowPage, category == SettingsCategory.Workflow);
        SetPageState(ScanButton, ScanPage, category == SettingsCategory.Scan);
        SetPageState(DiskButton, DiskPage, category == SettingsCategory.Disk);
        SetPageState(ExportSettingsButton, ExportPage, category == SettingsCategory.Export);
        SetPageState(ShortcutsButton, ShortcutsPage, category == SettingsCategory.Shortcuts);
        SetPageState(LegalButton, LegalPage, category == SettingsCategory.Legal);
    }

    private static void SetPageState(Button button, FrameworkElement page, bool selected)
    {
        page.Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
        button.Background = selected
            ? new SolidColorBrush(Windows.UI.Color.FromArgb(0x2D, 0x6B, 0x8B, 0xFF))
            : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        button.FontWeight = selected ? FontWeights.SemiBold : FontWeights.Normal;
        button.Opacity = selected ? 1 : 0.72;
        AutomationProperties.SetHelpText(
            button,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
    }

    private void LocalizeControls()
    {
        SetCategoryText(GeneralButton, GeneralLabel, GeneralHeading, "settingsGeneralTab");
        SetCategoryText(InterfaceButton, InterfaceLabel, InterfaceHeading, "settingsInterfaceTab");
        SetCategoryText(WorkflowButton, WorkflowLabel, WorkflowHeading, "settingsWorkflowTab");
        SetCategoryText(ScanButton, ScanLabel, ScanHeading, "settingsScanTab");
        SetCategoryText(DiskButton, DiskLabel, DiskHeading, "settingsDiskTab");
        SetCategoryText(ExportSettingsButton, ExportLabel, ExportHeading, "settingsExportTab");
        SetCategoryText(ShortcutsButton, ShortcutsLabel, ShortcutsHeading, "settingsShortcutsTab");
        SetCategoryText(LegalButton, LegalLabel, LegalHeading, "settingsLegalTab");

        AppearanceLabel.Text = AppResources.Get("settingsAppearancePicker", "Text");
        SystemAppearanceItem.Content = AppResources.Get("appearanceSystem", "Content");
        DarkAppearanceItem.Content = AppResources.Get("appearanceDark", "Content");
        LightAppearanceItem.Content = AppResources.Get("appearanceLight", "Content");
        SourceDpiItem.Content = AppResources.Get("settingsSourceDPI", "Text");
        FullSizeItem.Content = AppResources.Get("exportFullSize", "Text");

        LocalizeToggle(DeveloperModeToggle);
        LocalizeToggle(ClippingOverlayToggle);
        LocalizeToggle(ScannerSimulatorToggle);
        LocalizeToggle(DevelopImportsToggle);
        LocalizeToggle(ImageHashToggle);
    }

    private static void SetCategoryText(
        Button button,
        TextBlock label,
        TextBlock heading,
        string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        label.Text = text;
        heading.Text = text;
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void LocalizeToggle(ToggleSwitch toggle)
    {
        toggle.OffContent = AppResources.Get("off", "OffContent");
        toggle.OnContent = AppResources.Get("on", "OnContent");
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
    }
}
