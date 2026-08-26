using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 창 맨 아래 한 줄입니다. 왼쪽은 엔진 상태, 오른쪽은 필름스트립의 크기·차례·범위입니다 —
/// macOS <c>statusBar</c> 와 같은 자리, 같은 차례입니다.
/// </summary>
public sealed partial class StatusBarView : UserControl
{
    /// <summary>macOS <c>FilmstripSizing</c> 과 같은 값입니다.</summary>
    private const double MinimumItemScale = 0.56;

    private const double MaximumItemScale = 1.34;

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
        Localize();
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
        StateIndicator.Fill = new SolidColorBrush(
            status.IsAvailable ? Microsoft.UI.Colors.LimeGreen : Microsoft.UI.Colors.OrangeRed);
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
        int percent = (int)Math.Round(preferences.FilmstripItemScale * 100.0);
        ThumbnailSizeButton.Content = string.Create(
            System.Globalization.CultureInfo.CurrentCulture,
            $"{percent}%");
        ThumbnailSmallerButton.IsEnabled = preferences.FilmstripItemScale > MinimumItemScale + 0.001;
        ThumbnailLargerButton.IsEnabled = preferences.FilmstripItemScale < MaximumItemScale - 0.001;

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
            FilmstripItemScale = Math.Max(MinimumItemScale, current.FilmstripItemScale - ScaleStep),
        });
    }

    private void OnThumbnailLargerClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Mutate(current => current with
        {
            FilmstripItemScale = Math.Min(MaximumItemScale, current.FilmstripItemScale + ScaleStep),
        });
    }

    /// <summary>macOS 도 퍼센트 글자를 누르면 100% 로 돌아갑니다.</summary>
    private void OnThumbnailSizeResetClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Mutate(current => current with { FilmstripItemScale = 1 });
    }

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
