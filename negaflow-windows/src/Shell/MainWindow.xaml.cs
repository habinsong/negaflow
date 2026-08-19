using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace Negaflow.Shell;

public sealed partial class MainWindow : Window
{
    private readonly PresentationSettingsStore settingsStore;
    private readonly WorkspacePresentationState workspaceState;
    private SettingsWindow? settingsWindow;
    private AboutNegaflowWindow? aboutWindow;
    private QuickStartHelpWindow? quickStartHelpWindow;

    public MainWindow(
        PresentationSettingsStore settingsStore,
        WorkspacePresentationState workspaceState,
        NativeEngineStatusService nativeEngineStatusService,
        LibraryHostService? libraryHost = null,
        Negaflow.Shell.Library.ThumbnailService? thumbnails = null)
    {
        this.settingsStore = settingsStore;
        this.workspaceState = workspaceState;
        InitializeComponent();
        WindowIcon.Apply(AppWindow);

        ShellView.Initialize(
            workspaceState,
            nativeEngineStatusService,
            libraryHost,
            AppWindow.Id,
            thumbnails);
        ShellView.SettingsRequested += OnSettingsRequested;
        ShellView.QuickStartHelpRequested += OnQuickStartHelpRequested;
        ShellView.AboutRequested += OnAboutRequested;
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(ShellView.TitleBarElement);
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
        Closed += OnClosed;
    }

    private void OnShellLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCaptionInsets();
    }

    private void OnShellSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateCaptionInsets();
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

    private void OnSettingsRequested(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (settingsWindow is null)
        {
            settingsWindow = new SettingsWindow(settingsStore, workspaceState);
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
        settingsStore.Changed -= OnSettingsChanged;
        settingsWindow?.Close();
        settingsWindow = null;
        aboutWindow?.Close();
        aboutWindow = null;
    }
}
