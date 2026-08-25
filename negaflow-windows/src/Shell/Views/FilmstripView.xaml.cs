using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;
using Windows.System;

namespace Negaflow.Shell.Views;

public sealed partial class FilmstripView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private bool isResizing;
    private bool isSynchronizingSelection;
    private bool itemClickRaised;

    /// <summary>미뤄 둔 선택 맞추기가 큐에 올라가 있는지입니다.</summary>
    private bool isDeferredSelectionSync;

    private IReadOnlyList<string> pendingSelection = [];

    private string? pendingActiveFrameId;
    private double liveHeight = ShellLayoutMetrics.FilmstripDefaultHeight;
    private IReadOnlyList<LibraryFrameListItem> items = [];

    public FilmstripView()
    {
        InitializeComponent();
        // "이미지 없음"·앞/뒤 사진·높이 안내가 리소스에서 옵니다.
        LocalizedElement.Track(this, LocalizeControls);
    }

    /// <summary>사용자가 스트립에서 고른 frame 입니다. 현상 패널이 이것을 따라갑니다.</summary>
    public event EventHandler<LibraryFrameListItem>? FrameSelected;

    /// <summary>
    /// 썸네일에서 오른쪽 단추를 눌렀습니다. 메뉴는 라이브러리 화면이 들고 있는 그 하나를
    /// 씁니다 — 여기서 따로 만들면 두 메뉴가 갈라집니다.
    /// </summary>
    public event EventHandler<FilmstripMenuRequest>? FrameMenuRequested;

    private void OnFrameRightTapped(object sender, RightTappedRoutedEventArgs args)
    {
        if (sender is not FrameworkElement { DataContext: LibraryFrameListItem item } thumbnail)
        {
            return;
        }
        args.Handled = true;
        FrameMenuRequested?.Invoke(
            this,
            new FilmstripMenuRequest(thumbnail, item, args.GetPosition(thumbnail)));
    }

    /// <summary>
    /// 썸네일 하나가 도착했습니다. <b>스트립이 실제로 걸고 있는 객체</b>에 넣습니다.
    /// </summary>
    /// <remarks>
    /// 목록을 다시 지으면 <c>ItemsSource</c> 에는 새 항목 객체가 오는데, 스트립은 아이디가
    /// 같으면 <b>예전 객체</b>를 그대로 붙들고 있습니다(<see cref="ShowFrames"/> 의 깜빡임
    /// 방지). 그래서 새 객체만 갱신하면 스트립은 영영 비어 있습니다 - 앱을 켜자마자 현상뷰
    /// 하단 스트립이 통째로 비어 있다가, 다른 일이 <see cref="ShowFrames"/> 를 다시 부를 때만
    /// 한꺼번에 돌아오던 원인입니다.
    /// </remarks>
    public void ApplyThumbnail(string frameId, ImageSource? thumbnail)
    {
        if (string.IsNullOrEmpty(frameId) || thumbnail is null)
        {
            return;
        }
        for (int index = 0; index < items.Count; ++index)
        {
            if (string.Equals(items[index].Id, frameId, StringComparison.Ordinal))
            {
                items[index].Thumbnail = thumbnail;
                return;
            }
        }
    }

    /// <summary>
    /// 스트립에 보일 frame 들입니다. 항목은 라이브러리 그리드와 같은 것을 씁니다 — 썸네일이
    /// 도착하면 두 곳이 함께 채워집니다.
    /// </summary>
    public void ShowFrames(IReadOnlyList<LibraryFrameListItem> frames, int selectedIndex)
    {
        ArgumentNullException.ThrowIfNull(frames);
        // 같은 사진 목록이면 `ItemsSource` 를 다시 걸지 않습니다.
        //
        // 선택이 바뀔 때마다 새 목록 객체가 오는데, 그것을 그대로 걸면 ListView 가 칸을 전부
        // 헐고 다시 짓습니다. 그 일이 **클릭 콜백 안에서** 일어나면 WinUI 가 자기 이벤트 처리
        // 도중에 항목이 사라진 것을 보고 COMException 으로 앱을 내립니다 — Ctrl 로 여러 장을
        // 고를 때 앱이 죽던 자리입니다.
        bool sameItems = items.Count == frames.Count;
        for (int index = 0; sameItems && index < frames.Count; ++index)
        {
            sameItems = string.Equals(items[index].Id, frames[index].Id, StringComparison.Ordinal);
        }
        if (sameItems)
        {
            // 목록에 걸린 것은 <b>예전 객체</b>입니다. 새 목록 객체로 갈아 끼우지 않는 대신
            // 새로 도착한 썸네일만 옮겨 담습니다. 갈아 끼우면 선택이 목록에 없는 객체를
            // 가리켜 선택 막대가 튀고, 썸네일만 버리면 사진이 영영 비어 보입니다.
            for (int index = 0; index < frames.Count; ++index)
            {
                if (frames[index].Thumbnail is { } thumbnail)
                {
                    items[index].Thumbnail = thumbnail;
                }
            }
        }
        else
        {
            items = frames;
        }
        isSynchronizingSelection = true;
        try
        {
            if (!sameItems)
            {
                FrameStrip.ItemsSource = frames;
                // 목록이 그대로일 때 여기서 한 장으로 되돌리면, 여러 장을 고른 순간 선택
                // 막대가 한 장으로 튀었다가 한 박자 뒤에 되돌아옵니다 — 그 깜빡임 때문에
                // 목록이 실제로 바뀌었을 때만 자리를 잡습니다. 무엇이 골라졌는지는
                // 라이브러리가 들고 있고 `SynchronizeSelection` 이 그것을 그대로 냅니다.
                FrameStrip.SelectedIndex = frames.Count == 0
                    ? -1
                    : Math.Clamp(selectedIndex, 0, frames.Count - 1);
            }
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

    /// <summary>
    /// 여러 장 고르기를 보여 줍니다. macOS 필름스트립도 고른 사진을 모두 밝게 냅니다.
    /// </summary>
    /// <remarks>
    /// 목록의 선택은 <b>보여 주기</b>일 뿐입니다. 무엇이 골라졌는지는 라이브러리가 들고
    /// 있고, 누를 때의 규칙은 macOS <c>selectFrame</c> 그대로 컨트롤러가 정합니다.
    /// </remarks>
    public void SynchronizeSelection(IReadOnlyList<string> selectedFrameIds, string? activeFrameId)
    {
        ArgumentNullException.ThrowIfNull(selectedFrameIds);
        if (items.Count == 0)
        {
            return;
        }
        // 목록의 선택을 <b>클릭 콜백 안에서</b> 갈아 끼우면 WinUI 가 자기 이벤트 처리 도중에
        // 항목이 바뀐 것을 보고 앱을 내립니다. 한 박자 뒤로 미뤄 그 처리 밖에서 맞춥니다.
        pendingSelection = [.. selectedFrameIds];
        pendingActiveFrameId = activeFrameId;
        if (isDeferredSelectionSync)
        {
            // 이미 한 번 예약해 두었습니다. 값만 갈아 두면 그 한 번이 마지막 값을 씁니다 —
            // 예약 안에서 다시 예약하면 큐가 영영 비지 않아 화면이 멈춥니다.
            return;
        }
        isDeferredSelectionSync = true;
        if (!DispatcherQueue.TryEnqueue(() =>
            {
                isDeferredSelectionSync = false;
                ApplySelection(pendingSelection, pendingActiveFrameId);
            }))
        {
            isDeferredSelectionSync = false;
        }
    }

    private void ApplySelection(IReadOnlyList<string> selectedFrameIds, string? activeFrameId)
    {
        if (items.Count == 0)
        {
            return;
        }
        HashSet<string> wanted = [.. selectedFrameIds];
        isSynchronizingSelection = true;
        try
        {
            FrameStrip.SelectedItems.Clear();
            LibraryFrameListItem? active = null;
            foreach (LibraryFrameListItem item in items)
            {
                if (!wanted.Contains(item.Id))
                {
                    continue;
                }
                if (string.Equals(item.Id, activeFrameId, StringComparison.Ordinal))
                {
                    active = item;
                    continue;
                }
                FrameStrip.SelectedItems.Add(item);
            }
            // 마지막에 넣은 것이 WinUI 의 활성 항목이 됩니다 — 여러 장 선택도 그대로 남습니다.
            if (active is not null)
            {
                FrameStrip.SelectedItems.Add(active);
                FrameStrip.ScrollIntoView(active);
            }
        }
        finally
        {
            isSynchronizingSelection = false;
        }
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

    private void OnFrameItemClick(object sender, ItemClickEventArgs args)
    {
        _ = sender;
        if (isSynchronizingSelection || args.ClickedItem is not LibraryFrameListItem item)
        {
            return;
        }
        // 이미 고른 칸을 다시 눌러도, 빠른 클릭으로 SelectionChanged 가 빠져도 여기로 옵니다.
        itemClickRaised = true;
        FrameSelected?.Invoke(this, item);
    }

    /// <summary>
    /// 칸 안에 그리는 선택 막대의 값을 목록의 선택 하나에서 채웁니다. 선택이 바뀌는 길이
    /// 여럿이므로 <b>알림 한 곳</b>에서만 채웁니다 — 길마다 채우면 한 곳만 빠져도 막대가
    /// 옛 칸에 남습니다.
    /// </summary>
    private void SynchronizeSelectionFlags()
    {
        if (FrameStrip.ItemsSource is not IReadOnlyList<LibraryFrameListItem> shown)
        {
            return;
        }
        HashSet<LibraryFrameListItem> selected =
            [.. FrameStrip.SelectedItems.OfType<LibraryFrameListItem>()];
        foreach (LibraryFrameListItem item in shown)
        {
            item.IsSelected = selected.Contains(item);
        }
    }

    private void OnFrameSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        SynchronizeSelectionFlags();
        if (itemClickRaised)
        {
            itemClickRaised = false;
            return;
        }
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
        NoImagesLocalized.Text = AppResources.Get("noImages", "Text");
        string resize = AppResources.Get("filmstripHeightHelp", "Value");
        AutomationProperties.SetName(ResizeThumb, resize);
        ToolTipService.SetToolTip(ResizeThumb, resize);
        SetNameAndTooltip(PreviousButton, "previousFrame");
        SetNameAndTooltip(NextButton, "nextFrame");
        // 높이 안내는 지금 높이를 담은 서식이라 여기서 다시 만들어야 합니다.
        AutomationProperties.SetHelpText(
            ResizeThumb,
            AppResources.FormatInteger(
                "filmstripHeightValueFormat",
                "Value",
                (int)Math.Round(liveHeight)));
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

/// <summary>필름스트립 썸네일에서 오른쪽 단추를 누른 자리입니다.</summary>
public sealed record FilmstripMenuRequest(
    FrameworkElement Anchor,
    LibraryFrameListItem Item,
    Windows.Foundation.Point Position);
