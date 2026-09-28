using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Diagnostics;
using Negaflow.Shell.Library;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 창 맨 아래 한 줄입니다. 왼쪽은 엔진 상태, 오른쪽은 필름스트립의 크기·차례·범위입니다 —
/// macOS <c>statusBar</c> 와 같은 자리, 같은 차례입니다.
/// </summary>
public sealed partial class StatusBarView : UserControl
{
    /// <summary>macOS <c>FilmstripSizing</c> 과 같은 값입니다.</summary>
    private const double MinimumItemScale = ShellLayoutMetrics.FilmstripMinimumItemScale;

    private const double MaximumItemScale = ShellLayoutMetrics.FilmstripMaximumItemScale;

    /// <summary>macOS 의 한 걸음입니다(`effectiveScale ± 0.08`).</summary>
    private const double ScaleStep = 0.08;

    /// <summary>마지막으로 받은 엔진 상태입니다. 언어가 바뀌면 이것으로 다시 겁니다.</summary>
    private NativeEngineStatus? status;

    private WorkspacePresentationState? workspaceState;

    public StatusBarView()
    {
        InitializeComponent();
        stateHideTimer.Tick += (_, _) =>
        {
            stateHideTimer.Stop();
            StateText.Text = string.Empty;
        };
        messageHideTimer.Tick += (_, _) =>
        {
            messageHideTimer.Stop();
            MessageText.Visibility = Visibility.Collapsed;
        };
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        Localize();
    }

    private static readonly TimeSpan MessageDuration = TimeSpan.FromSeconds(3);

    private readonly DispatcherTimer messageHideTimer = new()
    {
        Interval = MessageDuration,
    };

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AppStatusMessage.Shared.Changed += OnStatusMessageChanged;
        AppErrorLog.Shared.Changed += OnErrorLogChanged;
        RenderIndicator();
        // 현상 화면은 늦게 세워집니다. 열기 알림은 그 전에 오므로, 3 초가 지나지 않았으면
        // 남은 시간만큼 띄웁니다 — macOS 는 막대가 먼저 떠 있어 이 차이가 없습니다.
        TimeSpan remaining = MessageDuration - (DateTimeOffset.UtcNow - AppStatusMessage.Shared.PostedAt);
        if (remaining > TimeSpan.Zero)
        {
            ShowMessage(remaining);
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AppStatusMessage.Shared.Changed -= OnStatusMessageChanged;
        AppErrorLog.Shared.Changed -= OnErrorLogChanged;
        messageHideTimer.Stop();
    }

    private void OnStatusMessageChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        _ = DispatcherQueue.TryEnqueue(() => ShowMessage(MessageDuration));
    }

    private void OnErrorLogChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        _ = DispatcherQueue.TryEnqueue(RenderIndicator);
    }

    /// <summary>macOS <c>StatusBarMessageRow.scheduleDismissal</c> — 띄우고 3 초 뒤 사라집니다.</summary>
    private void ShowMessage(TimeSpan duration)
    {
        string message = AppStatusMessage.Shared.Message;
        messageHideTimer.Stop();
        MessageText.Text = message;
        MessageText.Visibility = message.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (message.Length != 0)
        {
            messageHideTimer.Interval = duration;
            messageHideTimer.Start();
        }
    }

    /// <summary>
    /// macOS <c>StatusPhaseIndicator</c> — 최근 문제가 있으면 점이 빨갛고, 올리면 최신 문제가
    /// 보입니다. 없으면 엔진 상태 색 그대로입니다.
    /// </summary>
    private void RenderIndicator()
    {
        AppErrorEntry? latest = AppErrorLog.Shared.Latest;
        string help = latest?.Message ?? AppResources.Get("diagnosticsNoProblems", "Text");
        ToolTipService.SetToolTip(StateIndicatorHitArea, help);
        AutomationProperties.SetName(StateIndicatorHitArea, help);
        StateIndicator.Fill = latest is not null
            ? new SolidColorBrush(Microsoft.UI.Colors.Red)
            : new SolidColorBrush(status?.IsAvailable == false
                ? Microsoft.UI.Colors.OrangeRed
                : Microsoft.UI.Colors.LimeGreen);
    }

    /// <summary>macOS <c>RecentErrorsPopover</c> — 최근 문제가 있을 때만 엽니다.</summary>
    private void OnIndicatorTapped(object sender, TappedRoutedEventArgs args)
    {
        _ = args;
        if (!AppErrorLog.Shared.HasEntries)
        {
            return;
        }
        FillProblemsList();
        FlyoutBase.ShowAttachedFlyout((FrameworkElement)sender);
    }

    private void OnClearProblemsClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        AppErrorLog.Shared.Clear();
        FillProblemsList();
    }

    /// <summary>최신이 위입니다. 비면 "문제 없음" 한 줄입니다(macOS 와 같음).</summary>
    private void FillProblemsList()
    {
        ProblemsTitle.Text = AppResources.Get("diagnosticsRecentProblemsTitle", "Text");
        string clear = AppResources.Get("diagnosticsClearProblems", "Text");
        ToolTipService.SetToolTip(ClearProblemsButton, clear);
        AutomationProperties.SetName(ClearProblemsButton, clear);
        IReadOnlyList<AppErrorEntry> entries = AppErrorLog.Shared.Entries;
        ClearProblemsButton.IsEnabled = entries.Count != 0;
        ProblemsList.Children.Clear();
        if (entries.Count == 0)
        {
            ProblemsList.Children.Add(new TextBlock
            {
                Text = AppResources.Get("diagnosticsNoProblems", "Text"),
                Opacity = 0.6,
            });
            return;
        }
        foreach (AppErrorEntry entry in entries.Reverse())
        {
            StackPanel item = new() { Spacing = 2 };
            item.Children.Add(new TextBlock { Text = entry.Message, TextWrapping = TextWrapping.Wrap });
            item.Children.Add(new TextBlock
            {
                Text = entry.At.LocalDateTime.ToString("t", System.Globalization.CultureInfo.CurrentCulture),
                FontSize = 10,
                Opacity = 0.6,
            });
            ProblemsList.Children.Add(item);
        }
    }

    /// <summary>필름스트립의 크기·차례·범위가 바뀌었습니다. 두 화면이 목록을 다시 냅니다.</summary>
    public event EventHandler? FilmstripPresentationChanged;

    /// <summary>언어가 바뀌면 다시 겁니다. x:Uid 는 읽을 때 한 번만 풀리기 때문입니다.</summary>
    public void Localize()
    {
        BuildSortMenu();
        BuildScopeMenu();
        Render();
        // 상태 문구도 리소스에서 옵니다 — 앞 판은 처음 받은 언어에 그대로 머물렀습니다.
        if (status is { } current)
        {
            ShowState(AppResources.Get(
                current.IsAvailable ? "idleStatus" : "capabilityUnavailable",
                "Value"));
        }
    }

    /// <summary>
    /// 상태 글자를 띄우고 <b>잠시 뒤 지웁니다.</b>
    /// </summary>
    /// <remarks>
    /// macOS <c>StatusPhaseIndicator</c> 주석 그대로입니다 — 단계가 바뀌면 이름을 띄우고 3 초
    /// 뒤 사라집니다. 상태가 계속 붙어 있으면 하단 바가 늘 지저분하고 가운데 메시지와 겹칠
    /// 여지도 커집니다. 새 상태가 들어오면 다시 띄우고 시계를 되돌립니다. 자리(폭 92)는
    /// 그대로 두어 오른쪽 칸이 밀리지 않습니다.
    /// </remarks>
    private void ShowState(string text)
    {
        StateText.Text = text;
        stateHideTimer.Stop();
        stateHideTimer.Start();
    }

    private readonly DispatcherTimer stateHideTimer = new()
    {
        Interval = TimeSpan.FromSeconds(3),
    };

    public void Initialize(NativeEngineStatus status)
    {
        ArgumentNullException.ThrowIfNull(status);
        this.status = status;
        ShowState(AppResources.Get(
            status.IsAvailable ? "idleStatus" : "capabilityUnavailable",
            "Value"));
        StateDetail.Text = status.Detail;
        RenderIndicator();
    }

    /// <summary>저장된 값을 읽고 쓰는 자리입니다. 셸이 꽂아 줍니다.</summary>
    public void Attach(WorkspacePresentationState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        Render();
    }

    private ShellPreferences? Preferences => workspaceState?.Current;

    /// <summary>지금 값을 세 컨트롤에 되비춥니다.</summary>
    public void Render()
    {
        if (Preferences is not { } preferences)
        {
            return;
        }
        // **저장된 값이 아니라 실효 배율**을 냅니다. 스트립이 낮으면 1.34 를 저장해도 그
        // 크기로 설 자리가 없으므로, macOS 는 잴 수 있는 값을 보여 주고 그 값에서 한 걸음씩
        // 움직입니다(`ContentView+CenterStatus`).
        double effectiveScale = EffectiveScale(preferences);
        double maximumScale = FilmstripMetrics.MaximumEffectiveItemScale(
            preferences.FilmstripItemScale,
            preferences.FilmstripHeight);
        int percent = (int)Math.Round(effectiveScale * 100.0);
        ThumbnailSizeButton.Content = string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{percent}%");
        ThumbnailSmallerButton.IsEnabled = effectiveScale > MinimumItemScale + 0.001;
        ThumbnailLargerButton.IsEnabled = effectiveScale < maximumScale - 0.001;

        FilmstripSortText.Text = SortKeyName(preferences.FilmstripSortKey);
        // 오름차순은 위 화살표, 내림차순은 아래 화살표입니다.
        FilmstripSortDirectionIcon.Glyph = preferences.FilmstripSortAscending ? "" : "";
        FilmstripScopeText.Text = AppResources.Get(
            FilmstripScopes.ResourceKey(preferences.FilmstripScope),
            "Text");
    }

    private static string SortKeyName(LibrarySortKey key) => AppResources.Get(
        key switch
        {
            LibrarySortKey.Time => "sortTime",
            LibrarySortKey.Name => "sortName",
            LibrarySortKey.Flag => "sortFlag",
            LibrarySortKey.Rating => "sortRating",
            LibrarySortKey.FileSize => "sortFileSize",
            _ => "sortInputOrder",
        },
        "Text");

    private void BuildSortMenu()
    {
        FilmstripSortFlyout.Items.Clear();
        foreach (LibrarySortKey key in Enum.GetValues<LibrarySortKey>())
        {
            LibrarySortKey chosen = key;
            MenuFlyoutItem item = new() { Text = SortKeyName(key) };
            item.Click += (_, _) => Mutate(current => current with { FilmstripSortKey = chosen });
            FilmstripSortFlyout.Items.Add(item);
        }
        FilmstripSortFlyout.Items.Add(new MenuFlyoutSeparator());
        MenuFlyoutItem ascending = new() { Text = AppResources.Get("sortAscending", "Text") };
        ascending.Click += (_, _) => Mutate(current => current with { FilmstripSortAscending = true });
        FilmstripSortFlyout.Items.Add(ascending);
        MenuFlyoutItem descending = new() { Text = AppResources.Get("sortDescending", "Text") };
        descending.Click += (_, _) => Mutate(current => current with { FilmstripSortAscending = false });
        FilmstripSortFlyout.Items.Add(descending);
    }

    private void BuildScopeMenu()
    {
        FilmstripScopeFlyout.Items.Clear();
        foreach (FilmstripScope scope in FilmstripScopes.All)
        {
            FilmstripScope chosen = scope;
            MenuFlyoutItem item = new()
            {
                Text = AppResources.Get(FilmstripScopes.ResourceKey(scope), "Text"),
            };
            item.Click += (_, _) => Mutate(current => current with { FilmstripScope = chosen });
            FilmstripScopeFlyout.Items.Add(item);
        }
    }

    private void OnThumbnailSmallerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Mutate(current => current with
        {
            FilmstripItemScale = Math.Max(MinimumItemScale, EffectiveScale(current) - ScaleStep),
        });
    }

    private void OnThumbnailLargerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Mutate(current => current with
        {
            FilmstripItemScale = Math.Min(
                FilmstripMetrics.MaximumEffectiveItemScale(
                    current.FilmstripItemScale,
                    current.FilmstripHeight),
                EffectiveScale(current) + ScaleStep),
        });
    }

    /// <summary>macOS 도 퍼센트 글자를 누르면 100% 로 돌아갑니다.</summary>
    private void OnThumbnailSizeResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Mutate(current => current with { FilmstripItemScale = 1 });
    }

    /// <summary>스트립 높이가 허락하는 만큼으로 줄인 배율입니다.</summary>
    private static double EffectiveScale(ShellPreferences preferences) =>
        FilmstripMetrics.EffectiveItemScale(
            preferences.FilmstripItemScale,
            preferences.FilmstripHeight);

    private void Mutate(Func<ShellPreferences, ShellPreferences> update)
    {
        if (workspaceState is null)
        {
            return;
        }
        workspaceState.UpdateFilmstripPresentation(update);
        Render();
        FilmstripPresentationChanged?.Invoke(this, EventArgs.Empty);
    }
}
