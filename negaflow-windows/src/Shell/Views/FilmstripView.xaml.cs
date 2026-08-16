using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views;

public sealed partial class FilmstripView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isResizing;
    private bool isSynchronizingSelection;
    private double liveHeight = ShellLayoutMetrics.FilmstripDefaultHeight;
    private IReadOnlyList<LibraryFrameListItem> items = [];

    public FilmstripView()
    {
        InitializeComponent();
        LocalizeControls();
    }

    /// <summary>사용자가 스트립에서 고른 frame 입니다. 현상 패널이 이것을 따라갑니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameSelected;

    /// <summary>
    /// 스트립에 보일 frame 들입니다. 항목은 라이브러리 그리드와 같은 것을 씁니다 — 썸네일이
    /// 도착하면 두 곳이 함께 채워집니다.
    /// </summary>
    public void ShowFrames(IReadOnlyList<LibraryFrameListItem> frames, int selectedIndex)
    {
        ArgumentNullException.ThrowIfNull(frames);
        items = frames;
        isSynchronizingSelection = true;
        try
        {
            FrameStrip.ItemsSource = frames;
            FrameStrip.SelectedIndex = frames.Count == 0
                ? -1
                : Math.Clamp(selectedIndex, 0, frames.Count - 1);
        }
        finally
        {
            isSynchronizingSelection = false;
        }

        bool hasFrames = frames.Count > 0;
        FrameStrip.Visibility = hasFrames ? Visibility.Visible : Visibility.Collapsed;
        EmptyFilmstripPanel.Visibility = hasFrames ? Visibility.Collapsed : Visibility.Visible;
        PreviousButton.IsEnabled = hasFrames;
        NextButton.IsEnabled = hasFrames;
    }

    /// <summary>현상 패널이 다른 경로로 frame 을 바꿨을 때 스트립을 맞춥니다.</summary>
    public void SynchronizeSelection(int selectedIndex)
    {
        if (items.Count == 0)
        {
            return;
        }
        isSynchronizingSelection = true;
        try
        {
            FrameStrip.SelectedIndex = Math.Clamp(selectedIndex, 0, items.Count - 1);
            if (FrameStrip.SelectedItem is { } selected)
            {
                FrameStrip.ScrollIntoView(selected);
            }
        }
        finally
        {
            isSynchronizingSelection = false;
        }
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (isSynchronizingSelection || FrameStrip.SelectedItem is not LibraryFrameListItem item)
        {
            return;
        }
        FrameSelected?.Invoke(this, item);
    }

    /// <summary>
    /// 카드 크기는 스트립 높이에서 나옵니다. 사용자가 경계를 끌면 카드도 같이 커지고 작아집니다.
    /// </summary>
    private void OnFrameContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        _ = sender;
        if (args.ItemContainer is not ListViewItem container)
        {
            return;
        }
        double itemHeight = FilmstripMetrics.ItemHeight(1.0, liveHeight);
        container.Height = itemHeight;
        container.Width = FilmstripMetrics.CardWidth(itemHeight);
        container.Margin = new Thickness(3.0, 0.0, 3.0, 0.0);
        container.Padding = new Thickness(0.0);
        container.CornerRadius = new CornerRadius(9.0);
    }

    private void OnPreviousClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        StepSelection(-1);
    }

    private void OnNextClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        StepSelection(1);
    }

    private void StepSelection(int delta)
    {
        if (items.Count == 0)
        {
            return;
        }
        int next = Math.Clamp(FrameStrip.SelectedIndex + delta, 0, items.Count - 1);
        FrameStrip.SelectedIndex = next;
        FrameStrip.ScrollIntoView(items[next]);
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
        // 카드 크기가 높이에서 나오므로 이미 만들어진 컨테이너도 다시 재어야 합니다.
        if (FrameStrip?.ItemsSource is not null)
        {
            object? selected = FrameStrip.SelectedItem;
            isSynchronizingSelection = true;
            try
            {
                FrameStrip.ItemsSource = null;
                FrameStrip.ItemsSource = items;
                FrameStrip.SelectedItem = selected;
            }
            finally
            {
                isSynchronizingSelection = false;
            }
        }
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
        if (!isResizing && Math.Abs(preferences.FilmstripHeight - liveHeight) > 0.01)
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
