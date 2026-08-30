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
    private bool menuLayoutUpdateQueued;

    public WorkspaceToolbarView()
    {
        InitializeComponent();
        PreviewScanButton.Click += OnPreviewScanClick;
        ScanFrameButton.Click += OnScanFrameClick;
        TitleBarRoot.SizeChanged += OnMenuLayoutMeasureChanged;
        WorkspaceTabs.SizeChanged += OnMenuLayoutMeasureChanged;
        MenuBar.Loaded += OnMenuLayoutMeasureChanged;
        MenuBar.SizeChanged += OnMenuLayoutMeasureChanged;
        Loaded += OnLoaded;
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

    /// <summary>메뉴줄입니다. 제목 표시줄 첫 칸에 있고, 신호는 셸이 받습니다.</summary>
    internal AppMenuBarView Menu => MenuBar;

    /// <summary>
    /// 제목 표시줄 안에서 **끌기가 아니라 누르기**로 동작해야 하는 자리입니다.
    /// </summary>
    /// <remarks>
    /// 스캔·내보내기 단추는 이제 이 줄에 없습니다 — 셸이 가져가 둘째 줄에 답니다.
    /// 여기 남겨 두면 제목 표시줄 밖의 좌표를 상호작용 영역으로 등록하게 됩니다.
    /// </remarks>
    public IReadOnlyList<FrameworkElement> TitleBarInteractiveElements =>
        [MenuBar, WorkspaceTabs];


    public void UpdateCaptionInsets(double left, double right)
    {
        LeftCaptionInsetColumn.Width = new GridLength(Math.Max(0, left));
        RightCaptionInsetColumn.Width = new GridLength(Math.Max(0, right));
        QueueMenuLayoutUpdate();
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        QueueMenuLayoutUpdate();
    }

    private void OnMenuLayoutMeasureChanged(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        QueueMenuLayoutUpdate();
    }

    private void OnMenuLayoutMeasureChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        QueueMenuLayoutUpdate();
    }

    private void QueueMenuLayoutUpdate()
    {
        if (menuLayoutUpdateQueued)
        {
            return;
        }

        menuLayoutUpdateQueued = true;
        if (!DispatcherQueue.TryEnqueue(() =>
        {
            menuLayoutUpdateQueued = false;
            const double menuToWorkspaceTabsGap = 8;
            double availableWidth = TitleBarRoot.ActualWidth -
                TitleBarRoot.Padding.Left -
                TitleBarRoot.Padding.Right -
                LeftCaptionInsetColumn.ActualWidth -
                RightCaptionInsetColumn.ActualWidth -
                WorkspaceTabs.ActualWidth -
                menuToWorkspaceTabsGap;
            if (availableWidth < 0)
            {
                availableWidth = 0;
            }

            if (availableWidth > 0)
            {
                MenuBar.MaxWidth = availableWidth;
            }
            else
            {
                MenuBar.ClearValue(MaxWidthProperty);
            }

            if (MenuBar.FitAvailableWidth(availableWidth))
            {
                TitleBarInteractiveRegionsChanged?.Invoke(this, EventArgs.Empty);
            }
        }))
        {
            menuLayoutUpdateQueued = false;
        }
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
            // 별·깃발·제외는 라이브러리 카드·메뉴·단축키에서도 바뀝니다. 이 줄이 없으면
            // 도구줄 가운데가 옛 값에 멈춰 있습니다.
            libraryHost.FrameEdited += OnLibraryFrameEdited;
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

    private void OnLibraryFrameEdited(object? sender, EventArgs args)
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
        UpdateActiveFrameMarks(frame);
        TitleBarInteractiveRegionsChanged?.Invoke(this, EventArgs.Empty);
    }
    /// <summary>
    /// 가운데 줄의 사진 이름·평점·깃발·제외를 지금 고른 사진에 맞춥니다.
    /// macOS <c>RollToolbarStrip</c> 과 같은 색 규칙입니다 — 채운 별은 파랑, 깃발은 초록,
    /// 제외는 빨강, 걸리지 않은 것은 흐린 보조색.
    /// </summary>
    private void UpdateActiveFrameMarks(LibraryFrameSnapshot? frame)
    {
        bool hasFrame = frame is not null;
        ActiveFrameRating.IsEnabled = hasFrame;
        ActiveFramePickButton.IsEnabled = hasFrame;
        ActiveFrameRejectButton.IsEnabled = hasFrame;
        ActiveFrameRating.Rating = frame?.Rating ?? 0;

        FramePickState state = frame?.PickState ?? FramePickState.Unflagged;
        ActiveFramePickIcon.Glyph = state == FramePickState.Picked ? "\uEB4B" : "\uE129";
        ActiveFramePickIcon.Foreground = state == FramePickState.Picked
            ? PickedBrush
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        ActiveFrameRejectIcon.Foreground = state == FramePickState.Rejected
            ? RejectedBrush
            : (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorTertiaryBrush"];

        AutomationProperties.SetName(ActiveFramePickButton, AppResources.Get("picked", "Text"));
        AutomationProperties.SetName(ActiveFrameRejectButton, AppResources.Get("rejected", "Text"));
    }

    private static readonly Microsoft.UI.Xaml.Media.SolidColorBrush PickedBrush =
        new(Windows.UI.Color.FromArgb(0xFF, 0x30, 0xA4, 0x6C));

    private static readonly Microsoft.UI.Xaml.Media.SolidColorBrush RejectedBrush =
        new(Windows.UI.Color.FromArgb(0xFF, 0xE5, 0x48, 0x4D));

    private LibraryFrameSnapshot? ActiveFrame() =>
        libraryHost?.ActiveFrameId is { } activeFrameId
            ? libraryHost.Frames.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, activeFrameId, StringComparison.Ordinal))
            : null;

    private void OnActiveFrameRatingCommitted(object? sender, int rating)
    {
        _ = sender;
        if (libraryHost is null || ActiveFrame() is not { } frame)
        {
            return;
        }
        Commit(frame, new LibraryFrameEdit(frame.Tone, frame.ManualBase, Rating: rating));
    }

    private void OnActiveFramePickClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || ActiveFrame() is not { } frame)
        {
            return;
        }
        // macOS 와 같이 이미 그 상태면 다시 눌러 해제합니다.
        FramePickState next = frame.PickState == FramePickState.Picked
            ? FramePickState.Unflagged
            : FramePickState.Picked;
        Commit(frame, new LibraryFrameEdit(frame.Tone, frame.ManualBase, PickState: next));
    }

    private void OnActiveFrameRejectClick(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (libraryHost is null || ActiveFrame() is not { } frame)
        {
            return;
        }
        FramePickState next = frame.PickState == FramePickState.Rejected
            ? FramePickState.Unflagged
            : FramePickState.Rejected;
        Commit(frame, new LibraryFrameEdit(frame.Tone, frame.ManualBase, PickState: next));
    }

    private void Commit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        if (libraryHost is null)
        {
            return;
        }
        if (libraryHost.Edit(frame.Id, edit) != LibraryFrameError.None)
        {
            // 값을 못 넣었으면 화면도 되돌립니다 — 남길 수 없는 값을 남기지 않습니다.
            UpdateActiveFrameMarks(frame);
            return;
        }
        // 저장은 `Edit` 이 예약합니다(1.5 초 debounce, macOS 와 같습니다). 누를 때마다 카탈로그를
        // 통째로 쓰면 연달아 누르는 동안 그만큼 멈춥니다.
        UpdateActiveFrame();
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

        QueueMenuLayoutUpdate();
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
            libraryHost.FrameEdited -= OnLibraryFrameEdited;
        }
    }
}
