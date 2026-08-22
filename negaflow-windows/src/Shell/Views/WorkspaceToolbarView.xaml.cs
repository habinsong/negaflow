using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Negaflow.Catalog;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Shortcuts;

namespace Negaflow.Shell.Views;

public sealed partial class WorkspaceToolbarView : UserControl
{
    private WorkspacePresentationState? workspaceState;
    private LibraryHostService? libraryHost;

    public WorkspaceToolbarView()
    {
        InitializeComponent();
        PreviewScanButton.Click += OnPreviewScanClick;
        ScanFrameButton.Click += OnScanFrameClick;
        LocalizeControls();
    }

    public event EventHandler? SettingsRequested;

    /// <summary>작업 옵션 · 진단입니다. macOS 유틸리티 메뉴의 같은 자리입니다.</summary>
    public event EventHandler? DiagnosticsRequested;

    public event EventHandler? QuickExportRequested;

    /// <summary>
    /// 위 막대의 "내보내기" 입니다. macOS 처럼 <b>현상뷰 출력 탭의 내보내기 단추와 같은
    /// 동작</b>이며, 다른 화면에 있어도 그 동작을 부릅니다.
    /// </summary>
    public event EventHandler? ExportRequested;

    public event EventHandler<WorkflowShortcutAction>? ScannerCommandRequested;

    public event EventHandler? TitleBarInteractiveRegionsChanged;

    public UIElement TitleBarElement => TitleBarRoot;

    public IReadOnlyList<FrameworkElement> TitleBarInteractiveElements =>
        [PrimaryControls, ActiveFrameContainer, RightToolbarCluster];

    public void UpdateCaptionInsets(double left, double right)
    {
        LeftCaptionInsetColumn.Width = new GridLength(Math.Max(0, left));
        RightCaptionInsetColumn.Width = new GridLength(Math.Max(0, right));
    }

    public void SetQuickExportEnabled(bool isEnabled) => QuickExportButton.IsEnabled = isEnabled;

    public void SetExportEnabled(bool isEnabled) => ExportButton.IsEnabled = isEnabled;

    /// <summary>내보내는 동안 위 막대에 몇 장 중 몇 장인지 보입니다. 끝나면 사라집니다.</summary>
    public void SetExportProgress(Negaflow.Shell.Develop.ExportProgress progress) =>
        ExportProgress.Progress = progress;

    public void Initialize(WorkspacePresentationState state, LibraryHostService? host = null)
    {
        ArgumentNullException.ThrowIfNull(state);
        workspaceState = state;
        libraryHost = host;
        state.Changed += OnStateChanged;
        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged += OnLibrarySelectionChanged;
        }
        UpdateState(state.Current);
        UpdateActiveFrame();
        Unloaded += OnUnloaded;
    }

    private void OnLibrarySelectionChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        UpdateActiveFrame();
    }

    private void UpdateActiveFrame()
    {
        LibraryFrameSnapshot? frame = libraryHost?.ActiveFrameId is { } activeFrameId
            ? libraryHost.Frames.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, activeFrameId, StringComparison.Ordinal))
            : null;
        string text = frame is null
            ? AppResources.Get("noSelection", "Text")
            : LibraryFrameNaming.DisplayName(frame);
        ActiveFrameText.Text = text;
        AutomationProperties.SetName(ActiveFrameText, text);
        ToolTipService.SetToolTip(ActiveFrameText, text);
        TitleBarInteractiveRegionsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void OnLibraryClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Library);
    }

    private void OnQuickExportClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        QuickExportRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnExportClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ExportRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPreviewScanClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerCommandRequested?.Invoke(this, WorkflowShortcutAction.PreviewScan);
    }

    private void OnScanFrameClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ScannerCommandRequested?.Invoke(this, WorkflowShortcutAction.ScanFrame);
    }

    private void OnDevelopClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Develop);
    }

    private void OnPrintClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SelectWorkspace(WorkspaceModule.Print);
    }

    private void OnSidebarClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleSidebar();
    }

    private void OnFilmstripClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleFilmstrip();
    }

    private void OnInspectorClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.ToggleInspector();
    }

    private void OnSystemAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.System);
    }

    private void OnDarkAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.Dark);
    }

    private void OnLightAppearanceClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetAppearance(AppearanceMode.Light);
    }

    private void OnDiagnosticsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        DiagnosticsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnSettingsClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        SettingsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        SetWorkspaceSelection(LibraryButton, preferences.SelectedWorkspace == WorkspaceModule.Library);
        SetWorkspaceSelection(DevelopButton, preferences.SelectedWorkspace == WorkspaceModule.Develop);
        SetWorkspaceSelection(PrintButton, preferences.SelectedWorkspace == WorkspaceModule.Print);
        SetPanelState(SidebarButton, preferences.IsSidebarVisible);
        SetPanelState(FilmstripButton, preferences.IsFilmstripVisible);
        SetPanelState(InspectorButton, preferences.IsInspectorVisible);
        ApplyAppearanceIcon(preferences.Appearance);
    }

    private static void SetWorkspaceSelection(Button button, bool selected)
    {
        button.FontWeight = selected ? FontWeights.Bold : FontWeights.SemiBold;
        button.Opacity = selected ? 1 : 0.68;
        AutomationProperties.SetHelpText(
            button,
            AppResources.Get(selected ? "selected" : "notSelected", "Value"));
    }

    private static void SetPanelState(Button button, bool isOn)
    {
        button.Opacity = isOn ? 1 : 0.52;
        AutomationProperties.SetHelpText(
            button,
            AppResources.Get(isOn ? "on" : "off", "Value"));
    }

    /// <summary>언어가 바뀌면 문구를 다시 겁니다.</summary>
    public void Localize() => LocalizeControls();

    public void SyncScannerState(ScannerMenuState state, bool hasScanner, bool supportsPreview)
    {
        bool showPreview = hasScanner && supportsPreview;
        PreviewScanButton.Visibility = showPreview ? Visibility.Visible : Visibility.Collapsed;
        PreviewScanDivider.Visibility = showPreview ? Visibility.Visible : Visibility.Collapsed;
        ScanFrameButton.Visibility = hasScanner ? Visibility.Visible : Visibility.Collapsed;
        ScannerExportDivider.Visibility = hasScanner ? Visibility.Visible : Visibility.Collapsed;
        PreviewScanButton.IsEnabled = state.CanPreview;
        ScanFrameButton.IsEnabled = state.CanScan;
        TitleBarInteractiveRegionsChanged?.Invoke(this, EventArgs.Empty);
    }

    private void LocalizeControls()
    {
        CommandQuickExportLocalized.Text = AppResources.Get("commandQuickExport", "Text");
        CommandExportLocalized.Text = AppResources.Get("commandExport", "Text");
        CommandPreviewScanLocalized.Text = AppResources.Get("shortcutPreviewScan", "Text");
        CommandScanFrameLocalized.Text = AppResources.Get("shortcutScanFrame", "Text");
        // 활성 사진 이름은 고른 사진에 따라 바뀝니다 — 이름을 지우지 않도록 그 길로 다시 겁니다.
        UpdateActiveFrame();
        LibraryButton.Content = AppResources.Get("menuLibrary", "Content");
        DevelopButton.Content = AppResources.Get("menuDevelop", "Content");
        PrintButton.Content = AppResources.Get("menuPrint", "Content");
        SetNameAndTooltip(
            QuickExportButton,
            AppResources.Get("commandQuickExport", "Text"));
        SetNameAndTooltip(ExportButton, AppResources.Get("commandExport", "Text"));
        SetNameAndTooltip(
            PreviewScanButton,
            AppResources.Get("shortcutPreviewScan", "Text"));
        SetNameAndTooltip(
            ScanFrameButton,
            AppResources.Get("shortcutScanFrame", "Text"));
        SetNameAndTooltip(
            SidebarButton,
            AppResources.Get("commandShowHideSidebar", "Value"));
        SetNameAndTooltip(
            FilmstripButton,
            AppResources.Get("commandShowHideFilmstrip", "Value"));
        SetNameAndTooltip(
            InspectorButton,
            AppResources.Get("commandShowHideInspector", "Value"));
        SetNameAndTooltip(
            AppearanceButton,
            AppResources.Get("settingsAppearancePicker", "Value"));
        SetNameAndTooltip(
            UtilityButton,
            AppResources.Get("commandWorkspaceOptions", "Value"));
        SystemAppearanceItem.Text = AppResources.Get("appearanceSystem", "Text");
        DarkAppearanceItem.Text = AppResources.Get("appearanceDark", "Text");
        LightAppearanceItem.Text = AppResources.Get("appearanceLight", "Text");
        SettingsItem.Text = AppResources.Get("commandSettings", "Text");
        DiagnosticsItem.Text = AppResources.Get("commandDiagnostics", "Text");
        // 고름·켬/끔 표시도 리소스 문구입니다. 상태가 바뀔 때만 걸어 두면 언어를 바꿔도
        // 옛 언어로 남습니다.
        if (workspaceState is { } state)
        {
            UpdateState(state.Current);
        }
    }

    /// <summary>
    /// 화면 모드 아이콘입니다. macOS <c>AppAppearanceMode.systemImage</c> 와 같은 뜻으로
    /// 고른 값을 그림으로 보여 줍니다 - 셋 다 해 하나면 무엇이 걸려 있는지 알 수 없습니다.
    /// </summary>
    private void ApplyAppearanceIcon(AppearanceMode appearance) =>
        AppearanceIcon.Glyph = appearance switch
        {
            // macOS `moon.fill` 자리입니다. Segoe QuietHours 가 같은 초승달입니다.
            AppearanceMode.Dark => "\uE708",
            // macOS `sun.max.fill` 자리입니다.
            AppearanceMode.Light => "\uE706",
            // macOS `circle.lefthalf.filled` 자리입니다. Segoe Contrast 가 반쪽 채운 원입니다.
            _ => "\uE7A1",
        };

    private static void SetNameAndTooltip(Button button, string text)
    {
        AutomationProperties.SetName(button, text);
        ToolTipService.SetToolTip(button, text);
    }

    private void OnUnloaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            workspaceState.Changed -= OnStateChanged;
        }
        if (libraryHost is not null)
        {
            libraryHost.SelectionChanged -= OnLibrarySelectionChanged;
        }
    }
}
