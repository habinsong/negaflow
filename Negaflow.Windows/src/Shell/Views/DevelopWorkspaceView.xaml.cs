using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Layout;

namespace Negaflow.Shell.Views;

public sealed partial class DevelopWorkspaceView : UserControl
{
    private readonly ThreePaneResizeController resizeController = new();
    private WorkspacePresentationState? workspaceState;

    public DevelopWorkspaceView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(
        WorkspacePresentationState state,
        NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        state.Changed += OnStateChanged;
        Filmstrip.Initialize(state);
        StatusBar.Initialize(nativeEngineStatus);
        UpdateState(state.Current);
        Unloaded += OnUnloaded;
    }

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            SynchronizeWidths(workspaceState.Current);
        }
    }

    private void OnLeftResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginLeft();
    }

    private void OnLeftResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        LeftPanel.Width = resizeController.UpdateLeft(args.HorizontalChange, Root.ActualWidth);
        UpdateCompactRail();
    }

    private void OnLeftResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetSidebarWidth(resizeController.EndLeft());
    }

    private void OnRightResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginRight();
    }

    private void OnRightResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        RightPanel.Width = resizeController.UpdateRight(args.HorizontalChange, Root.ActualWidth);
    }

    private void OnRightResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetInspectorWidth(resizeController.EndRight());
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        LeftPanel.Visibility = preferences.IsSidebarVisible ? Visibility.Visible : Visibility.Collapsed;
        LeftDivider.Visibility = LeftPanel.Visibility;
        LeftResizeThumb.Visibility = LeftPanel.Visibility;
        RightPanel.Visibility = preferences.IsInspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        RightDivider.Visibility = RightPanel.Visibility;
        RightResizeThumb.Visibility = RightPanel.Visibility;
        Filmstrip.Visibility = preferences.IsFilmstripVisible ? Visibility.Visible : Visibility.Collapsed;
        SynchronizeWidths(preferences);
    }

    private void SynchronizeWidths(ShellPreferences preferences)
    {
        resizeController.Synchronize(
            preferences.SidebarWidth,
            preferences.InspectorWidth,
            Root.ActualWidth);
        LeftPanel.Width = resizeController.LeftWidth;
        RightPanel.Width = resizeController.RightWidth;
        UpdateCompactRail();
    }

    private void UpdateCompactRail()
    {
        LeftRailColumn.Width = new GridLength(
            LeftPanel.Width < ShellLayoutMetrics.SidebarCompactThreshold
                ? ShellLayoutMetrics.SidebarCompactRailWidth
                : ShellLayoutMetrics.SidebarRegularRailWidth);
    }

    private void LocalizeControls()
    {
        SetNameAndTooltip(LibraryRailButton, "sidebarLibrary");
        SetNameAndTooltip(FilesRailButton, "sidebarFiles");
        SetNameAndTooltip(VersionsRailButton, "sidebarVersions");
        SetNameAndTooltip(PresetsRailButton, "sidebarPresets");
        SetNameAndTooltip(FilmRailButton, "sidebarFilm");
        SetNameAndTooltip(OutputRailButton, "sidebarOutput");
        LibraryHeaderText.Text = AppResources.Get("sidebarLibrary", "Text");
        string noFrame = AppResources.Get("noFrame", "Text");
        NoFrameHeaderText.Text = noFrame;
        NoFrameLeftText.Text = noFrame;
        NoFrameInspectorText.Text = noFrame;
        DevelopHeaderText.Text = AppResources.Get("menuDevelop", "Text");
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
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
