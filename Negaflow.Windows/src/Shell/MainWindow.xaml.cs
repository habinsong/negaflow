using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace Negaflow.Shell;

public sealed partial class MainWindow : Window
{
    private readonly PresentationSettingsStore settingsStore;
    private readonly WorkspacePresentationState workspaceState;
    private SettingsWindow? settingsWindow;

    public MainWindow(
        PresentationSettingsStore settingsStore,
        WorkspacePresentationState workspaceState,
        NativeEngineStatusService nativeEngineStatusService,
        LibraryHostService? libraryHost = null)
    {
        this.settingsStore = settingsStore;
        this.workspaceState = workspaceState;
        InitializeComponent();

        ShellView.Initialize(
            workspaceState,
            nativeEngineStatusService,
            libraryHost,
            AppWindow.Id);
        ShellView.SettingsRequested += OnSettingsRequested;
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

    private void OnSettingsWindowClosed(object sender, WindowEventArgs args)
    {
        _ = args;
        if (sender is SettingsWindow closedWindow)
        {
            closedWindow.Closed -= OnSettingsWindowClosed;
        }

        settingsWindow = null;
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
        settingsStore.Changed -= OnSettingsChanged;
        settingsWindow?.Close();
        settingsWindow = null;
    }
}
