using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 검사기 고르개와 설정을 맞춥니다. 판을 그리는 일과 다른 이유로 바뀝니다.
/// </summary>
internal sealed class PrintInspectorBinder
{
    private readonly PrintInspectorSurface surface;
    private bool isSynchronizing;

    internal PrintInspectorBinder(PrintInspectorSurface surface) => this.surface = surface;

    internal bool IsSynchronizing => isSynchronizing;

    internal void Localize()
    {
        surface.LayoutModeText.Text = AppResources.Get("printLayoutMode", "Text");
        surface.PaperSizeText.Text = AppResources.Get("printPaperSize", "Text");
        surface.OrientationText.Text = AppResources.Get("printOrientation", "Text");
        surface.PerforationText.Text = AppResources.Get("printPerforation", "Text");
        surface.DpiText.Text = AppResources.Get("printResolution", "Text");
        surface.SheetSectionText.Text = AppResources.Get("printSheetSection", "Text");
        surface.RowsText.Text = AppResources.Get("printRows", "Text");
        surface.ColumnsText.Text = AppResources.Get("printColumns", "Text");
        surface.ContentModeText.Text = AppResources.Get("printContentMode", "Text");
        surface.SheetBackgroundText.Text = AppResources.Get("printSheetBackground", "Text");
        surface.OutputSectionText.Text = AppResources.Get("printOutputSection", "Content");
        PrintChoice<bool>.SetToggleLabel(
            surface.RotateToFitToggle, AppResources.Get("printRotateToFit", "Text"));
        PrintChoice<bool>.SetToggleLabel(
            surface.RepeatToggle, AppResources.Get("printRepeatOnePhoto", "Text"));
        surface.PrintExportButton.Content = AppResources.Get("printExport", "Content");

        surface.LayoutModeSelector.ItemsSource = new[]
        {
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.SingleImage, "printModeSingle"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.ContactSheet, "printModeContactSheet"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.PicturePackage, "printModePicturePackage"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.CustomPackage, "printModeCustomPackage"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.Cyanotype, "printModeCyanotype"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.GlassPlate, "printModeGlassPlate"),
            PrintChoice<PrintLayoutMode>.FromResource(PrintLayoutMode.Gelatin, "printModeGelatin"),
        };
        surface.PaperSizeSelector.ItemsSource = PrintPaper.All
            .Select(size => new PrintChoice<PrintPaperSize>(size, PrintPaper.Label(size)))
            .ToArray();
        PrintChoice<PrintPaperOrientation>.Fill(
            surface.OrientationSelector,
            [
            PrintChoice<PrintPaperOrientation>.FromResource(PrintPaperOrientation.Automatic, "printOrientationAuto"),
            PrintChoice<PrintPaperOrientation>.FromResource(PrintPaperOrientation.Portrait, "printOrientationPortrait"),
            PrintChoice<PrintPaperOrientation>.FromResource(PrintPaperOrientation.Landscape, "printOrientationLandscape"),
            ],
            PrintPaperOrientation.Automatic);
        surface.PerforationSelector.ItemsSource = new[]
        {
            PrintChoice<PrintPerforationStyle>.FromResource(PrintPerforationStyle.None, "printPerforationNone"),
            PrintChoice<PrintPerforationStyle>.FromResource(
                PrintPerforationStyle.ThirtyFiveMillimeter, "printPerforation35mm"),
        };
        // macOS 와 같은 네 단계입니다. 인화소가 받는 값이라 번역하지 않습니다.
        surface.DpiSelector.ItemsSource = new[] { 150, 240, 300, 360, 600 }
            .Select(dpi => new PrintChoice<int>(dpi, $"{dpi} dpi"))
            .ToArray();
        surface.ContentModeSelector.ItemsSource = new[]
        {
            PrintChoice<PrintPackageContentMode>.FromResource(PrintPackageContentMode.Fit, "printFit"),
            PrintChoice<PrintPackageContentMode>.FromResource(PrintPackageContentMode.Fill, "printFill"),
        };
        PrintChoice<PrintSheetBackground>.Fill(
            surface.SheetBackgroundSelector,
            [
            PrintChoice<PrintSheetBackground>.FromResource(PrintSheetBackground.White, "printBackgroundWhite"),
            PrintChoice<PrintSheetBackground>.FromResource(PrintSheetBackground.Gray, "printBackgroundGray"),
            PrintChoice<PrintSheetBackground>.FromResource(PrintSheetBackground.Black, "printBackgroundBlack"),
            ],
            PrintSheetBackground.Black);
        surface.TemplateText.Text = AppResources.Get("printTemplate", "Text");
        surface.TemplateSelector.ItemsSource = new[]
        {
            PrintChoice<PrintPicturePackageTemplate>.FromResource(
                PrintPicturePackageTemplate.OneLargeTwoSmall, "printTemplateOneLargeTwoSmall"),
            PrintChoice<PrintPicturePackageTemplate>.FromResource(
                PrintPicturePackageTemplate.TwoUp, "printTemplateTwoUp"),
            PrintChoice<PrintPicturePackageTemplate>.FromResource(
                PrintPicturePackageTemplate.FourUp, "printTemplateFourUp"),
        };
        surface.CaptionModeText.Text = AppResources.Get("printCaption", "Text");
        surface.CaptionModeSelector.ItemsSource = new[]
        {
            PrintChoice<PrintPackageCaptionMode>.FromResource(PrintPackageCaptionMode.None, "printCaptionNone"),
            PrintChoice<PrintPackageCaptionMode>.FromResource(PrintPackageCaptionMode.FileName, "printCaptionFileName"),
            PrintChoice<PrintPackageCaptionMode>.FromResource(PrintPackageCaptionMode.FrameNumber, "printCaptionFrameNumber"),
            PrintChoice<PrintPackageCaptionMode>.FromResource(PrintPackageCaptionMode.SequenceNumber, "printCaptionSequence"),
            PrintChoice<PrintPackageCaptionMode>.FromResource(PrintPackageCaptionMode.Rating, "printCaptionRating"),
        };
        PrintChoice<bool>.SetToggleLabel(
            surface.CropMarksToggle, AppResources.Get("printCropMarks", "Text"));
        surface.ViewSectionText.Text = AppResources.Get("printViewSection", "Text");
        PrintChoice<bool>.SetToggleLabel(
            surface.RulersToggle, AppResources.Get("printRulers", "Text"));
        surface.RulerUnitText.Text = AppResources.Get("printRulerUnit", "Text");
        PrintChoice<PrintRulerUnit>.Fill(
            surface.RulerUnitSelector,
            [
            PrintChoice<PrintRulerUnit>.FromResource(PrintRulerUnit.Centimeters, "printRulerCentimeters"),
            PrintChoice<PrintRulerUnit>.FromResource(PrintRulerUnit.Inches, "printRulerInches"),
            ],
            PrintRulerUnit.Inches);
    }

    /// <summary>고른 값을 설정에 담습니다. 담긴 값이 곧 미리보기와 파일을 정합니다.</summary>
    internal void Commit(WorkspacePresentationState state)
    {
        if (isSynchronizing)
        {
            return;
        }
        state.UpdatePrint(current => current with
        {
            LayoutMode = PrintChoice<PrintLayoutMode>.Selected(surface.LayoutModeSelector, current.LayoutMode),
            PaperSize = PrintChoice<PrintPaperSize>.Selected(surface.PaperSizeSelector, current.PaperSize),
            Orientation = PrintChoice<PrintPaperOrientation>.Selected(
                surface.OrientationSelector, current.Orientation),
            PerforationStyle = PrintChoice<PrintPerforationStyle>.Selected(
                surface.PerforationSelector, current.PerforationStyle),
            Dpi = PrintChoice<int>.Selected(surface.DpiSelector, current.Dpi),
            MarginMm = surface.MarginSlider.Value,
            ContactRows = (int)Math.Round(
                double.IsNaN(surface.RowsBox.Value) ? current.ContactRows : surface.RowsBox.Value),
            ContactColumns = (int)Math.Round(
                double.IsNaN(surface.ColumnsBox.Value) ? current.ContactColumns : surface.ColumnsBox.Value),
            HorizontalSpacingMm = surface.SpacingSlider.Value,
            VerticalSpacingMm = surface.SpacingSlider.Value,
            ContentMode = PrintChoice<PrintPackageContentMode>.Selected(
                surface.ContentModeSelector, current.ContentMode),
            RotateToFit = surface.RotateToFitToggle.IsOn,
            RepeatOnePhotoPerPage = surface.RepeatToggle.IsOn,
            SheetBackground = PrintChoice<PrintSheetBackground>.Selected(
                surface.SheetBackgroundSelector, current.SheetBackground),
            PictureTemplate = PrintChoice<PrintPicturePackageTemplate>.Selected(
                surface.TemplateSelector, current.PictureTemplate),
            CaptionMode = PrintChoice<PrintPackageCaptionMode>.Selected(
                surface.CaptionModeSelector, current.CaptionMode),
            ShowsCropMarks = surface.CropMarksToggle.IsOn,
            ShowsRulers = surface.RulersToggle.IsOn,
            RulerUnit = PrintChoice<PrintRulerUnit>.Selected(surface.RulerUnitSelector, current.RulerUnit),
            OutputProcess = PrintChoice<PrintOutputProcess>.Selected(
                surface.OutputProcessSelector, current.OutputProcess),
            CPrintLabName = surface.CprintLabBox.Text,
            CPrintPaperName = surface.CprintPaperBox.Text,
            CPrintPreviewEnabled =
                surface.PrintProofPreviewSelector.SelectedValue is bool on && on,
        });
    }

    /// <summary>설정과 선택을 화면에 맞춥니다. 판 그리기는 호출자가 이어서 합니다.</summary>
    internal void Apply(PrintPreferences print)
    {
        if (surface.LayoutModeSelector is null)
        {
            return;
        }
        isSynchronizing = true;
        try
        {
            PrintChoice<PrintLayoutMode>.Select(surface.LayoutModeSelector, print.LayoutMode);
            PrintChoice<PrintPaperSize>.Select(surface.PaperSizeSelector, print.PaperSize);
            PrintChoice<PrintPaperOrientation>.Select(surface.OrientationSelector, print.Orientation);
            PrintChoice<PrintPerforationStyle>.Select(surface.PerforationSelector, print.PerforationStyle);
            PrintChoice<int>.Select(surface.DpiSelector, print.Dpi);
            surface.MarginSlider.Value = print.MarginMm;
            surface.RowsBox.Value = print.ContactRows;
            surface.ColumnsBox.Value = print.ContactColumns;
            surface.SpacingSlider.Value = print.HorizontalSpacingMm;
            PrintChoice<PrintPackageContentMode>.Select(surface.ContentModeSelector, print.ContentMode);
            PrintChoice<PrintOutputProcess>.Select(surface.OutputProcessSelector, print.OutputProcess);
            surface.CprintLabBox.Text = print.CPrintLabName;
            surface.CprintPaperBox.Text = print.CPrintPaperName;
            surface.PrintProofPreviewSelector.SetSelected(print.CPrintPreviewEnabled);
            surface.RotateToFitToggle.IsOn = print.RotateToFit;
            surface.RepeatToggle.IsOn = print.RepeatOnePhotoPerPage;
            PrintChoice<PrintSheetBackground>.Select(surface.SheetBackgroundSelector, print.SheetBackground);
            PrintChoice<PrintPicturePackageTemplate>.Select(surface.TemplateSelector, print.PictureTemplate);
            PrintChoice<PrintPackageCaptionMode>.Select(surface.CaptionModeSelector, print.CaptionMode);
            surface.CropMarksToggle.IsOn = print.ShowsCropMarks;
            surface.RulersToggle.IsOn = print.ShowsRulers;
            PrintChoice<PrintRulerUnit>.Select(surface.RulerUnitSelector, print.RulerUnit);
        }
        finally
        {
            isSynchronizing = false;
        }

        surface.MarginText.Text = AppResources
            .Get("printMarginFormat", "Text")
            .Replace("{0}", print.MarginMm.ToString("0.#",
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
        surface.SpacingText.Text = AppResources
            .Get("printSpacingFormat", "Text")
            .Replace("{0}", print.HorizontalSpacingMm.ToString("0.#",
                System.Globalization.CultureInfo.CurrentCulture), StringComparison.Ordinal);
        surface.SheetCard.Visibility = PrintPreferences.PackageModeFor(print.LayoutMode) is null
            ? Visibility.Collapsed
            : Visibility.Visible;
        // 템플릿은 픽처 패키지에만 있습니다 — 컨택트 시트는 행·열이 곧 배치입니다.
        surface.TemplatePanel.Visibility = print.LayoutMode == PrintLayoutMode.PicturePackage
            ? Visibility.Visible
            : Visibility.Collapsed;
        surface.RulerUnitSelector.IsEnabled = print.ShowsRulers;
        surface.CustomCard.Visibility = print.LayoutMode == PrintLayoutMode.CustomPackage
            ? Visibility.Visible
            : Visibility.Collapsed;
        surface.CustomHintText.Text = AppResources.Get("printCustomHint", "Text");
    }
}
