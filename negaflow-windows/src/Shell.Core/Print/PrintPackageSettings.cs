namespace Negaflow.Shell.Print;

public enum PrintPackageContentMode
{
    Fit,
    Fill,
}

/// <summary>픽처 패키지의 칸 배치입니다. macOS <c>PrintPicturePackageTemplate</c> 과 같습니다.</summary>
public enum PrintPicturePackageTemplate
{
    OneLargeTwoSmall,
    TwoUp,
    FourUp,
}

/// <summary>칸 아래에 무엇을 적을지입니다. macOS <c>PrintPackageCaptionMode</c> 와 같습니다.</summary>
public enum PrintPackageCaptionMode
{
    None,
    FileName,
    FrameNumber,
    SequenceNumber,
    Rating,

    /// <summary>사용자가 적은 문구를 판 위 원하는 자리에 놓습니다.</summary>
    CustomText,
}

public enum PrintPackageCaptionAlignment
{
    Leading,
    Center,
    Trailing,
}

/// <summary>
/// 판 위에 손으로 놓은 문구 하나입니다. macOS <c>PrintPackageCustomCaption</c> 과 같습니다.
/// </summary>
/// <remarks>자리는 칸과 마찬가지로 내용 영역에 대한 0~1 비율입니다.</remarks>
public sealed record PrintCustomCaption(string Text, PrintRect NormalizedRect)
{
    public PrintPackageCaptionAlignment Alignment { get; init; } =
        PrintPackageCaptionAlignment.Leading;

    public bool IsValid =>
        NormalizedRect.Width > 0 &&
        NormalizedRect.Height > 0 &&
        NormalizedRect.X >= 0 &&
        NormalizedRect.Y >= 0 &&
        NormalizedRect.X + NormalizedRect.Width <= 1.000_001 &&
        NormalizedRect.Y + NormalizedRect.Height <= 1.000_001;

    /// <summary>
    /// 처음 문구 하나입니다. macOS 기본값 <c>(0.05, 0.02, 0.9, 0.05)</c> 가운데 맞춤이며,
    /// macOS 는 아래가 0 인 좌표라 같은 자리가 여기서는 <c>y = 1 - 0.02 - 0.05</c> 입니다.
    /// </summary>
    public static IReadOnlyList<PrintCustomCaption> DefaultSet { get; } =
    [
        new(string.Empty, new PrintRect(0.05, 1 - 0.02 - 0.05, 0.9, 0.05))
        {
            Alignment = PrintPackageCaptionAlignment.Center,
        },
    ];

    /// <summary>
    /// 새로 더할 때의 자리입니다. macOS <c>addCustomCaption()</c> 과 같습니다 — 이미 있는
    /// 문구 수만큼 조금씩 어긋나게 놓아 서로 가리지 않습니다.
    /// </summary>
    public static PrintCustomCaption Default(string text, int existingCount = 0)
    {
        double offset = (existingCount % 8) * 0.04;
        double bottomUpY = Math.Min(0.85, 0.02 + offset);
        return new PrintCustomCaption(
            text,
            new PrintRect(Math.Min(0.55, 0.05 + offset), 1 - bottomUpY - 0.05, 0.4, 0.05));
    }
}

/// <summary>
/// 사용자가 손으로 놓은 칸 하나입니다. macOS <c>PrintCustomPackageItem</c> 과 같습니다.
/// </summary>
/// <remarks>
/// 자리는 <b>내용 영역에 대한 0…1 비율</b>입니다. 화소로 담으면 용지나 해상도를 바꾼 순간
/// 배치가 통째로 어긋납니다.
/// </remarks>
public sealed record PrintCustomPackageItem(
    int SourceIndex,
    PrintRect NormalizedRect)
{
    public int PageIndex { get; init; }

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    public bool RotateToFit { get; init; }

    /// <summary>겹칠 때 위로 오는 차례입니다. 같으면 목록 차례를 따릅니다.</summary>
    public int ZIndex { get; init; }

    /// <summary>판 밖으로 나가거나 넓이가 없는 칸은 놓지 않습니다.</summary>
    public bool IsValid =>
        SourceIndex >= 0 &&
        PageIndex >= 0 &&
        double.IsFinite(NormalizedRect.X) && double.IsFinite(NormalizedRect.Y) &&
        double.IsFinite(NormalizedRect.Width) && double.IsFinite(NormalizedRect.Height) &&
        NormalizedRect.Width > 0 && NormalizedRect.Height > 0 &&
        NormalizedRect.X >= 0 && NormalizedRect.Y >= 0 &&
        NormalizedRect.MaxX <= 1.0001 && NormalizedRect.MaxY <= 1.0001;
}

/// <summary>크롭마크 선분 하나입니다.</summary>
public readonly record struct PrintLineSegment(
    double StartX,
    double StartY,
    double EndX,
    double EndY);

/// <summary>여러 장을 한 판에 놓는 방식입니다. macOS <c>PrintPackageLayoutMode</c> 와 같습니다.</summary>
public enum PrintPackageMode
{
    ContactSheet,
    PicturePackage,
    CustomPackage,
}

/// <summary>
/// 인화 판을 채우는 값입니다. macOS <c>PrintPackageSettings</c> 중 Windows 가 지금 내는 것들입니다.
/// </summary>
public sealed record PrintPackageSettings
{
    public const int MaximumPageCount = 32;

    /// <summary>한 판에 놓을 수 있는 칸 수의 한계입니다. 넘으면 칸이 화소보다 작아집니다.</summary>
    public const int MaximumCells = 400;

    public PrintPackageMode Mode { get; init; } = PrintPackageMode.ContactSheet;

    public int ContactRows { get; init; } = 7;

    public int ContactColumns { get; init; } = 6;

    public double HorizontalSpacingMm { get; init; } = 2;

    public double VerticalSpacingMm { get; init; } = 2;

    public PrintPackageContentMode ContentMode { get; init; } = PrintPackageContentMode.Fit;

    /// <summary>칸에 더 잘 맞으면 90도 돌려 놓습니다. 프레임 자체는 건드리지 않습니다.</summary>
    public bool RotateToFit { get; init; }

    /// <summary>한 판에 한 사진을 가득 반복합니다 — 증명사진처럼 같은 컷을 여러 장 뽑을 때입니다.</summary>
    public bool RepeatOnePhotoPerPage { get; init; }

    public PrintSheetBackground SheetBackground { get; init; } = PrintSheetBackground.White;

    public PrintPicturePackageTemplate PictureTemplate { get; init; } =
        PrintPicturePackageTemplate.OneLargeTwoSmall;

    public PrintPackageCaptionMode CaptionMode { get; init; } = PrintPackageCaptionMode.None;

    public PrintPackageCaptionAlignment CaptionAlignment { get; init; } =
        PrintPackageCaptionAlignment.Leading;

    /// <summary>캡션이 차지하는 높이입니다. 사진은 그만큼 위로 물러납니다.</summary>
    public double CaptionHeightMm { get; init; } = 6;

    /// <summary>
    /// 판에 올린 사진을 스캔 기본 방향으로 통일해 놓습니다. macOS
    /// <c>normalizesSourceOrientation</c> 이며, 프레임 자체의 방향은 그대로 둡니다.
    /// </summary>
    public bool NormalizesSourceOrientation { get; init; }

    /// <summary>캡션 글꼴입니다. 빈 값이면 화면 기본 글꼴을 씁니다.</summary>
    public string CaptionFontName { get; init; } = PrintCaptionFonts.DefaultName;

    /// <summary>손으로 놓은 문구들입니다. 캡션 방식이 "사용자 문구" 일 때만 씁니다.</summary>
    public IReadOnlyList<PrintCustomCaption> CustomCaptions { get; init; } = PrintCustomCaption.DefaultSet;

    /// <summary>손으로 놓을 수 있는 문구 수의 한계입니다.</summary>
    public const int MaximumCustomCaptionCount = 32;

    /// <summary>손으로 놓을 수 있는 칸 수의 한계입니다.</summary>
    public const int MaximumCustomItemCount = 128;

    public bool ShowsCropMarks { get; init; }

    public double CropMarkLengthMm { get; init; } = 3;

    /// <summary>커스텀 배치의 칸들입니다. 그 모드가 아니면 쓰이지 않습니다.</summary>
    public IReadOnlyList<PrintCustomPackageItem> CustomItems { get; init; } = PrintCustomPackageSeed.Default;

    public bool IsValid =>
        ContactRows > 0 && ContactColumns > 0 &&
        ContactRows * ContactColumns <= MaximumCells &&
        double.IsFinite(HorizontalSpacingMm) && HorizontalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(VerticalSpacingMm) && VerticalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(CaptionHeightMm) && CaptionHeightMm is >= 0 and <= 40 &&
        double.IsFinite(CropMarkLengthMm) && CropMarkLengthMm is >= 0 and <= 30 &&
        CustomItems.Count <= MaximumCustomItemCount;
}

/// <summary>판 위의 사진 한 칸입니다.</summary>
public sealed record PrintPackageItemLayout(
    int SourceIndex,
    PrintRect CellRect,
    PrintRect ImageRect,
    int QuarterTurns)
{
    /// <summary>캡션이 놓이는 자리입니다. 캡션이 없으면 null 입니다.</summary>
    public PrintRect? CaptionRect { get; init; }
}

/// <summary>판 한 장입니다.</summary>
public sealed record PrintPackagePageLayout(
    int PageIndex,
    PrintSizeMm CanvasSize,
    PrintRect ContentRect,
    IReadOnlyList<PrintPackageItemLayout> Items)
{
    /// <summary>재단선입니다. 켜지 않았으면 빕니다.</summary>
    public IReadOnlyList<PrintLineSegment> CropMarks { get; init; } = [];

    /// <summary>
    /// 손으로 놓은 문구들입니다. macOS <c>PrintPackagePageLayout.textItems</c> 와 같습니다 —
    /// 캡션 방식이 "사용자 문구" 일 때만 채워집니다.
    /// </summary>
    public IReadOnlyList<PrintPackageTextLayout> TextItems { get; init; } = [];
}

/// <summary>
/// 판 위에 놓인 문구 하나입니다. macOS <c>PrintPackageTextLayout</c> 과 같습니다.
/// </summary>
/// <remarks>
/// 자리는 <b>용지 전체</b>에 대한 값입니다(macOS <c>rect.minX * page.canvasSize.width</c>).
/// 칸은 여백을 뺀 내용 영역을 기준으로 하는 것과 다릅니다.
/// </remarks>
public sealed record PrintPackageTextLayout(
    string Text,
    PrintRect Rect,
    PrintPackageCaptionAlignment Alignment);
