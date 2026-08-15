namespace Negaflow.Shell.Print;

/// <summary>
/// 인화 화면이 기억하는 값입니다. macOS <c>PrintWorkspaceSettingsStore</c> 와 같은 항목이며,
/// 그쪽은 UserDefaults 에, 여기서는 셸 설정 파일에 삽니다.
/// </summary>
public sealed record PrintPreferences
{
    public PrintLayoutMode LayoutMode { get; init; } = PrintLayoutMode.SingleImage;

    public PrintPaperSize PaperSize { get; init; } = PrintPaperSize.A4;

    public PrintPaperOrientation Orientation { get; init; } = PrintPaperOrientation.Automatic;

    public double MarginMm { get; init; } = 10;

    public int Dpi { get; init; } = 300;

    public PrintPerforationStyle PerforationStyle { get; init; } = PrintPerforationStyle.None;

    public PrintPaperSurface PaperSurface { get; init; } = PrintPaperSurface.Glossy;

    public bool ShowsRulers { get; init; }

    public PrintRulerUnit RulerUnit { get; init; } = PrintRulerUnit.Centimeters;

    public PrintOutputProcess OutputProcess { get; init; } = PrintOutputProcess.Standard;

    public PrintSheetBackground SheetBackground { get; init; } = PrintSheetBackground.White;

    public int ContactRows { get; init; } = 7;

    public int ContactColumns { get; init; } = 6;

    public double HorizontalSpacingMm { get; init; } = 4;

    public double VerticalSpacingMm { get; init; } = 4;

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    public bool RotateToFit { get; init; }

    public bool RepeatOnePhotoPerPage { get; init; }

    public PrintPicturePackageTemplate PictureTemplate { get; init; } =
        PrintPicturePackageTemplate.OneLargeTwoSmall;

    public PrintPackageCaptionMode CaptionMode { get; init; } = PrintPackageCaptionMode.None;

    public PrintPackageCaptionAlignment CaptionAlignment { get; init; } =
        PrintPackageCaptionAlignment.Center;

    public double CaptionHeightMm { get; init; } = 6;

    public bool ShowsCropMarks { get; init; }

    public double CropMarkLengthMm { get; init; } = 4;

    /// <summary>
    /// 이 값들로 만든 판 설정입니다. 레이아웃 모드가 공정을 고르면 그 겉모습이 함께 갑니다 —
    /// macOS <c>presentationStyle</c> 과 같은 대응입니다.
    /// </summary>
    public PrintCompositionSettings Composition(double? photoAspectRatio = null) => new()
    {
        PaperSize = PaperSize,
        Orientation = Orientation,
        MarginMm = MarginMm,
        Dpi = Dpi,
        PerforationStyle = PerforationStyle,
        PhotoAspectRatio = photoAspectRatio,
        PresentationStyle = PresentationStyleFor(LayoutMode),
        SheetBackground = SheetBackground,
    };

    public PrintPackageSettings Package() => new()
    {
        Mode = PackageModeFor(LayoutMode) ?? PrintPackageMode.ContactSheet,
        ContactRows = ContactRows,
        ContactColumns = ContactColumns,
        HorizontalSpacingMm = HorizontalSpacingMm,
        VerticalSpacingMm = VerticalSpacingMm,
        ContentMode = ContentMode,
        RotateToFit = RotateToFit,
        RepeatOnePhotoPerPage = RepeatOnePhotoPerPage,
        SheetBackground = SheetBackground,
        PictureTemplate = PictureTemplate,
        CaptionMode = CaptionMode,
        CaptionAlignment = CaptionAlignment,
        CaptionHeightMm = CaptionHeightMm,
        ShowsCropMarks = ShowsCropMarks,
        CropMarkLengthMm = CropMarkLengthMm,
    };

    /// <summary>
    /// 여러 장을 한 판에 놓는 모드인지. 아니면 사진마다 한 장씩입니다 — macOS
    /// <c>packageMode</c> 와 같습니다.
    /// </summary>
    public static PrintPackageMode? PackageModeFor(PrintLayoutMode mode) => mode switch
    {
        PrintLayoutMode.ContactSheet => PrintPackageMode.ContactSheet,
        PrintLayoutMode.PicturePackage => PrintPackageMode.PicturePackage,
        PrintLayoutMode.CustomPackage => PrintPackageMode.CustomPackage,
        _ => null,
    };

    public static PrintPresentationStyle PresentationStyleFor(PrintLayoutMode mode) => mode switch
    {
        PrintLayoutMode.Cyanotype => PrintPresentationStyle.Cyanotype,
        PrintLayoutMode.GlassPlate => PrintPresentationStyle.GlassPlate,
        PrintLayoutMode.Gelatin => PrintPresentationStyle.GelatinSilver,
        _ => PrintPresentationStyle.Standard,
    };

    /// <summary>
    /// 설정 파일에서 읽은 값이 범위를 벗어났으면 되돌립니다. 손으로 고친 파일이 여백 900mm 를
    /// 담고 있으면 판 계산이 통째로 실패해 화면이 빕니다.
    /// </summary>
    public PrintPreferences Normalize() => this with
    {
        LayoutMode = Enum.IsDefined(LayoutMode) ? LayoutMode : PrintLayoutMode.SingleImage,
        PaperSize = Enum.IsDefined(PaperSize) ? PaperSize : PrintPaperSize.A4,
        Orientation = Enum.IsDefined(Orientation) ? Orientation : PrintPaperOrientation.Automatic,
        MarginMm = double.IsFinite(MarginMm) ? Math.Clamp(MarginMm, 0, 50) : 10,
        Dpi = Math.Clamp(Dpi, 72, 600),
        PerforationStyle = Enum.IsDefined(PerforationStyle)
            ? PerforationStyle
            : PrintPerforationStyle.None,
        PaperSurface = Enum.IsDefined(PaperSurface) ? PaperSurface : PrintPaperSurface.Glossy,
        RulerUnit = Enum.IsDefined(RulerUnit) ? RulerUnit : PrintRulerUnit.Centimeters,
        OutputProcess = Enum.IsDefined(OutputProcess) ? OutputProcess : PrintOutputProcess.Standard,
        SheetBackground = Enum.IsDefined(SheetBackground)
            ? SheetBackground
            : PrintSheetBackground.White,
        ContactRows = Math.Clamp(ContactRows, 1, 20),
        ContactColumns = Math.Clamp(ContactColumns, 1, 20),
        HorizontalSpacingMm = double.IsFinite(HorizontalSpacingMm)
            ? Math.Clamp(HorizontalSpacingMm, 0, 50)
            : 4,
        VerticalSpacingMm = double.IsFinite(VerticalSpacingMm)
            ? Math.Clamp(VerticalSpacingMm, 0, 50)
            : 4,
        ContentMode = Enum.IsDefined(ContentMode) ? ContentMode : PrintPackageContentMode.Fit,
        PictureTemplate = Enum.IsDefined(PictureTemplate)
            ? PictureTemplate
            : PrintPicturePackageTemplate.OneLargeTwoSmall,
        CaptionMode = Enum.IsDefined(CaptionMode) ? CaptionMode : PrintPackageCaptionMode.None,
        CaptionAlignment = Enum.IsDefined(CaptionAlignment)
            ? CaptionAlignment
            : PrintPackageCaptionAlignment.Center,
        CaptionHeightMm = double.IsFinite(CaptionHeightMm)
            ? Math.Clamp(CaptionHeightMm, 0, 40)
            : 6,
        CropMarkLengthMm = double.IsFinite(CropMarkLengthMm)
            ? Math.Clamp(CropMarkLengthMm, 0, 30)
            : 4,
    };
}
