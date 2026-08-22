using Microsoft.UI.Xaml;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Print;
using Negaflow.Shell.Views.Controls;
using Negaflow.Shell;

namespace Negaflow.Shell.Views.Print.Settings;

/// <summary>
/// 검사기 고르개와 설정을 맞춥니다. 판을 그리는 일과 다른 이유로 바뀝니다.
/// </summary>
/// <remarks>
/// 줄 차례와 어느 줄이 언제 나오는지는 macOS <c>PrintWorkspaceInspector</c> 를 따릅니다 —
/// 퍼포레이션과 해상도는 macOS 인화 인스펙터에 없으므로 여기에도 없습니다.
/// </remarks>
internal sealed class PrintInspectorBinder
{
    private readonly PrintInspectorSurface surface;
    private bool isSynchronizing;

    internal PrintInspectorBinder(PrintInspectorSurface surface) => this.surface = surface;

    internal bool IsSynchronizing => isSynchronizing;

    /// <summary>켬/끔 두 칸입니다. macOS <c>PrintInspectorBooleanSegmentedField</c>.</summary>
    private static IReadOnlyList<SegmentOption> BooleanOptions() =>
    [
        new(false, AppResources.Get("printToggleOff", "Text")),
        new(true, AppResources.Get("printToggleOn", "Text")),
    ];

    internal void Localize()
    {
        // 레이아웃 탭
        surface.LayoutModeField.Label = AppResources.Get("printLayoutMode", "Text");
        surface.PaperSizeField.Label = AppResources.Get("printPaperSize", "Text");
        surface.OrientationField.Label = AppResources.Get("printOrientation", "Text");
        surface.RulerField.Label = AppResources.Get("printRulers", "Text");
        surface.RulerUnitField.Label = AppResources.Get("printRulerUnit", "Text");
        surface.SheetColorField.Label = AppResources.Get("printSheetBackground", "Text");
        surface.SurfaceField.Label = AppResources.Get("printSurface", "Text");
        surface.RowsField.Label = AppResources.Get("printRows", "Text");
        surface.ColumnsField.Label = AppResources.Get("printColumns", "Text");
        surface.TemplateField.Label = AppResources.Get("printTemplate", "Text");
        surface.NormalizeOrientationField.Label =
            AppResources.Get("printNormalizeOrientation", "Text");
        surface.CustomAddButton.Content = AppResources.Get("printAddCell", "Text");

        // 콘텐츠 탭
        surface.ContentFitField.Label = AppResources.Get("printContentMode", "Text");
        surface.RotateToFitField.Label = AppResources.Get("printRotateToFit", "Text");
        surface.RepeatField.Label = AppResources.Get("printRepeatOnePhoto", "Text");
        surface.CaptionField.Label = AppResources.Get("printCaption", "Text");
        surface.CaptionAlignmentField.Label = AppResources.Get("printCaptionAlignment", "Text");
        surface.CaptionFontField.Label = AppResources.Get("printCaptionFont", "Text");
        surface.ContentCropMarksField.Label = AppResources.Get("printCropMarks", "Text");
        surface.ContentSectionText.Text = AppResources.Get("printContentSection", "Text");
        surface.AddCaptionButton.Content = AppResources.Get("printAddCaption", "Text");
        // 고급 서랍 — macOS `PrintInspectorDisclosure(printAdvanced)` 안의 세 줄입니다.
        surface.AdvancedProofText.Text = AppResources.Get("printAdvanced", "Text");
        surface.DeliveryColorSpaceRow.Label = AppResources.Get("printDeliveryColorSpace", "Text");
        surface.PaperSimulationField.Label = AppResources.Get("printPaperSimulation", "Text");
        surface.GamutWarningField.Label = AppResources.Get("settingsColorGamutWarning", "Text");

        // 출력 탭
        surface.OutputSectionText.Text = AppResources.Get("printOutputSection", "Content");
        surface.OutputProcessField.Label = AppResources.Get("printOutputProcess", "Text");
        surface.CprintLabField.Label = AppResources.Get("printCprintLab", "Text");
        surface.CprintPaperField.Label = AppResources.Get("printCprintPaper", "Text");
        surface.ProofProfileField.Label = AppResources.Get("printProofProfile", "Text");
        surface.ProofPreviewField.Label = AppResources.Get("printProofPreview", "Text");

        FillPickers();
        FillSegments();
    }

    private void FillPickers()
    {
        surface.LayoutModeSelector.SetOptions(
        [
            Option(PrintLayoutMode.SingleImage, "printModeSingle"),
            Option(PrintLayoutMode.ContactSheet, "printModeContactSheet"),
            Option(PrintLayoutMode.PicturePackage, "printModePicturePackage"),
            Option(PrintLayoutMode.CustomPackage, "printModeCustomPackage"),
            Option(PrintLayoutMode.Cyanotype, "printModeCyanotype"),
            Option(PrintLayoutMode.GlassPlate, "printModeGlassPlate"),
            Option(PrintLayoutMode.Gelatin, "printModeGelatin"),
        ]);
        // macOS `paperSizeTitle` — 규격 이름은 번역하지 않지만 **사진 비율만은 번역합니다**
        // (규격이 아니라 "사진에 맞춘다"는 뜻이라서입니다). 앞 판은 "Photo" 가 그대로 나갔습니다.
        surface.PaperSizeSelector.SetOptions(
        [
            .. PrintPaper.All.Select(size => new PopupPickerOption(
                size == PrintPaperSize.PhotoRatio
                    ? AppResources.Get("printPaperPhotoRatio", "Text")
                    : PrintPaper.Label(size),
                size)),
        ]);
        surface.SurfaceSelector.SetOptions(
        [
            Option(PrintPaperSurface.Glossy, "printSurfaceGlossy"),
            Option(PrintPaperSurface.Matte, "printSurfaceMatte"),
            Option(PrintPaperSurface.Lustre, "printSurfaceLustre"),
            Option(PrintPaperSurface.Silk, "printSurfaceSilk"),
        ]);
        surface.TemplateSelector.SetOptions(
        [
            Option(PrintPicturePackageTemplate.OneLargeTwoSmall, "printTemplateOneLargeTwoSmall"),
            Option(PrintPicturePackageTemplate.TwoUp, "printTemplateTwoUp"),
            Option(PrintPicturePackageTemplate.FourUp, "printTemplateFourUp"),
        ]);
        surface.CaptionSelector.SetOptions(
        [
            Option(PrintPackageCaptionMode.None, "printCaptionNone"),
            Option(PrintPackageCaptionMode.FileName, "printCaptionFileName"),
            Option(PrintPackageCaptionMode.FrameNumber, "printCaptionFrameNumber"),
            Option(PrintPackageCaptionMode.SequenceNumber, "printCaptionSequence"),
            Option(PrintPackageCaptionMode.Rating, "printCaptionRating"),
            Option(PrintPackageCaptionMode.CustomText, "printCaptionCustomText"),
        ]);
        // 글꼴은 이 기계에 깔린 것을 그대로 씁니다(macOS 도 `availableFontFamilies`).
        // 첫 칸은 화면 기본 글꼴이며, 그 이름만 번역합니다 — 글꼴 이름 자체는 고유명사라
        // 번역하지 않습니다.
        surface.CaptionFontSelector.SetOptions(
        [
            new PopupPickerOption(AppResources.Get("printCaptionSystemFont", "Text"), string.Empty),
            .. InstalledFontFamilies().Select(name => new PopupPickerOption(name, name)),
        ]);
    }

    private void FillSegments()
    {
        surface.OrientationSelector.SetOptions(
        [
            Segment(PrintPaperOrientation.Automatic, "printOrientationAuto"),
            Segment(PrintPaperOrientation.Portrait, "printOrientationPortrait"),
            Segment(PrintPaperOrientation.Landscape, "printOrientationLandscape"),
        ], PrintPaperOrientation.Automatic);
        surface.SheetBackgroundSelector.SetOptions(
        [
            Segment(PrintSheetBackground.Black, "printBackgroundBlack"),
            Segment(PrintSheetBackground.Gray, "printBackgroundGray"),
            Segment(PrintSheetBackground.White, "printBackgroundWhite"),
        ], PrintSheetBackground.Black);
        surface.RulerUnitSelector.SetOptions(
        [
            Segment(PrintRulerUnit.Inches, "printRulerInches"),
            Segment(PrintRulerUnit.Centimeters, "printRulerCentimeters"),
        ], PrintRulerUnit.Inches);
        surface.ContentFitSelector.SetOptions(
        [
            Segment(PrintPackageContentMode.Fit, "printFit"),
            Segment(PrintPackageContentMode.Fill, "printFill"),
        ], PrintPackageContentMode.Fit);
        surface.CaptionAlignmentSelector.SetOptions(
        [
            Segment(PrintPackageCaptionAlignment.Leading, "printCaptionAlignLeading"),
            Segment(PrintPackageCaptionAlignment.Center, "printCaptionAlignCenter"),
            Segment(PrintPackageCaptionAlignment.Trailing, "printCaptionAlignTrailing"),
        ], PrintPackageCaptionAlignment.Center);
        surface.OutputProcessSelector.SetOptions(
        [
            Segment(PrintOutputProcess.Standard, "printOutputStandard"),
            Segment(PrintOutputProcess.CPrint, "printOutputCprint"),
        ], PrintOutputProcess.Standard);

        IReadOnlyList<SegmentOption> booleans = BooleanOptions();
        surface.RulerSelector.SetOptions(booleans, false);
        surface.NormalizeOrientationSelector.SetOptions(BooleanOptions(), false);
        surface.ContentCropMarksSelector.SetOptions(BooleanOptions(), false);
        surface.RotateToFitSelector.SetOptions(BooleanOptions(), false);
        surface.RepeatSelector.SetOptions(BooleanOptions(), false);
        surface.PrintProofPreviewSelector.SetOptions(BooleanOptions(), false);
        surface.PaperSimulationSelector.SetOptions(BooleanOptions(), false);
        surface.GamutWarningSelector.SetOptions(BooleanOptions(), false);
    }

    /// <summary>
    /// 이 기계에 깔린 글꼴 이름입니다. macOS <c>NSFontManager.availableFontFamilies</c>
    /// 자리입니다.
    /// </summary>
    /// <remarks>
    /// 등록된 글꼴은 <c>HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts</c> 에
    /// "Arial (TrueType)" 꼴로 들어 있습니다. 괄호 뒤 형식 표시를 떼면 글꼴 이름입니다 —
    /// 이 길이면 새 의존성 없이 실제로 깔린 것만 셀 수 있습니다.
    /// </remarks>
    private static IReadOnlyList<string> InstalledFontFamilies()
    {
        try
        {
            using Microsoft.Win32.RegistryKey? key = Microsoft.Win32.Registry.LocalMachine
                .OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts");
            if (key is null)
            {
                return [];
            }
            // "Arial Bold Italic" 같은 낱개 이름을 가족으로 되돌립니다 — macOS 는
            // `availableFontFamilies` 로 가족만 받습니다. 낱개 그대로 두면 목록이 수백 줄이
            // 되고, 팝업을 여는 순간 그 수백 줄을 지으며 화면이 멈춥니다.
            return PrintCaptionFonts.Merge(key.GetValueNames());
        }
        catch (Exception error) when (error is System.Security.SecurityException or
            UnauthorizedAccessException or IOException or ObjectDisposedException)
        {
            return [];
        }
    }

    private static PopupPickerOption Option<T>(T value, string key)
        where T : notnull =>
        new(AppResources.Get(key, "Text"), value);

    private static SegmentOption Segment<T>(T value, string key)
        where T : notnull =>
        new(value, AppResources.Get(key, "Text"));

    /// <summary>고른 값을 설정에 담습니다. 담긴 값이 곧 미리보기와 파일을 정합니다.</summary>
    internal void Commit(WorkspacePresentationState state)
    {
        if (isSynchronizing)
        {
            return;
        }
        state.UpdatePrint(current => current with
        {
            LayoutMode = Picked(surface.LayoutModeSelector, current.LayoutMode),
            PaperSize = Picked(surface.PaperSizeSelector, current.PaperSize),
            Orientation = Chosen(surface.OrientationSelector, current.Orientation),
            PaperSurface = Picked(surface.SurfaceSelector, current.PaperSurface),
            MarginMm = surface.MarginSlider.Value,
            ContactRows = (int)Math.Round(
                double.IsNaN(surface.RowsBox.Value) ? current.ContactRows : surface.RowsBox.Value),
            ContactColumns = (int)Math.Round(
                double.IsNaN(surface.ColumnsBox.Value) ? current.ContactColumns : surface.ColumnsBox.Value),
            HorizontalSpacingMm = surface.SpacingSlider.Value,
            ContentMode = Chosen(surface.ContentFitSelector, current.ContentMode),
            RotateToFit = Chosen(surface.RotateToFitSelector, current.RotateToFit),
            RepeatOnePhotoPerPage = Chosen(surface.RepeatSelector, current.RepeatOnePhotoPerPage),
            SheetBackground = Chosen(surface.SheetBackgroundSelector, current.SheetBackground),
            PictureTemplate = Picked(surface.TemplateSelector, current.PictureTemplate),
            CaptionMode = Picked(surface.CaptionSelector, current.CaptionMode),
            CaptionAlignment = Chosen(surface.CaptionAlignmentSelector, current.CaptionAlignment),
            ShowsCropMarks = Chosen(surface.ContentCropMarksSelector, current.ShowsCropMarks),
            NormalizesSourceOrientation = Chosen(
                surface.NormalizeOrientationSelector, current.NormalizesSourceOrientation),
            CaptionFontName = surface.CaptionFontSelector.SelectedTag as string ?? current.CaptionFontName,
            VerticalSpacingMm = surface.VerticalSpacingSlider.Value,
            ShowsRulers = Chosen(surface.RulerSelector, current.ShowsRulers),
            RulerUnit = Chosen(surface.RulerUnitSelector, current.RulerUnit),
            OutputProcess = Chosen(surface.OutputProcessSelector, current.OutputProcess),
            CPrintLabName = surface.CprintLabBox.Text,
            CPrintPaperName = surface.CprintPaperBox.Text,
            CPrintPreviewEnabled = Chosen(surface.PrintProofPreviewSelector, current.CPrintPreviewEnabled),
            CPrintPaperSimulationEnabled =
                Chosen(surface.PaperSimulationSelector, current.CPrintPaperSimulationEnabled),
        });
    }

    private static T Picked<T>(NegaflowPopupPicker picker, T fallback) =>
        picker.SelectedTag is T value ? value : fallback;

    private static T Chosen<T>(NegaflowSegmentedPicker picker, T fallback) =>
        picker.SelectedValue is T value ? value : fallback;

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
            surface.LayoutModeSelector.SelectByTag(print.LayoutMode);
            surface.PaperSizeSelector.SelectByTag(print.PaperSize);
            surface.SurfaceSelector.SelectByTag(print.PaperSurface);
            surface.TemplateSelector.SelectByTag(print.PictureTemplate);
            surface.CaptionSelector.SelectByTag(print.CaptionMode);
            surface.OrientationSelector.SetSelected(print.Orientation);
            surface.SheetBackgroundSelector.SetSelected(print.SheetBackground);
            surface.RulerSelector.SetSelected(print.ShowsRulers);
            surface.RulerUnitSelector.SetSelected(print.RulerUnit);
            surface.ContentFitSelector.SetSelected(print.ContentMode);
            surface.RotateToFitSelector.SetSelected(print.RotateToFit);
            surface.RepeatSelector.SetSelected(print.RepeatOnePhotoPerPage);
            surface.ContentCropMarksSelector.SetSelected(print.ShowsCropMarks);
            surface.NormalizeOrientationSelector.SetSelected(print.NormalizesSourceOrientation);
            surface.CaptionFontSelector.SelectByTag(print.CaptionFontName);
            surface.VerticalSpacingSlider.Value = print.VerticalSpacingMm;
            surface.CaptionAlignmentSelector.SetSelected(print.CaptionAlignment);
            surface.OutputProcessSelector.SetSelected(print.OutputProcess);
            surface.PrintProofPreviewSelector.SetSelected(print.CPrintPreviewEnabled);
            surface.PaperSimulationSelector.SetSelected(print.CPrintPaperSimulationEnabled);
            surface.MarginSlider.Value = print.MarginMm;
            surface.RowsBox.Value = print.ContactRows;
            surface.ColumnsBox.Value = print.ContactColumns;
            surface.SpacingSlider.Value = print.HorizontalSpacingMm;
            surface.CprintLabBox.Text = print.CPrintLabName;
            surface.CprintPaperBox.Text = print.CPrintPaperName;
        }
        finally
        {
            isSynchronizing = false;
        }

        surface.MarginText.Text = AppResources.Get("printMargin", "Text");
        surface.MarginValueText.Text = Millimetres(print.MarginMm);
        surface.SpacingText.Text = AppResources.Get("printHorizontalSpacing", "Text");
        surface.SpacingValueText.Text = Millimetres(print.HorizontalSpacingMm);

        // macOS 는 눈금자를 켰을 때만 단위 줄을 냅니다 — 끄면 자리 자체가 없습니다.
        surface.RulerUnitField.Visibility = Visible(print.ShowsRulers);

        bool package = PrintPreferences.PackageModeFor(print.LayoutMode) is not null;
        surface.PackageLayoutCard.Visibility = Visible(package);
        // 행·열은 콘택트 시트만 직접 정합니다. 사진 패키지는 판형이, 사용자 패키지는
        // 캔버스에서 끄는 칸이 배치를 정합니다.
        surface.GridSizeRow.Visibility = Visible(print.LayoutMode == PrintLayoutMode.ContactSheet);
        surface.TemplateField.Visibility = Visible(print.LayoutMode == PrintLayoutMode.PicturePackage);
        surface.CustomPanel.Visibility = Visible(print.LayoutMode == PrintLayoutMode.CustomPackage);
        surface.PackageLayoutTitle.Text = AppResources.Get(
            print.LayoutMode switch
            {
                PrintLayoutMode.ContactSheet => "printModeContactSheet",
                PrintLayoutMode.PicturePackage => "printModePicturePackage",
                _ => "printModeCustomPackage",
            },
            "Text");

        // 사용자 패키지는 칸마다 크기를 직접 정하므로 맞춤·회전이 없습니다.
        surface.ContentFitGroup.Visibility =
            Visible(package && print.LayoutMode != PrintLayoutMode.CustomPackage);
        // 반복은 콘택트 시트만 씁니다(macOS `contactSheetControls`).
        surface.RepeatField.Visibility = Visible(print.LayoutMode == PrintLayoutMode.ContactSheet);
        // 사용자 패키지는 칸 자리를 직접 정하므로 간격이 없습니다.
        surface.SpacingGroup.Visibility =
            Visible(package && print.LayoutMode != PrintLayoutMode.CustomPackage);
        surface.VerticalSpacingText.Text = AppResources.Get("printVerticalSpacing", "Text");
        surface.VerticalSpacingValueText.Text = Millimetres(print.VerticalSpacingMm);

        // 캡션을 끄면 글꼴도 정렬도 고를 것이 없습니다(macOS `if captionMode != .none`).
        bool hasCaption = print.CaptionMode != PrintPackageCaptionMode.None;
        surface.CaptionDetailGroup.Visibility = Visible(hasCaption);
        bool customText = print.CaptionMode == PrintPackageCaptionMode.CustomText;
        surface.CustomCaptionGroup.Visibility = Visible(customText);
        surface.CaptionAlignmentGroup.Visibility = Visible(!customText);
        surface.AddCaptionButton.IsEnabled =
            print.CustomCaptions.Count < PrintPackageSettings.MaximumCustomCaptionCount;
        surface.CustomAddButton.IsEnabled =
            print.CustomItems.Count < PrintPackageSettings.MaximumCustomItemCount;
    }

    private static string Millimetres(double value) => string.Create(
        System.Globalization.CultureInfo.CurrentCulture,
        $"{Math.Round(value):0} mm");

    private static Visibility Visible(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;
}
