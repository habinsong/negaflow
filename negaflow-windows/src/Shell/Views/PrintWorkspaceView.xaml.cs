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
    /// <summary>출력 패널이 알린 진행입니다. 위 막대가 같은 값을 보여 줍니다.</summary>
    public event EventHandler<Negaflow.Shell.Develop.ExportProgress>? ExportProgressChanged;

    private readonly ThreePaneResizeController resizeController = new();
    private WorkspacePresentationState? workspaceState;

    /// <summary>숨어 있는 동안 현상 설정이 바뀌었습니다. 다시 보일 때 판을 새로 그립니다.</summary>
    private bool printPageIsStale;

    public PrintWorkspaceView()
    {
        using (Diagnostics.StartupTrace.Measure("PrintWorkspaceView.xaml"))
        {
            InitializeComponent();
        }
        // 레이아웃·출력 카드 XAML 은 각자 UserControl 로 옮겼습니다. 이벤트는 옮기기 전과
        // 같은 이 타입의 메서드로 돌아옵니다.
        LayoutTab.Owner = this;
        OutputTab.Owner = this;
        ContentTab.Owner = this;
        BindPrintComposition();
        LocalizeControls();
        LocalizePrintInspector();
        HookPrintSegments();
    }

    public void Initialize(WorkspacePresentationState state, NativeEngineStatus nativeEngineStatus)
    {
        ArgumentNullException.ThrowIfNull(state);
        ArgumentNullException.ThrowIfNull(nativeEngineStatus);
        workspaceState = state;
        PrintFilesSourceTree.AttachPresentation(state);
        state.Changed += OnStateChanged;
        // macOS 인화 사이드바도 현상과 **같은** `ExportSection` 이므로 같은 설정을 봅니다.
        // 붙이지 않으면 이 탭에서 고친 값이 저장되지 않고 현상뷰와 따로 놀게 됩니다.
        PrintExportPanel.Attach(state);
        StatusBar.Attach(state);
        StatusBar.FilmstripPresentationChanged += (_, _) => RefreshSources();
        PrintExportPanel.ProgressChanged +=
            (_, progress) => ExportProgressChanged?.Invoke(this, progress);
        Filmstrip.Initialize(state);
        Filmstrip.FrameSelected += OnPrintFilmstripFrameSelected;
        StatusBar.Initialize(nativeEngineStatus);
        UpdateState(state.Current);
        SynchronizePrint();
        Unloaded += OnUnloaded;
    }

    /// <summary>
    /// 카탈로그의 현상 설정이 바뀌었습니다. 인화 미리보기는 현상뷰와 <b>같은 그림</b>이어야
    /// 하므로 풀어 둔 그림과 크기 판정을 버립니다.
    /// </summary>
    /// <remarks>
    /// macOS 는 <c>ScanFrame</c> 이 <c>ObservableObject</c> 라 값이 바뀌는 순간 인화 판이
    /// 저절로 따라옵니다. WinUI 에는 그 관찰이 없어 알려 주지 않으면 인화 판은 <b>처음
    /// 그린 그림에 그대로 멈춰 있습니다</b> — 현상뷰에서 자동 레벨·자동 색상을 껐는데도
    /// 인화뷰에는 켠 그림이 남아 있던 원인입니다(실측: 현상 3회 변경, 인화 재요청 0회).
    ///
    /// 숨어 있을 때는 표시만 남깁니다. 현상뷰에서 슬라이더를 끄는 동안 편집마다 숨은 판을
    /// 다시 그리면 그 값이 그대로 UI 스레드 비용이 됩니다.
    /// </remarks>
    public void NotifyFrameEdited()
    {
        printPreview?.InvalidateForRecipeChange();
        if (Visibility == Visibility.Visible)
        {
            printPreview?.Draw();
            return;
        }
        printPageIsStale = true;
    }

    /// <summary>인화뷰가 다시 보일 때입니다. 숨은 동안 바뀐 것이 있으면 그때 그립니다.</summary>
    public void RedrawIfStale()
    {
        if (!printPageIsStale)
        {
            return;
        }
        printPageIsStale = false;
        printPreview?.Draw();
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
        // 캡슐의 글자·아이콘 색은 <b>캔버스 배경</b>을 따릅니다 — 검정·회색이면 흰색,
        // 흰색이면 검정입니다(macOS `CanvasBackground.hudContentColor`). 라이트·다크
        // 모드와는 무관합니다.
        PrintZoomHud.ApplyChrome(Negaflow.Shell.Develop.CanvasHudChrome.For(background));
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
        // 좌측 레일 머리글은 고른 갈래(파일/내보내기)에 따라 다릅니다 —
        // `LocalizeControls` 가 "파일" 로 되돌려 놓으므로 여기서 다시 맞춥니다.
        ShowPrintSource(printSourceIsExport);
        StatusBar.Localize();
        // 사이드바 머리글·필름스트립 항목 이름은 만들 때 정해집니다.
        printSources?.Localize();
        // 미리보기 안의 "N페이지"·용지 크기 요약도 리소스 문구라 다시 그려야 바뀝니다.
        printPreview?.Draw();
    }

    private void LocalizeControls()
    {
        // 인스펙터 탭 셋입니다. macOS `PrintWorkspaceInspector.tabTitle` 과 같은 문구입니다.
        OutputTabText.Text = AppResources.Get("printOutputSection", "Content");
        AutomationProperties.SetName(OutputTabButton, OutputTabText.Text);
        ContentTabText.Text = AppResources.Get("printContentSection", "Text");
        AutomationProperties.SetName(ContentTabButton, ContentTabText.Text);
        LayoutTab.PrintLayoutSectionLocalized.Text = AppResources.Get("printLayoutSection", "Text");
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
        LayoutTabText.Text = layout;
        AutomationProperties.SetName(LayoutTabButton, layout);
    }

    /// <summary>
    /// macOS 출력 탭의 C-print 갈래입니다. 출력 방식·인화소·인화지·인화 프로파일·인화
    /// 미리보기가 모두 여기 붙습니다.
    /// </summary>
    private void LocalizeCprint()
    {
        OutputTab.OutputProcessField.Label = AppResources.Get("printOutputProcess", "Text");
        OutputTab.CprintSectionText.Text = AppResources.Get("printCprintSection", "Text");
        // 라벨은 이제 `PrintInspectorInlineField`·`PrintInspectorStackedField` 가 들고
        // 있습니다 — 자리마다 TextBlock 을 따로 두면 macOS 의 라벨 폭·간격이 어긋납니다.
        OutputTab.CprintLabField.Label = AppResources.Get("printCprintLab", "Text");
        OutputTab.CprintPaperField.Label = AppResources.Get("printCprintPaper", "Text");
        string custom = AppResources.Get("printCprintCustom", "Text");
        OutputTab.CprintLabBox.PlaceholderText = custom;
        OutputTab.CprintPaperBox.PlaceholderText = custom;
        AutomationProperties.SetName(OutputTab.CprintLabBox, OutputTab.CprintLabField.Label);
        AutomationProperties.SetName(OutputTab.CprintPaperBox, OutputTab.CprintPaperField.Label);
        OutputTab.PrintProofSectionText.Text = AppResources.Get("printProofSection", "Text");
        OutputTab.ProofProfileField.Label = AppResources.Get("printProofProfile", "Text");
        OutputTab.ProofPreviewField.Label = AppResources.Get("printProofPreview", "Text");
        OutputTab.OutputProcessSelector.SetOptions(
            [
                new Views.Controls.SegmentOption(
                    PrintOutputProcess.Standard,
                    AppResources.Get("printOutputStandard", "Text")),
                new Views.Controls.SegmentOption(
                    PrintOutputProcess.CPrint,
                    AppResources.Get("printOutputCprint", "Text")),
            ],
            // 언어를 바꿀 때도 이 길로 다시 옵니다 — 고른 값을 그대로 두어야 합니다.
            OutputTab.OutputProcessSelector.SelectedValue ?? PrintOutputProcess.Standard);
        OutputTab.PrintProofPreviewSelector.SetOptions(
            [
                new Views.Controls.SegmentOption(false, AppResources.Get("printProofOff", "Text")),
                new Views.Controls.SegmentOption(true, AppResources.Get("printProofOn", "Text")),
            ],
            OutputTab.PrintProofPreviewSelector.SelectedValue ?? false);
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
    private void OnPrintTabChecked(object sender, RoutedEventArgs args)
    {
        _ = args;
        if (sender is not RadioButton { Tag: string tag })
        {
            return;
        }
        ShowPrintTab(tag);
    }

    /// <summary>지금 열려 있는 인스펙터 탭입니다. 레이아웃 · 콘텐츠 · 출력 셋입니다.</summary>
    private string selectedInspectorTab = "Layout";

    /// <summary>
    /// 탭을 갈아 끼웁니다. macOS <c>PrintWorkspaceInspector.selectedTabContent</c> 자리입니다.
    /// </summary>
    private void ShowPrintTab(string tag)
    {
        selectedInspectorTab = tag;
        LayoutTab.Visibility = Visible(tag == "Layout");
        ContentTab.Visibility = Visible(tag == "Content");
        OutputTab.Visibility = Visible(tag == "Output");

        // 고른 칸의 음영은 판형(`NegaflowPrintTabStyle`)의 CheckStates 가 그립니다 —
        // 코드에서 `Application.Current.Resources` 로 브러시를 읽으면 요소의 테마가 아니라
        // 앱의 테마로 풀려 창이 어두운데 밝은 색이 나옵니다.
        LayoutTabButton.IsChecked = tag == "Layout";
        ContentTabButton.IsChecked = tag == "Content";
        OutputTabButton.IsChecked = tag == "Output";
        MarkTabStatus(LayoutTabButton, tag == "Layout");
        MarkTabStatus(ContentTabButton, tag == "Content");
        MarkTabStatus(OutputTabButton, tag == "Output");
        PaintTabIcons();
    }

    /// <summary>
    /// 캡슐의 아이콘을 글자와 같은 색으로 칠합니다. 고른 칸은 강조색, 나머지는 본문색입니다 —
    /// macOS <c>PrintInspectorTabButton</c> 도 아이콘과 글자를 한 색으로 냅니다.
    /// </summary>
    /// <remarks>
    /// 아이콘은 <see cref="Controls.VectorIcon"/> 이라 판형의 <c>Checked</c> 세터가 칠하는
    /// <c>ContentPresenter.Foreground</c> 를 <b>물려받지 못합니다</b>. 글자에 바인딩으로
    /// 묶어 보았지만 상속값이 바뀔 때 알림이 오지 않아 한 번 파랗게 된 아이콘이 그대로
    /// 남았습니다. 그래서 여기서 직접 칠합니다.
    ///
    /// 색은 <b>이 요소의 테마</b>로 풉니다. <c>Application.Current.Resources</c> 를 그냥
    /// 읽으면 앱 테마로 풀려, 창이 어두운데 밝은 테마의 색이 나옵니다.
    /// </remarks>
    private void PaintTabIcons()
    {
        Microsoft.UI.Xaml.Media.Brush? accent = ThemedBrush("NegaflowAccentBrush");
        Microsoft.UI.Xaml.Media.Brush? primary = ThemedBrush("TextFillColorPrimaryBrush");
        Paint(LayoutTabIcon, LayoutTabButton.IsChecked == true);
        Paint(ContentTabIcon, ContentTabButton.IsChecked == true);
        Paint(OutputTabIcon, OutputTabButton.IsChecked == true);

        void Paint(Controls.VectorIcon icon, bool selected)
        {
            if ((selected ? accent : primary) is { } brush)
            {
                icon.Foreground = brush;
            }
        }
    }

    /// <summary>이 요소의 테마로 푼 브러시입니다. 없으면 평평한 사전에서 찾습니다.</summary>
    private Microsoft.UI.Xaml.Media.Brush? ThemedBrush(string key)
    {
        string theme = ActualTheme == ElementTheme.Dark ? "Dark" : "Light";
        if (Application.Current.Resources.ThemeDictionaries.TryGetValue(theme, out object? entry) &&
            entry is ResourceDictionary dictionary &&
            dictionary.TryGetValue(key, out object? themed) &&
            themed is Microsoft.UI.Xaml.Media.Brush themedBrush)
        {
            return themedBrush;
        }
        return Application.Current.Resources.TryGetValue(key, out object? flat)
            ? flat as Microsoft.UI.Xaml.Media.Brush
            : null;
    }

    private static void MarkTabStatus(RadioButton button, bool isSelected) =>
        AutomationProperties.SetItemStatus(
            button,
            AppResources.Get(isSelected ? "selected" : "notSelected", "Value"));

    /// <summary>
    /// 콘텐츠 탭은 한 판에 여러 장을 놓는 모드에서만 있습니다 — macOS
    /// <c>availableTabs</c> 와 같습니다. 사라질 때 그 탭을 보고 있었으면 레이아웃으로
    /// 돌려보냅니다(macOS <c>onChange(of: layoutMode)</c>).
    /// </summary>
    internal void ApplyInspectorTabAvailability(PrintPreferences print)
    {
        bool package = PrintPreferences.PackageModeFor(print.LayoutMode) is not null;
        ContentTabButton.Visibility = Visible(package);
        ContentTabColumn.Width = package
            ? new GridLength(1, GridUnitType.Star)
            : new GridLength(0);
        if (!package && selectedInspectorTab == "Content")
        {
            ShowPrintTab("Layout");
        }
    }

    private static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

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
