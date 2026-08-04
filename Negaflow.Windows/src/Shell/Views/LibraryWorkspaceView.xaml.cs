using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

public sealed partial class LibraryWorkspaceView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isResizing;
    private double liveWidth = ShellLayoutMetrics.LibraryControlsDefaultWidth;

    public LibraryWorkspaceView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        SynchronizeWidth(state.Current.LibraryControlsWidth);
        Unloaded += OnUnloaded;
    }

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (!isResizing && workspaceState is not null)
        {
            SynchronizeWidth(workspaceState.Current.LibraryControlsWidth);
        }
    }

    private void OnResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        isResizing = true;
    }

    private void OnResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        WorkspaceLayout layout = WorkspaceLayoutCalculator.Calculate(Root.ActualWidth);
        liveWidth = layout.ClampLibraryControlsWidth(liveWidth + args.HorizontalChange);
        ControlsPanel.Width = liveWidth;
    }

    private void OnResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        isResizing = false;
        workspaceState?.SetLibraryControlsWidth(liveWidth);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        if (!isResizing)
        {
            SynchronizeWidth(preferences.LibraryControlsWidth);
        }
    }

    private void SynchronizeWidth(double storedWidth)
    {
        liveWidth = WorkspaceLayoutCalculator.Calculate(Root.ActualWidth)
            .ClampLibraryControlsWidth(storedWidth);
        ControlsPanel.Width = liveWidth;
    }

    private void LocalizeControls()
    {
        SetNameAndTooltip(ImportRailButton, "importSection");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(CollectionsRailButton, "libraryCollections");
        string import = AppResources.Get("importSection", "Text");
        ImportHeaderText.Text = import;
        ImportSectionText.Text = import;
        string importImages = AppResources.Get("importImages", "Content");
        SetButtonText(ImportImagesButton, importImages);
        SetButtonText(EmptyImportImagesButton, importImages);
        LibraryCountText.Text = AppResources.FormatIntegers(
            "libraryResultCountFormat",
            "Value",
            0,
            0);
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private static void SetButtonText(Button button, string text)
    {
        button.Content = text;
        AutomationProperties.SetName(button, text);
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
