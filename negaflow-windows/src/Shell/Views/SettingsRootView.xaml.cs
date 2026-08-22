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
    private LibraryHostService? library;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    /// <summary>지금 설정으로 구한 폴더들입니다. 설정이 바뀔 때마다 새로 만듭니다.</summary>
    private Negaflow.Shell.Storage.DiskStorageLocations diskStorage =
        new(new Negaflow.Shell.Storage.DiskStorageSettings());
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
        Microsoft.UI.WindowId? windowId = null,
        LibraryHostService? libraryHost = null,
        Negaflow.Shell.Library.ThumbnailService? thumbnailService = null)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        library = libraryHost;
        thumbnails = thumbnailService;
        pickerWindowId = windowId;
        InitializeGeneralTab();
        state.ScannerCapabilitiesChanged += OnScannerCapabilitiesChanged;
        scannerCapabilities = state.ScannerCapabilities;
        InitializeInterfaceWorkflowTabs();
        InitializeDiskTab();
        InitializeExportTab();
        ShortcutGroupPicker.SelectionChanged += OnShortcutGroupChanged;
        state.Changed += OnStateChanged;
        AppResources.LanguageChanged += OnLanguageResourcesChanged;
        LocalizeControls();
        UpdateState(state.Current);
        BuildShortcutGroups();
        BuildShortcutRows();
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// macOS <c>monitorProfileSummary</c> — 화면 색 프로파일 이름입니다. 창이 아직 없거나
    /// 프로파일을 못 읽으면 macOS 와 같은 자리에 대체 문구를 냅니다.
    /// </summary>
    private string MonitorProfileName()
    {
        if (pickerWindowId is { } id &&
            MonitorColorProfile.Name(Microsoft.UI.Win32Interop.GetWindowFromWindowId(id))
                is { Length: > 0 } name)
        {
            return name;
        }
        return AppResources.Get("settingsColorSystemDisplayProfile", "Text");
    }

    /// <summary>설정 창이 열려 있는 동안 언어를 바꾸면 이 창부터 바뀌어야 합니다.</summary>
    private void OnLanguageResourcesChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        LocalizeControls();
        BuildShortcutGroups();
        BuildShortcutRows();
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

    /// <summary>
    /// 앱 언어를 고릅니다. **다시 시작한 뒤에 보입니다** — WinUI 는 리소스를 시작할 때 한 번
    /// 고르므로, 켜져 있는 창의 문자열을 그 자리에서 바꾸면 이미 만들어진 컨트롤만 남아
    /// 두 언어가 섞입니다.
    /// </summary>
    private void OnLanguageSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isUpdating)
        {
            return;
        }
        int index = LanguageComboBox.SelectedIndex;
        if (index < 0 || index >= AppLanguages.All.Count)
        {
            return;
        }
        string language = AppLanguages.All[index];
        workspaceState?.SetLanguage(language);
        // 다음 실행에서도 이 언어로 뜨도록 적어 둡니다.
        Windows.Globalization.ApplicationLanguages.PrimaryLanguageOverride = language;
        // macOS 는 고르는 즉시 모든 문구가 바뀝니다. 다시 시작하게 두지 않습니다.
        AppResources.SetLanguage(language);
    }




    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    /// <summary>
    /// 저장값을 화면에 겁니다.
    /// </summary>
    /// <remarks>
    /// 갱신 중에는 <c>isUpdating</c> 으로 손잡이를 막습니다. 중간에 무엇이 터지면 그 표시가
    /// 켜진 채 남아 <b>설정 창의 모든 컨트롤이 조용히 죽습니다</b> - 눌러도 아무 일도 일어나지
    /// 않습니다. 그래서 finally 로 반드시 풀고, 터진 것은 기록으로 남깁니다.
    /// </remarks>
    private void UpdateState(ShellPreferences preferences)
    {
        isUpdating = true;
        try
        {
            AppearanceComboBox.SelectedIndex = preferences.Appearance switch
            {
                AppearanceMode.Dark => 1,
                AppearanceMode.Light => 2,
                _ => 0,
            };
            diskStorage = new Negaflow.Shell.Storage.DiskStorageLocations(preferences.Disk);
            SynchronizeGeneralTab(preferences);
            SynchronizeInterfaceWorkflowTabs(preferences);
            SynchronizeDiskTab(preferences);
            SynchronizeExportTab(preferences);
            SynchronizeScanTab(preferences);
            LanguageComboBox.SelectedIndex = Math.Max(
                0,
                AppLanguages.All.ToList().IndexOf(AppLanguages.Normalize(preferences.Language)));
            SelectCategory(preferences.SelectedSettingsCategory);
        }
        catch (Exception error)
        {
            Negaflow.Shell.Diagnostics.SettingsChangeLog.Write(
                "sync failed: " + error.GetType().Name + " " + error.Message);
            throw;
        }
        finally
        {
            isUpdating = false;
        }
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
        // x:Uid 로 걸려 있던 문구입니다. 언어를 바꾸면 그 문구만 옛 언어로 남으므로
        // 여기서 겁니다.
        SetCategoryText(GeneralButton, GeneralLabel, "settingsGeneralTab");
        LocalizeGeneralTab();
        SetCategoryText(InterfaceButton, InterfaceLabel, "settingsInterfaceTab");
        SetCategoryText(WorkflowButton, WorkflowLabel, "settingsWorkflowTab");
        LocalizeInterfaceWorkflowTabs();
        SetCategoryText(ScanButton, ScanLabel, "settingsScanTab");
        SetCategoryText(DiskButton, DiskLabel, "settingsDiskTab");
        LocalizeDiskTab();
        SetCategoryText(ExportSettingsButton, ExportLabel, "settingsExportTab");
        LocalizeExportTab();
        SetCategoryText(ShortcutsButton, ShortcutsLabel, "settingsShortcutsTab");
        ShortcutsSection.HeaderText = AppResources.Get("settingsShortcutsTab", "Text");
        ShortcutResetAllRow.Label = AppResources.Get("shortcutResetAll", "Content");
        ShortcutResetAllButton.Content = AppResources.Get("shortcutReset", "Content");
        SetCategoryText(LegalButton, LegalLabel, "settingsLegalTab");
        LocalizeLegalTab();
        LocalizeScanTab();
        SystemAppearanceItem.Content = AppResources.Get("appearanceSystem", "Content");
        DarkAppearanceItem.Content = AppResources.Get("appearanceDark", "Content");
        LightAppearanceItem.Content = AppResources.Get("appearanceLight", "Content");

        // ToggleSwitch 에는 Header, Button 에는 Content 가 있습니다. 리소스 키가
        // .Text/.Value 라서 x:Uid 로 붙이면 WinUI 가 0x802B000A 로 프로세스를 죽입니다.
    }

    private static void SetCategoryText(
        Button button,
        TextBlock label,
        TextBlock heading,
        string resourceKey)
    {
        heading.Text = AppResources.Get(resourceKey, "Text");
        SetCategoryText(button, label, resourceKey);
    }

    /// <summary>
    /// 큰 페이지 제목이 없는 탭용입니다.
    /// </summary>
    /// <remarks>
    /// macOS 설정창은 탭 안에 페이지 제목을 두지 않습니다 — <c>Form(.grouped)</c> 의 섹션
    /// 머리글만 있습니다. 지금 Windows 는 24pt 제목을 따로 두어 맥보다 한 줄 더 내려가 있고,
    /// 옮겨 간 탭부터 이 판을 씁니다.
    /// </remarks>
    private static void SetCategoryText(Button button, TextBlock label, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Text");
        label.Text = text;
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
        AppResources.LanguageChanged -= OnLanguageResourcesChanged;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
            workspaceState.ScannerCapabilitiesChanged -= OnScannerCapabilitiesChanged;
        }
    }
}
