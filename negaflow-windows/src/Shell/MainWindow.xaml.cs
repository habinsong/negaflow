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
    private LibraryHostService? libraryHost;
    private Negaflow.Shell.Library.ThumbnailService? thumbnails;
    private SettingsWindow? settingsWindow;
    private DiagnosticsWindow? diagnosticsWindow;
    private AboutNegaflowWindow? aboutWindow;
    private QuickStartHelpWindow? quickStartHelpWindow;

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

        ShellView.TitleBarInteractiveRegionsChanged += OnTitleBarInteractiveRegionsChanged;
        // **셸 초기화는 창을 띄운 뒤로 미룹니다.** 생성자에서 끝내면 그 시간만큼 창이
        // 아예 뜨지 않아 사용자는 검은 화면을 봅니다 - 실측으로 창이 2.02 초에 떴고 그중
        // 0.39 초가 이 초기화였습니다. 창을 먼저 내놓고 같은 UI 스레드에서 이어서 채웁니다.
        pendingInitialization = () =>
        {
            // 카탈로그 열기도 여기서 합니다 - 창을 띄우기 전에 하면 그 시간 동안 화면이
            // 비어 있습니다.
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

        ShellView.SettingsRequested += OnSettingsRequested;
        ShellView.DiagnosticsRequested += OnDiagnosticsRequested;
        ShellView.QuickStartHelpRequested += OnQuickStartHelpRequested;
        ShellView.AboutRequested += OnAboutRequested;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(ShellView.TitleBarElement);
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
        ShellView.Loaded += (_, _) =>
            Diagnostics.StartupTrace.Mark("shell Loaded (첫 레이아웃)");
        // **화면에 실제로 픽셀이 나온 때**입니다. 창이 뜬 것과 다릅니다 - 창은 비어 있어도
        // 뜹니다. `Rendering` 은 합성기가 프레임을 그릴 때마다 오므로 첫 번을 받고 뗍니다.
        Microsoft.UI.Xaml.Media.CompositionTarget.Rendering += OnFirstRendered;
        ShellView.Loaded += OnShellLoaded;
        ShellView.SizeChanged += OnShellSizeChanged;

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
