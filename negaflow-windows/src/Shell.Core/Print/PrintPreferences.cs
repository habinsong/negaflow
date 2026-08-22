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

    public PrintPaperSurface PaperSurface { get; init; } = PrintPaperSurface.Matte;

    public bool ShowsRulers { get; init; }

    public PrintRulerUnit RulerUnit { get; init; } = PrintRulerUnit.Inches;

    /// <summary>
    /// 일반 출력인지 C-print 인지입니다.
    ///
    /// macOS 는 이 값을 **기억하지 않습니다**(`PrintWorkspaceSettingsStore` 주석 원문:
    /// "C-Print 는 랩에 넘길 때만 켜는 특수 경로인데, 한 번 켠 뒤 다음 실행에서도 켜져
    /// 있으면 일반 출력인 줄 알고 프루프가 걸린 결과를 받게 된다"). 불러올 때 항상
    /// <see cref="PrintOutputProcess.Standard"/> 로 되돌립니다 — <see cref="Restored"/>.
    /// </summary>
    public PrintOutputProcess OutputProcess { get; init; } = PrintOutputProcess.Standard;

    /// <summary>C-print 를 맡길 인화소입니다. macOS <c>cPrintLabName</c>.</summary>
    public string CPrintLabName { get; init; } = string.Empty;

    /// <summary>C-print 인화지입니다. macOS <c>cPrintPaperName</c>.</summary>
    public string CPrintPaperName { get; init; } = string.Empty;

    /// <summary>인화소가 준 ICC 프로파일의 자리입니다. macOS <c>cPrintProofICCProfileData</c>.</summary>
    public string CPrintProofProfilePath { get; init; } = string.Empty;

    /// <summary>그 프로파일의 이름입니다. 화면에 그대로 보입니다.</summary>
    public string CPrintProofProfileName { get; init; } = string.Empty;

    /// <summary>인화 미리보기(소프트 프루프)를 켤지입니다. macOS <c>cPrintPreviewEnabled</c>.</summary>
    public bool CPrintPreviewEnabled { get; init; }

    /// <summary>
    /// 용지 흰색과 잉크 검정까지 흉내 낼지입니다. macOS
    /// <c>cPrintPaperSimulationEnabled</c> 이며, 켜면 프루프가
    /// <see cref="Develop.SoftProofSimulation.PaperAndInk"/> 로 갑니다.
    /// </summary>
    public bool CPrintPaperSimulationEnabled { get; init; }

    public PrintSheetBackground SheetBackground { get; init; } = PrintSheetBackground.White;

    public int ContactRows { get; init; } = 7;

    public int ContactColumns { get; init; } = 6;

    public double HorizontalSpacingMm { get; init; } = 2;

    public double VerticalSpacingMm { get; init; } = 2;

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    public bool RotateToFit { get; init; }

    public bool RepeatOnePhotoPerPage { get; init; }

    public PrintPicturePackageTemplate PictureTemplate { get; init; } =
        PrintPicturePackageTemplate.OneLargeTwoSmall;

    public PrintPackageCaptionMode CaptionMode { get; init; } = PrintPackageCaptionMode.None;

    public PrintPackageCaptionAlignment CaptionAlignment { get; init; } =
        PrintPackageCaptionAlignment.Leading;

    public double CaptionHeightMm { get; init; } = 6;

    /// <summary>
    /// 판에 올린 사진을 스캔 기본 방향으로 통일합니다. macOS
    /// <c>normalizesSourceOrientation</c> 자리입니다.
    /// </summary>
    public bool NormalizesSourceOrientation { get; init; }

    /// <summary>캡션 글꼴입니다. 빈 값이면 화면 기본 글꼴입니다.</summary>
    public string CaptionFontName { get; init; } = PrintCaptionFonts.DefaultName;

    /// <summary>손으로 놓은 문구들입니다. 캡션이 "사용자 문구" 일 때만 씁니다.</summary>
    public IReadOnlyList<PrintCustomCaption> CustomCaptions { get; init; } = PrintCustomCaption.DefaultSet;

    public bool ShowsCropMarks { get; init; }

    public double CropMarkLengthMm { get; init; } = 3;

    /// <summary>손으로 놓은 배치입니다. 커스텀 패키지 모드에서만 쓰입니다.</summary>
    public IReadOnlyList<PrintCustomPackageItem> CustomItems { get; init; } = PrintCustomPackageSeed.Default;

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
        CustomItems = CustomItems,
        NormalizesSourceOrientation = NormalizesSourceOrientation,
        CaptionFontName = CaptionFontName,
        CustomCaptions = CustomCaptions,
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
    /// <summary>
    /// 디스크에서 읽어 온 값에 적용합니다. macOS 처럼 **출력 방식만 되돌립니다** — 나머지는
    /// 그대로 기억합니다.
    /// </summary>
    public PrintPreferences Restored() =>
        Normalize() with
        {
            OutputProcess = PrintOutputProcess.Standard,
            // 퍼포레이션은 macOS 인화 인스펙터가 <b>내주지 않는</b> 값이라 늘 없음입니다.
            // 예전 Windows 판에는 이것을 고르는 칸이 있었고, 그때 켜 둔 값이 그대로 남아
            // 있으면 이제는 끌 방법 없이 판에 구멍이 계속 찍힙니다.
            PerforationStyle = PrintPerforationStyle.None,
        };

    public PrintPreferences Normalize() => this with
    {
        CPrintLabName = (CPrintLabName ?? string.Empty).Trim(),
        CPrintPaperName = (CPrintPaperName ?? string.Empty).Trim(),
        CPrintProofProfilePath = (CPrintProofProfilePath ?? string.Empty).Trim(),
        CPrintProofProfileName = (CPrintProofProfileName ?? string.Empty).Trim(),
        // 프로파일이 없으면 미리보기도 의미가 없습니다.
        CPrintPreviewEnabled = CPrintPreviewEnabled &&
            !string.IsNullOrWhiteSpace(CPrintProofProfilePath),
        LayoutMode = Enum.IsDefined(LayoutMode) ? LayoutMode : PrintLayoutMode.SingleImage,
        PaperSize = Enum.IsDefined(PaperSize) ? PaperSize : PrintPaperSize.A4,
        Orientation = Enum.IsDefined(Orientation) ? Orientation : PrintPaperOrientation.Automatic,
        MarginMm = double.IsFinite(MarginMm) ? Math.Clamp(MarginMm, 0, 50) : 10,
        Dpi = Math.Clamp(Dpi, 72, 600),
        // 퍼포레이션(필름 띠 + 천공)은 **어느 화면에서도 고를 수 없습니다** — macOS 인화
        // 인스펙터에 그 자리가 없고, Windows 에만 있던 창작이라 걷어냈습니다
        // (`PrintInspectorSurface`). 그런데 걷어내기 전에 저장된 설정 파일에는 값이 남아
        // 있어, 끌 방법 없이 판마다 필름 띠와 천공이 그려졌습니다(사용자 신고). 읽을 때
        // 되돌립니다 — macOS 가 실제로 내는 값과 같습니다.
        PerforationStyle = PrintPerforationStyle.None,
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
        // 손으로 고친 파일이 판 밖의 칸을 담고 있으면 배치가 통째로 거절됩니다. 그런 칸만
        // 버리고 나머지는 살립니다 — 배치 하나 때문에 화면이 비지 않게.
        CustomItems = [.. (CustomItems ?? []).Where(item => item.IsValid)],
    };
}
