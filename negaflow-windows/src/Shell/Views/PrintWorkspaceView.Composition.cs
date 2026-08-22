using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI;
using Negaflow.Catalog;
using Microsoft.UI.Xaml.Automation;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views.Print.Export;
using Negaflow.Shell.Views.Print.Preview;
using Negaflow.Shell.Views.Print.Settings;
using Negaflow.Shell.Views.Print.Sources;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 화면의 소스·검사기·미리보기·게시를 실제 타입에 넘기는 배선입니다.
/// </summary>
public sealed partial class PrintWorkspaceView
{
    private PrintSourceController? printSources;
    private PrintInspectorBinder? printInspector;
    private PrintPreviewRenderer? printPreview;
    private PrintExportWorkflow? printExport;

    private void BindPrintComposition()
    {
        printSources = new PrintSourceController(
            new PrintSourceSurface
            {
                FilesTree = PrintFilesSourceTree,
                LeftHeader = NoFrameLeftHeaderText,
                RightHeader = NoFrameRightHeaderText,
                NoFrameLeftPanel = NoFrameLeftPanel,
                Filmstrip = Filmstrip,
                ApplySourcePane = frames =>
                {
                    hasPrintFrames = frames;
                    ShowPrintSource(printSourceIsExport);
                },
            },
            SynchronizePrint);
        PrintFilesSourceTree.FrameInvoked += (sender, frameId) =>
            printSources?.HandleTreeInvoked(sender, frameId);
        printInspector = new PrintInspectorBinder(
            new PrintInspectorSurface
            {
                LayoutModeText = LayoutModeText,
                LayoutModeSelector = LayoutModeSelector,
                PaperSizeText = PaperSizeText,
                PaperSizeSelector = PaperSizeSelector,
                OrientationText = OrientationText,
                OrientationSelector = OrientationSelector,
                PerforationText = PerforationText,
                PerforationSelector = PerforationSelector,
                DpiText = DpiText,
                DpiSelector = DpiSelector,
                MarginText = MarginText,
                MarginSlider = MarginSlider,
                SheetCard = SheetCard,
                SheetSectionText = SheetSectionText,
                RowsText = RowsText,
                RowsBox = RowsBox,
                ColumnsText = ColumnsText,
                ColumnsBox = ColumnsBox,
                SpacingText = SpacingText,
                SpacingSlider = SpacingSlider,
                ContentModeText = ContentModeText,
                ContentModeSelector = ContentModeSelector,
                RotateToFitToggle = RotateToFitToggle,
                RepeatToggle = RepeatToggle,
                SheetBackgroundText = SheetBackgroundText,
                SheetBackgroundSelector = SheetBackgroundSelector,
                TemplatePanel = TemplatePanel,
                TemplateText = TemplateText,
                TemplateSelector = TemplateSelector,
                CaptionModeText = CaptionModeText,
                CaptionModeSelector = CaptionModeSelector,
                CropMarksToggle = CropMarksToggle,
                ViewSectionText = ViewSectionText,
                RulersToggle = RulersToggle,
                RulerUnitText = RulerUnitText,
                RulerUnitSelector = RulerUnitSelector,
                OutputProcessSelector = OutputProcessSelector,
                CprintLabBox = CprintLabBox,
                CprintPaperBox = CprintPaperBox,
                PrintProofPreviewSelector = PrintProofPreviewSelector,
                CustomCard = CustomCard,
                CustomHintText = CustomHintText,
                OutputSectionText = OutputSectionText,
                PrintExportButton = PrintExportButton,
            });
        printPreview = new PrintPreviewRenderer(
            new PrintPreviewSurface
            {
                CanvasHost = CanvasHost,
                PageBorder = PageBorder,
                PageCanvas = PageCanvas,
                RulerCanvas = RulerCanvas,
                NoFramePanel = NoFramePanel,
                PageCountText = PageCountText,
                PageSizeSummaryText = PageSizeSummaryText,
                PrintExportButton = PrintExportButton,
            },
            () => PrintSources,
            () => printSources?.Thumbnails,
            () => workspaceState,
            DrawCustomEditor);
        printExport = new PrintExportWorkflow(PrintExportButton, PrintStatusText, TextRasterHost);
    }

    /// <summary>
    /// 인화할 사진들입니다. 라이브러리에서 고른 것을 그대로 씁니다 — macOS 도 같은 선택을
    /// 봅니다.
    /// </summary>
    private IReadOnlyList<LibraryFrameSnapshot> PrintSources =>
        printSources?.Sources ?? [];

    public void AttachThumbnails(Negaflow.Shell.Library.ThumbnailService service) =>
        printSources?.AttachThumbnails(service);

    public void ShowLibrary(LibraryHostService host) => printSources?.ShowLibrary(host);

    public void AttachWindow(Microsoft.UI.WindowId windowId) =>
        printExport?.AttachWindow(windowId);



    private void OnPrintFilmstripFrameSelected(object? sender, LibraryFrameListItem item) =>
        printSources?.HandleFilmstripSelected(sender, item);

    private void LocalizePrintInspector()
    {
        printInspector?.Localize();
        LocalizeCprint();
        LocalizeLayoutTemplates();
    }

    /// <summary>
    /// 세그먼트는 XAML 에서 `SelectionChanged` 를 걸 수 없어(이벤트가 컨트롤 것이라) 여기서
    /// 겁니다. 안 걸면 눌러도 값이 안 바뀌는 가짜가 됩니다.
    /// </summary>
    private void HookPrintSegments()
    {
        OrientationSelector.SelectionChanged += OnPrintSegmentChanged;
        SheetBackgroundSelector.SelectionChanged += OnPrintSegmentChanged;
        RulerUnitSelector.SelectionChanged += OnPrintSegmentChanged;
        OutputProcessSelector.SelectionChanged += OnPrintSegmentChanged;
        PrintProofPreviewSelector.SelectionChanged += OnPrintSegmentChanged;
    }

    /// <summary>
    /// C-print 를 골랐을 때만 인화소·인화지·인화 프로파일이 나옵니다. macOS 도 일반 출력에서는
    /// 그 카드들을 내리므로, 여기서도 같은 자리에서 감춥니다.
    /// </summary>
    internal void ApplyCprintVisibility(PrintPreferences print)
    {
        ArgumentNullException.ThrowIfNull(print);
        bool cprint = print.OutputProcess == PrintOutputProcess.CPrint;
        CprintCard.Visibility = cprint ? Visibility.Visible : Visibility.Collapsed;
        PrintProofCard.Visibility = CprintCard.Visibility;
        PrintProofProfileText.Text = print.CPrintProofProfileName;
        PrintProofClearButton.IsEnabled = !string.IsNullOrWhiteSpace(print.CPrintProofProfilePath);
        // 프로파일이 없으면 미리보기를 켤 수 없습니다 — 흉내 낼 대상이 없습니다.
        PrintProofPreviewSelector.IsEnabled = PrintProofClearButton.IsEnabled;
    }

    /// <summary>
    /// macOS <c>PrintLayoutTemplateStore</c> 자리입니다. 앱 데이터 폴더에 한 파일로 삽니다 —
    /// macOS 도 `Application Support/negaflow/print-layout-templates.json` 한 장입니다.
    /// </summary>
    private PrintLayoutTemplateStore? layoutTemplates;

    private PrintLayoutTemplateStore Templates => layoutTemplates ??= new PrintLayoutTemplateStore(
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Negaflow",
            "print-layout-templates.json"));

    internal void LocalizeLayoutTemplates()
    {
        LayoutTemplateSectionText.Text = AppResources.Get("printLayoutTemplateSection", "Text");
        LayoutTemplateNameLabel.Text = AppResources.Get("printLayoutTemplateName", "Text");
        LayoutTemplateNameBox.PlaceholderText = LayoutTemplateNameLabel.Text;
        AutomationProperties.SetName(LayoutTemplateNameBox, LayoutTemplateNameLabel.Text);
        LayoutTemplateSaveButton.Content = AppResources.Get("printLayoutTemplateSave", "Content");
        LayoutTemplateApplyButton.Content = AppResources.Get("printLayoutTemplateApply", "Content");
        LayoutTemplateDeleteButton.Content = AppResources.Get("printLayoutTemplateDelete", "Content");
        RefreshLayoutTemplates();
    }

    private void RefreshLayoutTemplates()
    {
        LayoutTemplateSelector.ItemsSource = Templates.Templates;
        bool hasTemplates = Templates.Templates.Count > 0;
        LayoutTemplateAppliedRow.Visibility =
            hasTemplates ? Visibility.Visible : Visibility.Collapsed;
        if (hasTemplates && LayoutTemplateSelector.SelectedIndex < 0)
        {
            LayoutTemplateSelector.SelectedIndex = 0;
        }
        LayoutTemplateSaveButton.IsEnabled = Templates.CanModify &&
            !string.IsNullOrWhiteSpace(LayoutTemplateNameBox.Text) &&
            Templates.Templates.Count < PrintLayoutTemplateStore.MaximumTemplateCount;
        LayoutTemplateStatusText.Text = Templates.CanModify
            ? string.Empty
            : AppResources.Get("printLayoutTemplateLocked", "Text");
    }

    private void OnLayoutTemplateNameChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        LayoutTemplateSaveButton.IsEnabled = Templates.CanModify &&
            !string.IsNullOrWhiteSpace(LayoutTemplateNameBox.Text) &&
            Templates.Templates.Count < PrintLayoutTemplateStore.MaximumTemplateCount;
    }

    private void OnLayoutTemplateSaveClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is not { } state)
        {
            return;
        }
        if (Templates.Templates.Count >= PrintLayoutTemplateStore.MaximumTemplateCount)
        {
            LayoutTemplateStatusText.Text = AppResources.Get("printLayoutTemplateFull", "Text");
            return;
        }
        if (Templates.Add(
                LayoutTemplateNameBox.Text,
                PrintLayoutTemplateSettings.From(state.Current.Print)) is null)
        {
            LayoutTemplateStatusText.Text = Templates.CanModify
                ? AppResources.Get("printLayoutTemplateDuplicate", "Text")
                : AppResources.Get("printLayoutTemplateLocked", "Text");
            return;
        }
        LayoutTemplateNameBox.Text = string.Empty;
        RefreshLayoutTemplates();
    }

    private void OnLayoutTemplateApplyClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is null ||
            LayoutTemplateSelector.SelectedItem is not PrintLayoutTemplate template)
        {
            return;
        }
        workspaceState.UpdatePrint(current => template.Settings.ApplyTo(current));
    }

    private void OnLayoutTemplateDeleteClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (LayoutTemplateSelector.SelectedItem is PrintLayoutTemplate template &&
            Templates.Delete(template.Id))
        {
            RefreshLayoutTemplates();
        }
    }

    private void OnCprintTextChanged(object sender, TextChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    /// <summary>
    /// 인화소가 준 ICC 를 고릅니다. macOS <c>selectCPrintProofICCProfile</c> — 고르면 미리보기가
    /// 함께 켜집니다.
    /// </summary>
    private async void OnPrintProofChooseClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        if (workspaceState is null || printExport?.WindowId is not { } windowId)
        {
            return;
        }
        Windows.Storage.Pickers.FileOpenPicker picker = new();
        picker.FileTypeFilter.Add(".icc");
        picker.FileTypeFilter.Add(".icm");
        WinRT.Interop.InitializeWithWindow.Initialize(
            picker,
            Win32Interop.GetWindowFromWindowId(windowId));
        if (await picker.PickSingleFileAsync() is not { } file)
        {
            return;
        }
        workspaceState.UpdatePrint(current => current with
        {
            CPrintProofProfilePath = file.Path,
            CPrintProofProfileName = Path.GetFileNameWithoutExtension(file.Path),
            CPrintPreviewEnabled = true,
        });
    }

    /// <summary>macOS <c>clearCPrintProofICCProfile</c> — 지우면 미리보기도 함께 꺼집니다.</summary>
    private void OnPrintProofClearClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        workspaceState?.UpdatePrint(current => current with
        {
            CPrintProofProfilePath = string.Empty,
            CPrintProofProfileName = string.Empty,
            CPrintPreviewEnabled = false,
        });
    }

    private void OnPrintSegmentChanged(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintSettingChanged(object sender, SelectionChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintSliderChanged(object sender, RangeBaseValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintNumberChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void OnPrintToggled(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        CommitPrintSettings();
    }

    private void CommitPrintSettings()
    {
        if (printInspector is null ||
            printInspector.IsSynchronizing ||
            workspaceState is not { } state)
        {
            return;
        }
        printInspector.Commit(state);
        SynchronizePrint();
    }

    /// <summary>설정과 선택을 화면에 맞춥니다.</summary>
    private void SynchronizePrint()
    {
        if (printInspector is null || workspaceState is not { } state)
        {
            return;
        }
        printInspector.Apply(state.Current.Print);
        ApplyCprintVisibility(state.Current.Print);
        SynchronizeExportSelection();
        SeedCustomLayoutIfEmpty();
        printPreview?.Draw();
    }

    private void OnCanvasHostSizeChanged(object sender, SizeChangedEventArgs args)
    {
        _ = sender;
        _ = args;
        printPreview?.Draw();
    }

    private void OnPrintExportClicked(object sender, RoutedEventArgs args)
    {
        _ = sender;
        _ = args;
        ExportFromMenu();
    }

    /// <summary>macOS 인화 모듈의 <c>exportSelectionToFolder(for:)</c> 입니다.</summary>
    internal void ExportFromMenu() => printExport?.Export(workspaceState, PrintSources);

    private static PrintSizeMm SourcePixelSize(LibraryFrameSnapshot frame) =>
        PrintPreviewRenderer.SourcePixelSize(frame);

    private double PreviewScale(PrintSizeMm canvas) =>
        printPreview?.PreviewScale(canvas) ?? 1;
}
