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
}

public enum PrintPackageCaptionAlignment
{
    Leading,
    Center,
    Trailing,
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

    public double HorizontalSpacingMm { get; init; } = 4;

    public double VerticalSpacingMm { get; init; } = 4;

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
        PrintPackageCaptionAlignment.Center;

    /// <summary>캡션이 차지하는 높이입니다. 사진은 그만큼 위로 물러납니다.</summary>
    public double CaptionHeightMm { get; init; } = 6;

    public bool ShowsCropMarks { get; init; }

    public double CropMarkLengthMm { get; init; } = 4;

    /// <summary>커스텀 배치의 칸들입니다. 그 모드가 아니면 쓰이지 않습니다.</summary>
    public IReadOnlyList<PrintCustomPackageItem> CustomItems { get; init; } = [];

    /// <summary>손으로 놓을 수 있는 칸 수의 한계입니다. macOS 와 같은 128 입니다.</summary>
    public const int MaximumCustomItems = 128;

    public bool IsValid =>
        ContactRows > 0 && ContactColumns > 0 &&
        ContactRows * ContactColumns <= MaximumCells &&
        double.IsFinite(HorizontalSpacingMm) && HorizontalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(VerticalSpacingMm) && VerticalSpacingMm is >= 0 and <= 50 &&
        double.IsFinite(CaptionHeightMm) && CaptionHeightMm is >= 0 and <= 40 &&
        double.IsFinite(CropMarkLengthMm) && CropMarkLengthMm is >= 0 and <= 30 &&
        CustomItems.Count <= MaximumCustomItems;
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
}
