using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class SettingsRootView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isUpdating;

    public SettingsRootView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        UpdateState(state.Current);
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
        SelectCategory(preferences.SelectedSettingsCategory);
        isUpdating = false;
    }

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
