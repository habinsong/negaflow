using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views;

public sealed partial class FilmstripView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isResizing;
    private double liveHeight = ShellLayoutMetrics.FilmstripDefaultHeight;

    public FilmstripView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    public void Initialize(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        state.Changed += OnStateChanged;
        SetHeight(state.Current.FilmstripHeight);
        Unloaded += OnUnloaded;
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
        SetHeight(liveHeight - args.VerticalChange);
    }

    private void OnResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        isResizing = false;
        workspaceState?.SetFilmstripHeight(liveHeight);
    }

    private void OnResizeKeyDown(object sender, KeyRoutedEventArgs args)
    {
        _ = sender;
        double delta = args.Key switch
        {
            VirtualKey.Up => ShellLayoutMetrics.FilmstripResizeStep,
            VirtualKey.Down => -ShellLayoutMetrics.FilmstripResizeStep,
            _ => 0,
        };
        if (delta == 0)
        {
            return;
        }

        SetHeight(liveHeight + delta);
        workspaceState?.SetFilmstripHeight(liveHeight);
        args.Handled = true;
    }

    private void SetHeight(double height)
    {
        liveHeight = Math.Clamp(
            height,
            ShellLayoutMetrics.FilmstripMinimumHeight,
            ShellLayoutMetrics.FilmstripMaximumHeight);
        Height = liveHeight;
        AutomationProperties.SetHelpText(
            ResizeThumb,
            AppResources.FormatInteger(
                "filmstripHeightValueFormat",
                "Value",
                (int)Math.Round(liveHeight)));
    }

    private void LocalizeControls()
    {
        string resize = AppResources.Get("filmstripHeightHelp", "Value");
        AutomationProperties.SetName(ResizeThumb, resize);
        ToolTipService.SetToolTip(ResizeThumb, resize);
        SetNameAndTooltip(PreviousButton, "previousFrame");
        SetNameAndTooltip(NextButton, "nextFrame");
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        if (!isResizing)
        {
            SetHeight(preferences.FilmstripHeight);
        }
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
