using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI;
using Negaflow.Interop;
using Negaflow.Shell.Print;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Layout;

namespace Negaflow.Shell.Views;

public sealed partial class PrintWorkspaceView : UserControl
{
    private readonly ThreePaneResizeController resizeController = new();
    private WorkspacePresentationState? workspaceState;

    public PrintWorkspaceView()
    {
        InitializeComponent();
        BindPrintComposition();
        LocalizeControls();
        LocalizePrintInspector();
        LocalizeCustomEditor();
        HookPrintSegments();
    }

    public void Initialize(WorkspacePresentationState state, NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        state.Changed += OnStateChanged;
        // macOS 인화 사이드바도 현상과 **같은** `ExportSection` 이므로 같은 설정을 봅니다.
        // 붙이지 않으면 이 탭에서 고친 값이 저장되지 않고 현상뷰와 따로 놀게 됩니다.
        PrintExportPanel.Attach(state);
        Filmstrip.Initialize(state);
        Filmstrip.FrameSelected += OnPrintFilmstripFrameSelected;
        StatusBar.Initialize(nativeEngineStatus);
        UpdateState(state.Current);
        SynchronizePrint();
        Unloaded += OnUnloaded;
    }

    private void OnRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not null)
        {
            SynchronizeWidths(workspaceState.Current);
        }
    }

    private void OnLeftResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginLeft();
    }

    private void OnLeftResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        LeftPanel.Width = resizeController.UpdateLeft(args.HorizontalChange, Root.ActualWidth);
        UpdateCompactRail();
    }

    private void OnLeftResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetSidebarWidth(resizeController.EndLeft());
    }

    private void OnRightResizeStarted(object sender, DragStartedEventArgs args)
    {
        _ = sender;
        _ = args;
        resizeController.BeginRight();
    }

    private void OnRightResizeDelta(object sender, DragDeltaEventArgs args)
    {
        _ = sender;
        RightPanel.Width = resizeController.UpdateRight(args.HorizontalChange, Root.ActualWidth);
    }

    private void OnRightResizeCompleted(object sender, DragCompletedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.SetInspectorWidth(resizeController.EndRight());
    }

    private void OnStateChanged(object? sender, ShellPreferences preferences)
    {
        _ = sender;
        UpdateState(preferences);
    }

    private void UpdateState(ShellPreferences preferences)
    {
        LeftPanel.Visibility = preferences.IsSidebarVisible ? Visibility.Visible : Visibility.Collapsed;
        LeftDivider.Visibility = LeftPanel.Visibility;
        LeftResizeThumb.Visibility = LeftPanel.Visibility;
        RightPanel.Visibility = preferences.IsInspectorVisible ? Visibility.Visible : Visibility.Collapsed;
        RightDivider.Visibility = RightPanel.Visibility;
        RightResizeThumb.Visibility = RightPanel.Visibility;
        Filmstrip.Visibility = preferences.IsFilmstripVisible ? Visibility.Visible : Visibility.Collapsed;
        SynchronizeWidths(preferences);
        ApplyCanvasBackground(preferences.CanvasBackground);
        // 인화 내보내기도 현상과 같은 자리를 씁니다(디스크 탭의 내보내기/빠른 내보내기 폴더).
        Negaflow.Shell.Develop.ExportSettings export = preferences.ResolvedExport;
        Negaflow.Shell.Develop.QuickExportSettings quick = preferences.ResolvedQuickExport;
        if (PrintExportPanel.Settings != export ||
            PrintExportPanel.QuickSettings != quick ||
            PrintExportPanel.Recipes != preferences.ExportRecipes)
        {
            PrintExportPanel.ApplyPreferences(
                export,
                quick,
                preferences.ExportRecipes);
        }
    }

    /// <summary>
    /// 설정 · 인터페이스의 캔버스 배경입니다. macOS 는 인화 캔버스도 같은 값을 씁니다
    /// (<c>PrintCanvasView</c> 의 <c>CanvasBackgroundMenu</c>).
    /// </summary>
    private void ApplyCanvasBackground(Negaflow.Shell.Develop.CanvasBackgroundKind background)
    {
        byte level = Negaflow.Shell.Develop.CanvasBackgroundColors.Byte(background);
        CanvasHost.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(
            Microsoft.UI.ColorHelper.FromArgb(255, level, level, level));
        printCanvasBackground = background;
        CanvasHost.ContextFlyout ??= Views.Controls.CanvasBackgroundFlyout.Create(
            () => printCanvasBackground,
            kind => workspaceState?.SetCanvasBackground(kind));
    }

    private Negaflow.Shell.Develop.CanvasBackgroundKind printCanvasBackground =
        Negaflow.Shell.Develop.CanvasBackgroundKind.Black;

    private void SynchronizeWidths(ShellPreferences preferences)
    {
        resizeController.Synchronize(preferences.SidebarWidth, preferences.InspectorWidth, Root.ActualWidth);
        LeftPanel.Width = resizeController.LeftWidth;
        RightPanel.Width = resizeController.RightWidth;
        UpdateCompactRail();
    }

    private void UpdateCompactRail()
    {
        LeftRailColumn.Width = new GridLength(
            LeftPanel.Width < ShellLayoutMetrics.SidebarCompactThreshold
                ? ShellLayoutMetrics.SidebarCompactRailWidth
                : ShellLayoutMetrics.SidebarRegularRailWidth);
    }

    /// <summary>언어가 바뀌면 문구를 다시 겁니다.</summary>
    public void Localize()
    {
        LocalizeControls();
        LocalizePrintInspector();
        LocalizeCustomEditor();
    }

    private void LocalizeControls()
    {
        PrintOutputSectionLocalized.Content = AppResources.Get("printOutputSection", "Content");
        AutomationProperties.SetName(
            PrintOutputSectionLocalized,
            AppResources.Get("printOutputSection", "Content"));
        PrintLayoutSectionLocalized.Text = AppResources.Get("printLayoutSection", "Text");
        SetNameAndTooltip(FilesRailButton, "libraryFiles");
        SetNameAndTooltip(ExportRailButton, "exportSection");
        FilesHeaderText.Text = AppResources.Get("libraryFiles", "Text");
        string noFrame = AppResources.Get("noFrame", "Text");
        NoFrameLeftHeaderText.Text = noFrame;
        NoFrameLeftText.Text = noFrame;
        NoFrameCenterText.Text = noFrame;
        NoFrameRightHeaderText.Text = noFrame;
        PrintHeaderText.Text = AppResources.Get("menuPrint", "Text");
        string layout = AppResources.Get("printLayoutMode", "Content");
        LayoutTabButton.Content = layout;
        AutomationProperties.SetName(LayoutTabButton, layout);
        LayoutModeText.Text = AppResources.Get("printLayoutMode", "Text");
    }

    /// <summary>
    /// macOS 출력 탭의 C-print 갈래입니다. 출력 방식·인화소·인화지·인화 프로파일·인화
    /// 미리보기가 모두 여기 붙습니다.
    /// </summary>
    private void LocalizeCprint()
    {
        OutputProcessText.Text = AppResources.Get("printOutputProcess", "Text");
        CprintSectionText.Text = AppResources.Get("printCprintSection", "Text");
        CprintLabText.Text = AppResources.Get("printCprintLab", "Text");
        CprintPaperText.Text = AppResources.Get("printCprintPaper", "Text");
        string custom = AppResources.Get("printCprintCustom", "Text");
        CprintLabBox.PlaceholderText = custom;
        CprintPaperBox.PlaceholderText = custom;
        AutomationProperties.SetName(CprintLabBox, CprintLabText.Text);
        AutomationProperties.SetName(CprintPaperBox, CprintPaperText.Text);
        PrintProofSectionText.Text = AppResources.Get("printProofSection", "Text");
        PrintProofProfileLabel.Text = AppResources.Get("printProofProfile", "Text");
        PrintProofPreviewLabel.Text = AppResources.Get("printProofPreview", "Text");
        OutputProcessSelector.SetOptions(
            [
                new Views.Controls.SegmentOption(
                    PrintOutputProcess.Standard,
                    AppResources.Get("printOutputStandard", "Text")),
                new Views.Controls.SegmentOption(
                    PrintOutputProcess.CPrint,
                    AppResources.Get("printOutputCprint", "Text")),
            ],
            PrintOutputProcess.Standard);
        PrintProofPreviewSelector.SetOptions(
            [
                new Views.Controls.SegmentOption(false, AppResources.Get("printProofOff", "Text")),
                new Views.Controls.SegmentOption(true, AppResources.Get("printProofOn", "Text")),
            ],
            false);
    }

    /// <summary>
    /// macOS 인화뷰 좌측 레일의 **파일 / 내보내기** 입니다. 둘 다 눌리며 같은 자리를 나눠 씁니다.
    /// </summary>
    private void OnPrintSourceRailClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag })
        {
            return;
        }
        ShowPrintSource(string.Equals(tag, "Export", StringComparison.Ordinal));
    }

    private bool printSourceIsExport;

    private void ShowPrintSource(bool export)
    {
        printSourceIsExport = export;
        PrintExportPanel.Visibility = export ? Visibility.Visible : Visibility.Collapsed;
        PrintFilesSourceTree.Visibility =
            export || !hasPrintFrames ? Visibility.Collapsed : Visibility.Visible;
        NoFrameLeftPanel.Visibility =
            !export && !hasPrintFrames ? Visibility.Visible : Visibility.Collapsed;
        Microsoft.UI.Xaml.Media.Brush selected =
            (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"];
        Microsoft.UI.Xaml.Media.Brush clear =
            new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
        Microsoft.UI.Xaml.Media.Brush accent =
            (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"];
        Microsoft.UI.Xaml.Media.Brush primary =
            (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["TextFillColorPrimaryBrush"];
        FilesRailButton.Background = export ? clear : selected;
        ExportRailButton.Background = export ? selected : clear;
        FilesRailIcon.Foreground = export ? primary : accent;
        ExportRailIcon.Foreground = export ? accent : primary;
        FilesHeaderText.Text = AppResources.Get(export ? "exportSection" : "libraryFiles", "Text");
    }

    /// <summary>파일 탭이 트리를 보일지 "사진 없음" 을 보일지 정하는 값입니다.</summary>
    private bool hasPrintFrames;

    /// <summary>
    /// 인화뷰 좌측 내보내기 탭을 실제로 동작하게 겁니다. macOS 도 현상뷰와 **같은
    /// `ExportSection`** 이므로 같은 컨트롤에 같은 상태를 물립니다.
    ///
    /// 이것을 안 부르면 탭은 열리지만 안이 죽어 있습니다 — 눌러도 아무 일이 없는 UI 입니다.
    /// </summary>
    public void BindExport(
        LibraryHostService host,
        ToneLimits limits,
        NegativeLimits negativeLimits,
        Microsoft.UI.WindowId windowId,
        string engineVersion)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        ArgumentNullException.ThrowIfNull(negativeLimits);
        ArgumentNullException.ThrowIfNull(engineVersion);
        printExportHost = host;
        exportPanelState = new DevelopPanelState(host, limits, negativeLimits);
        PrintExportPanel.Bind(exportPanelState, host, windowId, engineVersion);
        PrintExportPanel.Localize();
        SynchronizeExportSelection();
    }

    private DevelopPanelState? exportPanelState;
    private LibraryHostService? printExportHost;

    /// <summary>인화뷰가 보고 있는 사진이 곧 내보낼 사진입니다.</summary>
    internal void SynchronizeExportSelection()
    {
        if (exportPanelState is null || printExportHost?.ActiveFrameId is not { Length: > 0 } frameId)
        {
            return;
        }
        _ = exportPanelState.Select(frameId);
        PrintExportPanel.SynchronizeExportControls();
        PrintExportPanel.RefreshPreview();
    }

    /// <summary>
    /// macOS 인화 인스펙터의 **레이아웃 / 출력** 두 탭입니다. 카드를 두 묶음으로 갈라 두고
    /// 여기서 한 묶음만 보입니다 — macOS 도 같은 자리에서 갈아 끼웁니다.
    /// </summary>
    private void OnPrintTabClicked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not Button { Tag: string tag })
        {
            return;
        }
        ShowPrintTab(string.Equals(tag, "Output", StringComparison.Ordinal));
    }

    private void ShowPrintTab(bool output)
    {
        PrintLayoutTabPanel.Visibility = output ? Visibility.Collapsed : Visibility.Visible;
        PrintOutputTabPanel.Visibility = output ? Visibility.Visible : Visibility.Collapsed;
        Microsoft.UI.Xaml.Media.Brush selected =
            (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["NegaflowSelectionBrush"];
        Microsoft.UI.Xaml.Media.Brush clear =
            new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.Transparent);
        LayoutTabButton.Background = output ? clear : selected;
        PrintOutputSectionLocalized.Background = output ? selected : clear;
        AutomationProperties.SetItemStatus(
            LayoutTabButton,
            AppResources.Get(output ? "notSelected" : "selected", "Value"));
        AutomationProperties.SetItemStatus(
            PrintOutputSectionLocalized,
            AppResources.Get(output ? "selected" : "notSelected", "Value"));
    }

    private static void SetNameAndTooltip(Button button, string resourceKey)
    {
        string text = AppResources.Get(resourceKey, "Value");
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
        Filmstrip.FrameSelected -= OnPrintFilmstripFrameSelected;
    }
}
