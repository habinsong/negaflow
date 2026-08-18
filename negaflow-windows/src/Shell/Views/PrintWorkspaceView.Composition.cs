using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Negaflow.Catalog;
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
            },
            SynchronizePrint);
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

    private void OnPrintFilesTreeItemInvoked(TreeView sender, TreeViewItemInvokedEventArgs args) =>
        printSources?.HandleTreeInvoked(sender, args);

    private void OnPrintFilmstripFrameSelected(object? sender, LibraryFrameListItem item) =>
        printSources?.HandleFilmstripSelected(sender, item);

    private void LocalizePrintInspector() => printInspector?.Localize();

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
