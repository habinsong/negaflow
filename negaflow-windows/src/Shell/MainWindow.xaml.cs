using System.Collections.Generic;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using Rect = Windows.Foundation.Rect;

namespace Negaflow.Shell;

public sealed partial class MainWindow : Window
{
    private readonly PresentationSettingsStore settingsStore;
    private readonly WorkspacePresentationState workspaceState;
    /// <summary>창을 띄운 뒤에 열립니다 - 그 전에는 <see langword="null"/> 입니다.</summary>
    /// <summary>
    /// 셸입니다. 창을 띄운 <b>뒤</b>에 만들어 <c>ShellHost</c> 에 넣습니다 - XAML 에 적어 두면
    /// 그 값이 창 등장 앞에 놓여 검은 화면이 됩니다.
    /// </summary>
    private Views.WorkspaceShellView ShellView { get; set; } = null!;

    private LibraryHostService? libraryHost;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    private SettingsWindow? settingsWindow;
    private DiagnosticsWindow? diagnosticsWindow;
    private AboutNegaflowWindow? aboutWindow;
    private QuickStartHelpWindow? quickStartHelpWindow;

    private void OnLoadingIconOpened(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        Diagnostics.StartupTrace.Mark("로고 이미지 열림");
        logoReady = true;
        StartShellWhenLogoIsUp();
    }

    private void OnLoadingIconFailed(object sender, ExceptionRoutedEventArgs args)
    {
        _ = sender;
        Diagnostics.StartupTrace.Mark("로고 이미지 실패: " + args.ErrorMessage);
        // 그림이 없어도 이름은 보입니다. 셸 만들기를 붙잡아 둘 이유가 없습니다.
        logoReady = true;
        StartShellWhenLogoIsUp();
    }

    private bool logoReady;

    private bool shellStarted;

    /// <summary>
    /// 로고가 <b>화면에 나온 뒤</b>에 셸을 만듭니다.
    /// </summary>
    /// <remarks>
    /// 셸을 만드는 동안 UI 스레드는 통째로 막힙니다(실측 1 초). 그 전에 시작하면 그림 디코딩이
    /// 끝나도 그것을 화면에 올릴 차례가 오지 않아, 로고는 셸이 다 만들어진 뒤에야 나타납니다 -
    /// 즉 보여 줄 시간에는 없습니다. 실측으로 그림이 4.30 초에야 열렸고 오버레이는 2.99 초에
    /// 이미 걷혔습니다.
    ///
    /// 그림이 준비되고 한 프레임이 더 그려진 뒤에 시작합니다. 그림이 없어도(실패해도) 이름은
    /// 보이므로 그때도 곧바로 시작합니다.
    /// </remarks>
    private void StartShellWhenLogoIsUp()
    {
        if (shellStarted || !logoReady || !firstFrameSeen)
        {
            return;
        }
        shellStarted = true;
        Diagnostics.StartupTrace.Mark("로고 표시됨 - 셸 만들기 시작");
        _ = DispatcherQueue.TryEnqueue(
            Microsoft.UI.Dispatching.DispatcherQueuePriority.Low,
            CompleteInitialization);
    }

    private bool firstFrameSeen;

    private void OnFirstRendered(object? sender, object args)
    {
        _ = sender;
        _ = args;
        if (firstFrameSeen)
        {
            return;
        }
        firstFrameSeen = true;
        Microsoft.UI.Xaml.Media.CompositionTarget.Rendering -= OnFirstRendered;
        Diagnostics.StartupTrace.Mark("첫 프레임 그려짐");
        StartShellWhenLogoIsUp();

    }

    /// <summary>셸이 만들어진 뒤에 거는 것들입니다. 만들기 전에는 걸 대상이 없습니다.</summary>
    private void WireShell()
    {
        ShellView.TitleBarInteractiveRegionsChanged += OnTitleBarInteractiveRegionsChanged;
        ShellView.SettingsRequested += OnSettingsRequested;
        ShellView.DiagnosticsRequested += OnDiagnosticsRequested;
        ShellView.QuickStartHelpRequested += OnQuickStartHelpRequested;
        ShellView.AboutRequested += OnAboutRequested;
        ShellView.Loaded += OnShellLoaded;
        ShellView.SizeChanged += OnShellSizeChanged;
        ShellView.Loaded += (_, _) =>
        {
            Diagnostics.StartupTrace.Mark("shell Loaded (첫 레이아웃)");
            // 셸이 자리를 잡았으니 이제 로고를 걷습니다.
            LoadingOverlay.Visibility = Visibility.Collapsed;
        };
        SetTitleBar(ShellView.TitleBarElement);
    }

    /// <summary>창을 띄운 뒤에 할 초기화입니다. 한 번만 돕니다.</summary>
    private Action? pendingInitialization;

    /// <summary>
    /// 창이 뜬 뒤 셸을 채웁니다. <see cref="App"/> 이 <c>Activate()</c> 바로 뒤에 부릅니다.
    /// </summary>
    public void CompleteInitialization()
    {
        if (Interlocked.Exchange(ref pendingInitialization, null) is not { } work)
        {
            return;
        }
        using (Diagnostics.StartupTrace.Measure("ShellView.Initialize"))
        {
            work();
        }
    }

    public MainWindow(
        PresentationSettingsStore settingsStore,
        WorkspacePresentationState workspaceState,
        NativeEngineStatusService nativeEngineStatusService,
        Func<LibraryHostService?> openLibrary,
        Func<Negaflow.Shell.Library.ThumbnailService?> thumbnailsFactory)
    {
        ArgumentNullException.ThrowIfNull(openLibrary);
        ArgumentNullException.ThrowIfNull(thumbnailsFactory);
        this.settingsStore = settingsStore;
        this.workspaceState = workspaceState;
        using (Diagnostics.StartupTrace.Measure("MainWindow.InitializeComponent"))
        {
            InitializeComponent();
        }
        WindowIcon.Apply(AppWindow);

        // 셸 자체를 `x:Load="False"` 로 미루는 것도 해 봤으나 되돌렸습니다 - `FindName` 이
        // 창의 네임스코프에서 셸을 찾지 못해 그 뒤가 통째로 `NullReferenceException` 이었고,
        // 앱이 죽는 것을 실기에서 확인했습니다. 창을 더 빨리 띄우려면 그 자리부터 풀어야
        // 합니다.
        pendingInitialization = () =>
        {
            using (Diagnostics.StartupTrace.Measure("ShellView 만들기"))
            {
                ShellView = new Views.WorkspaceShellView();
                ShellHost.Children.Add(ShellView);
            }
            WireShell();
            using (Diagnostics.StartupTrace.Measure("OpenLibrary"))
            {
                libraryHost = openLibrary();
            }
            thumbnails = thumbnailsFactory();
            ShellView.Initialize(
                workspaceState,
                nativeEngineStatusService,
                libraryHost,
                AppWindow.Id,
                thumbnails);
        };

        // **뜨는 동안 검은 창이 보이지 않게 합니다.**
        //
        // 창은 콘텐츠가 그려지기 전까지 아무 것도 없는 판이고, 그 판은 검게 보입니다.
        // 시스템 배경(Mica)을 걸면 그 자리에 바탕 화면이 비쳐 보이므로, 로딩 화면의
        // 아이콘과 이름만 떠 있는 모양이 됩니다.
        SystemBackdrop = new Microsoft.UI.Xaml.Media.MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        // 창 뿌리에서 키를 한 번 봅니다. 여기까지도 안 오면 키가 앱에 들어오지 않은
        // 것이고, 여기는 오는데 셸이 못 받으면 라우팅이 끊긴 것입니다.
        WindowRoot.AddHandler(
            UIElement.KeyDownEvent,
            new Microsoft.UI.Xaml.Input.KeyEventHandler(OnWindowRootKeyDown),
            handledEventsToo: true);
        WindowRoot.AddHandler(
            UIElement.PreviewKeyDownEvent,
            new Microsoft.UI.Xaml.Input.KeyEventHandler(OnWindowRootPreviewKeyDown),
            handledEventsToo: true);

        // **화면에 실제로 픽셀이 나온 때**입니다. 창이 뜬 것과 다릅니다 - 창은 비어 있어도
        // 뜹니다. `Rendering` 은 합성기가 프레임을 그릴 때마다 오므로 첫 번을 받고 뗍니다.
        Microsoft.UI.Xaml.Media.CompositionTarget.Rendering += OnFirstRendered;


        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            var minimumSize = WindowDpiSizing.LogicalToPhysical(
                this,
                ShellLayoutMetrics.MinimumWindowWidth,
                ShellLayoutMetrics.MinimumWindowHeight);
            presenter.PreferredMinimumWidth = minimumSize.Width;
            presenter.PreferredMinimumHeight = minimumSize.Height;
            presenter.Maximize();
        }

        AppWindow.TitleBar.ButtonBackgroundColor = Microsoft.UI.Colors.Transparent;
        AppWindow.TitleBar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
        ApplyAppearance(settingsStore.Current.Appearance);
        settingsStore.Changed += OnSettingsChanged;
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnClosed;
    }

    /// <summary>
    /// 버블 단계입니다. 터널에서 이미 처리했으면 아무 것도 하지 않습니다 - 포커스가 어디에
    /// 있든 한 번은 들어오게 하려고 두 단계 모두 겁니다.
    /// </summary>
    private void OnWindowRootKeyDown(
        object sender,
        Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        _ = sender;
        if (!args.Handled)
        {
            ShellView.HandleWindowKey(args);
        }
    }

    /// <summary>
    /// 터널 단계입니다. 키는 이 자리까지 옵니다(측정 확인). 셸의 UserControl 까지는
    /// 포커스가 그 안에 있을 때만 내려오므로, 여기서 넘겨 줍니다.
    /// </summary>
    private void OnWindowRootPreviewKeyDown(
        object sender,
        Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        _ = sender;
        ShellView.HandleWindowKey(args);
    }

    private void OnShellLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCaptionInsets();
        UpdateTitleBarInteractiveRegions();
    }

    private void OnShellSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCaptionInsets();
        UpdateTitleBarInteractiveRegions();
    }

    private void UpdateCaptionInsets()
    {
        double scale = ShellView.XamlRoot?.RasterizationScale ?? 1;
        if (scale <= 0)
        {
            scale = 1;
        }

        ShellView.UpdateCaptionInsets(
            AppWindow.TitleBar.LeftInset / scale,
            AppWindow.TitleBar.RightInset / scale);
    }

    private void OnTitleBarInteractiveRegionsChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        ShellView.DispatcherQueue.TryEnqueue(UpdateTitleBarInteractiveRegions);
    }

    private void UpdateTitleBarInteractiveRegions()
    {
        if (!ExtendsContentIntoTitleBar || ShellView.XamlRoot is not { } root)
        {
            return;
        }

        double scale = root.RasterizationScale;
        if (scale <= 0)
        {
            scale = 1;
        }

        List<RectInt32> rects = [];
        foreach (FrameworkElement element in ShellView.TitleBarInteractiveElements)
        {
            if (element.Visibility != Visibility.Visible ||
                element.ActualWidth <= 0 ||
                element.ActualHeight <= 0)
            {
                continue;
            }

            GeneralTransform transform = element.TransformToVisual(null);
            Rect bounds = transform.TransformBounds(
                new Rect(0, 0, element.ActualWidth, element.ActualHeight));
            rects.Add(new RectInt32(
                (int)Math.Round(bounds.X * scale),
                (int)Math.Round(bounds.Y * scale),
                (int)Math.Round(bounds.Width * scale),
                (int)Math.Round(bounds.Height * scale)));
        }

        InputNonClientPointerSource pointerSource =
            InputNonClientPointerSource.GetForWindowId(AppWindow.Id);
        pointerSource.SetRegionRects(
            NonClientRegionKind.Passthrough,
            rects.ToArray());
    }

    /// <summary>
    /// 작업 옵션 · 진단입니다. macOS 는 <c>runDiagnostics()</c> 를 부르고 팝오버를 엽니다 -
    /// 여는 순간 보고서를 만들고, 새로고침 단추로 다시 만듭니다.
    /// </summary>
    private void OnDiagnosticsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (diagnosticsWindow is null)
        {
            diagnosticsWindow = new DiagnosticsWindow(settingsStore, CollectDiagnosticsAsync);
            diagnosticsWindow.Closed += OnDiagnosticsWindowClosed;
        }
        diagnosticsWindow.Activate();
    }

    /// <summary>
    /// 진단에 담을 값을 모읍니다. 디스크를 읽는 부분은 워커로 넘깁니다 - macOS 도 같은
    /// 이유로 <c>runDiagnostics</c> 가 비동기입니다.
    /// </summary>
    private Task<Negaflow.Shell.Diagnostics.DiagnosticsReport> CollectDiagnosticsAsync()
    {
        Negaflow.Shell.Diagnostics.DiagnosticsInputs inputs = ShellView.CollectDiagnostics(
            libraryHost);
        DateTimeOffset now = DateTimeOffset.Now;
        return Task.Run(() =>
            Negaflow.Shell.Diagnostics.DiagnosticsCollector.Collect(inputs, now));
    }

    private void OnDiagnosticsWindowClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (sender is DiagnosticsWindow closed)
        {
            closed.Closed -= OnDiagnosticsWindowClosed;
        }
        diagnosticsWindow = null;
    }

    private void OnSettingsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(
                settingsStore, workspaceState, libraryHost, thumbnails);
            settingsWindow.Closed += OnSettingsWindowClosed;
        }

        settingsWindow.Activate();
    }

    private void OnQuickStartHelpRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (quickStartHelpWindow is null)
        {
            quickStartHelpWindow = new QuickStartHelpWindow(settingsStore);
            quickStartHelpWindow.Closed += OnQuickStartHelpWindowClosed;
        }

        quickStartHelpWindow.Activate();
    }

    private void OnQuickStartHelpWindowClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        if (quickStartHelpWindow is not null)
        {
            quickStartHelpWindow.Closed -= OnQuickStartHelpWindowClosed;
            quickStartHelpWindow = null;
        }
    }

    private void OnAboutRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (aboutWindow is null)
        {
            aboutWindow = new AboutNegaflowWindow(settingsStore);
            aboutWindow.Closed += OnAboutWindowClosed;
        }

        aboutWindow.Activate();
    }

    /// <summary>
    /// 두 번째 실행이 기존 프로세스로 넘어왔을 때 이 창을 다시 보여 줍니다. 최소화면이면
    /// 복원합니다 — 뒤에 숨어 있으면 사용자는 또 켜진 줄 압니다.
    /// </summary>
    internal void BringToFront()
    {
        if (AppWindow.Presenter is OverlappedPresenter { State: OverlappedPresenterState.Minimized } presenter)
        {
            presenter.Restore();
        }

        Activate();
    }

    private void OnSettingsWindowClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (sender is SettingsWindow closedWindow)
        {
            closedWindow.Closed -= OnSettingsWindowClosed;
        }

        settingsWindow = null;
    }

    private void OnAboutWindowClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (sender is AboutNegaflowWindow closedWindow)
        {
            closedWindow.Closed -= OnAboutWindowClosed;
        }

        aboutWindow = null;
    }

    private void OnSettingsChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        ApplyAppearance(preferences.Appearance);
    }

    private void ApplyAppearance(AppearanceMode appearance)
    {
        WindowRoot.RequestedTheme = appearance switch
        {
            AppearanceMode.Dark => ElementTheme.Dark,
            AppearanceMode.Light => ElementTheme.Light,
            _ => ElementTheme.Default,
        };
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        _ = sender;
        _ = args;
        if (ShellView is null)
        {
            return;
        }
        ShellView.Loaded -= OnShellLoaded;
        ShellView.SizeChanged -= OnShellSizeChanged;
        ShellView.SettingsRequested -= OnSettingsRequested;
        ShellView.QuickStartHelpRequested -= OnQuickStartHelpRequested;
        ShellView.AboutRequested -= OnAboutRequested;
        ShellView.TitleBarInteractiveRegionsChanged -= OnTitleBarInteractiveRegionsChanged;
        settingsStore.Changed -= OnSettingsChanged;
        AppWindow.Closing -= OnAppWindowClosing;
        settingsWindow?.Close();
        settingsWindow = null;
        aboutWindow?.Close();
        aboutWindow = null;
    }
}
