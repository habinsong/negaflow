using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class WorkspaceToolbarView : UserControl
{
    private WorkspacePresentationState? workspaceState;

    public WorkspaceToolbarView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public event EventHandler? SettingsRequested;

    public UIElement TitleBarElement => TitleBarRoot;

    public void UpdateCaptionInsets(double left, double right)
    {
        LeftCaptionInsetColumn.Width = new GridLength(Math.Max(0, left));
        RightCaptionInsetColumn.Width = new GridLength(Math.Max(0, right));
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        UpdateState(state.Current);
        Unloaded += OnUnloaded;
    }

    private void OnLibraryClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Library);
    }

    private void OnDevelopClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
    }

    private void OnPrintClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Print);
    }

    private void OnSidebarClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleSidebar();
    }

    private void OnFilmstripClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleFilmstrip();
    }

    private void OnInspectorClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleInspector();
    }

    private void OnSystemAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.System);
    }

    private void OnDarkAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.Dark);
    }

    private void OnLightAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.Light);
    }

    private void OnSettingsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        SetWorkspaceSelection(LibraryButton, preferences.SelectedWorkspace == WorkspaceModule.Library);
        SetWorkspaceSelection(DevelopButton, preferences.SelectedWorkspace == WorkspaceModule.Develop);
        SetWorkspaceSelection(PrintButton, preferences.SelectedWorkspace == WorkspaceModule.Print);
        SetPanelState(SidebarButton, preferences.IsSidebarVisible);
        SetPanelState(FilmstripButton, preferences.IsFilmstripVisible);
        SetPanelState(InspectorButton, preferences.IsInspectorVisible);
    }

    private static void SetWorkspaceSelection(Button button, bool selected)
    {
        button.FontWeight = selected ? FontWeights.Bold : FontWeights.SemiBold;
        button.Opacity = selected ? 1 : 0.68;
        AutomationProperties.SetHelpText(
            button,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
    }

    private static void SetPanelState(Button button, bool isOn)
    {
        button.Opacity = isOn ? 1 : 0.52;
        AutomationProperties.SetHelpText(
            button,
            AppResources.Get(isOn ? "on" : "off", "Value"));
    }

    private void LocalizeControls()
    {
        LibraryButton.Content = AppResources.Get("menuLibrary", "Content");
        DevelopButton.Content = AppResources.Get("menuDevelop", "Content");
        PrintButton.Content = AppResources.Get("menuPrint", "Content");
        SetNameAndTooltip(
            QuickExportButton,
            AppResources.Get("commandQuickExport", "Text"));
        SetNameAndTooltip(ExportButton, AppResources.Get("commandExport", "Text"));
        SetNameAndTooltip(
            SidebarButton,
            AppResources.Get("commandShowHideSidebar", "Value"));
        SetNameAndTooltip(
            FilmstripButton,
            AppResources.Get("commandShowHideFilmstrip", "Value"));
        SetNameAndTooltip(
            InspectorButton,
            AppResources.Get("commandShowHideInspector", "Value"));
        SetNameAndTooltip(
            AppearanceButton,
            AppResources.Get("settingsAppearancePicker", "Value"));
        SetNameAndTooltip(
            UtilityButton,
            AppResources.Get("commandWorkspaceOptions", "Value"));
        SystemAppearanceItem.Text = AppResources.Get("appearanceSystem", "Text");
        DarkAppearanceItem.Text = AppResources.Get("appearanceDark", "Text");
        LightAppearanceItem.Text = AppResources.Get("appearanceLight", "Text");
        SettingsItem.Text = AppResources.Get("commandSettings", "Text");
        DiagnosticsItem.Text = AppResources.Get("commandDiagnostics", "Text");
    }

    private static void SetNameAndTooltip(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
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
