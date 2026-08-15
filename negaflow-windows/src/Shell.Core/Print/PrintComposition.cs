namespace Negaflow.Shell.Print;

/// <summary>용지입니다. macOS <c>PrintPaperSize</c> 와 같은 스물여섯 가지, 같은 차례입니다.</summary>
public enum PrintPaperSize
{
    PhotoRatio,
    ThreePointFiveByFive,
    FourBySix,
    FiveBySeven,
    EightByTen,
    TenByTwelve,
    ElevenByFourteen,
    TwelveByEighteen,
    SixteenByTwenty,
    TwentyByTwentyFour,
    TwentyByThirty,
    TwentyFourByThirtySix,
    Letter,
    Tabloid,
    A3Plus,
    A6,
    A5,
    A4,
    A3,
    A2,
    A1,
    B6,
    B5,
    B4,
    B3,
    B2,
    B1,
}

public enum PrintPaperOrientation
{
    Automatic,
    Portrait,
    Landscape,
}

public enum PrintPerforationStyle
{
    None,
    ThirtyFiveMillimeter,
}

/// <summary>
/// 인화 공정의 겉모습입니다. 측정 프로파일을 대신하는 장치 정확도 시뮬레이션이 아니라, 공정의
/// 핵심 시각 특성만 화면과 파일에 <b>같게</b> 적용합니다 — macOS 와 같은 뜻입니다.
/// </summary>
public enum PrintPresentationStyle
{
    Standard,
    Cyanotype,
    GlassPlate,
    GelatinSilver,
}

public enum PrintSheetBackground
{
    Black,
    Gray,
    White,
}

public enum PrintLayoutMode
{
    SingleImage,
    ContactSheet,
    PicturePackage,
    CustomPackage,
    Cyanotype,
    GlassPlate,
    Gelatin,
}

public enum PrintPaperSurface
{
    Glossy,
    Matte,
    Lustre,
    Silk,
}

public enum PrintRulerUnit
{
    Inches,
    Centimeters,
}

public enum PrintOutputProcess
{
    Standard,
    CPrint,
}

public readonly record struct PrintSizeMm(double Width, double Height);

public readonly record struct PrintRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;

    public double MinY => Y;

    public double MaxX => X + Width;

    public double MaxY => Y + Height;

    public double MidX => X + (Width / 2);

    public double MidY => Y + (Height / 2);

    /// <summary>안쪽으로 물러난 사각형입니다. 남는 것이 없으면 폭·높이가 음수가 됩니다.</summary>
    public PrintRect Inset(double amount) =>
        new(X + amount, Y + amount, Width - (amount * 2), Height - (amount * 2));
}

public static class PrintPaper
{
    /// <summary>사진 비율 용지의 긴 변입니다. macOS 와 같은 254mm 입니다.</summary>
    public const double PhotoRatioLongEdgeMm = 254;

    public static IReadOnlyList<PrintPaperSize> All { get; } =
        [.. Enum.GetValues<PrintPaperSize>()];

    /// <summary>mm 치수입니다. macOS <c>dimensionsMM</c> 과 <b>같은 수</b>여야 합니다.</summary>
    public static PrintSizeMm DimensionsMm(PrintPaperSize size) => size switch
    {
        PrintPaperSize.PhotoRatio =>
            new(PhotoRatioLongEdgeMm * 2 / 3, PhotoRatioLongEdgeMm),
        PrintPaperSize.ThreePointFiveByFive => new(88.9, 127),
        PrintPaperSize.FourBySix => new(101.6, 152.4),
        PrintPaperSize.FiveBySeven => new(127, 177.8),
        PrintPaperSize.EightByTen => new(203.2, 254),
        PrintPaperSize.TenByTwelve => new(254, 304.8),
        PrintPaperSize.ElevenByFourteen => new(279.4, 355.6),
        PrintPaperSize.TwelveByEighteen => new(304.8, 457.2),
        PrintPaperSize.SixteenByTwenty => new(406.4, 508),
        PrintPaperSize.TwentyByTwentyFour => new(508, 609.6),
        PrintPaperSize.TwentyByThirty => new(508, 762),
        PrintPaperSize.TwentyFourByThirtySix => new(609.6, 914.4),
        PrintPaperSize.Letter => new(215.9, 279.4),
        PrintPaperSize.Tabloid => new(279.4, 431.8),
        PrintPaperSize.A3Plus => new(329, 483),
        PrintPaperSize.A6 => new(105, 148),
        PrintPaperSize.A5 => new(148, 210),
        PrintPaperSize.A4 => new(210, 297),
        PrintPaperSize.A3 => new(297, 420),
        PrintPaperSize.A2 => new(420, 594),
        PrintPaperSize.A1 => new(594, 841),
        PrintPaperSize.B6 => new(125, 176),
        PrintPaperSize.B5 => new(176, 250),
        PrintPaperSize.B4 => new(250, 353),
        PrintPaperSize.B3 => new(353, 500),
        PrintPaperSize.B2 => new(500, 707),
        _ => new(707, 1000),
    };

    /// <summary>
    /// 사진 비율 용지는 사진을 따라갑니다. 비율을 모르면 macOS 처럼 3:2 로 둡니다.
    /// </summary>
    public static PrintSizeMm DimensionsMm(PrintPaperSize size, double? photoAspectRatio)
    {
        if (size != PrintPaperSize.PhotoRatio ||
            photoAspectRatio is not { } ratio ||
            !double.IsFinite(ratio) ||
            ratio <= 0)
        {
            return DimensionsMm(size);
        }
        return ratio >= 1
            ? new PrintSizeMm(PhotoRatioLongEdgeMm, PhotoRatioLongEdgeMm / ratio)
            : new PrintSizeMm(PhotoRatioLongEdgeMm * ratio, PhotoRatioLongEdgeMm);
    }

    /// <summary>
    /// 고르개에 보이는 이름입니다. 번역하지 않습니다 — A4·Letter 는 규격 이름이고 치수 표기는
    /// 언어와 무관합니다. macOS <c>uiLabel</c> 과 같습니다.
    /// </summary>
    public static string Label(PrintPaperSize size) => size switch
    {
        PrintPaperSize.PhotoRatio => "Photo",
        PrintPaperSize.ThreePointFiveByFive => "3.5 × 5 in",
        PrintPaperSize.FourBySix => "4 × 6 in",
        PrintPaperSize.FiveBySeven => "5 × 7 in",
        PrintPaperSize.EightByTen => "8 × 10 in",
        PrintPaperSize.TenByTwelve => "10 × 12 in",
        PrintPaperSize.ElevenByFourteen => "11 × 14 in",
        PrintPaperSize.TwelveByEighteen => "12 × 18 in",
        PrintPaperSize.SixteenByTwenty => "16 × 20 in",
        PrintPaperSize.TwentyByTwentyFour => "20 × 24 in",
        PrintPaperSize.TwentyByThirty => "20 × 30 in",
        PrintPaperSize.TwentyFourByThirtySix => "24 × 36 in",
        PrintPaperSize.Letter => "Letter · 8.5 × 11 in",
        PrintPaperSize.Tabloid => "Tabloid · 11 × 17 in",
        PrintPaperSize.A3Plus => "A3+ · 13 × 19 in",
        _ => size.ToString().ToUpperInvariant(),
    };
}

/// <summary>인화 판 하나를 정하는 값입니다. macOS <c>PrintCompositionSettings</c> 과 같습니다.</summary>
public sealed record PrintCompositionSettings
{
    public PrintPaperSize PaperSize { get; init; } = PrintPaperSize.A4;

    public PrintPaperOrientation Orientation { get; init; } = PrintPaperOrientation.Automatic;

    public double MarginMm { get; init; } = 10;

    public int Dpi { get; init; } = 300;

    public PrintPerforationStyle PerforationStyle { get; init; } = PrintPerforationStyle.None;

    /// <summary><c>PhotoRatio</c> 용지가 따라갈 사진의 가로/세로비입니다. 다른 용지는 무시합니다.</summary>
    public double? PhotoAspectRatio { get; init; }

    public PrintPresentationStyle PresentationStyle { get; init; } =
        PrintPresentationStyle.Standard;

    public PrintSheetBackground SheetBackground { get; init; } = PrintSheetBackground.White;

    public PrintSizeMm PaperDimensionsMm => PrintPaper.DimensionsMm(PaperSize, PhotoAspectRatio);

    /// <summary>macOS 와 같은 한계입니다 — 여백 0~50mm, 해상도 72~600dpi.</summary>
    public bool IsValid =>
        double.IsFinite(MarginMm) && MarginMm is >= 0 and <= 50 && Dpi is >= 72 and <= 600;
}

/// <summary>
/// 한 장을 어떻게 놓을지 계산한 결과입니다. 화면 미리보기와 내보내기가 <b>같은 값</b>을 씁니다 —
/// 둘이 다른 계산을 하면 보이는 것과 나오는 것이 갈립니다.
/// </summary>
public sealed record PrintCompositionLayout(
    PrintSizeMm CanvasSize,
    PrintRect ContentRect,
    PrintRect ImageRect,
    PrintRect? FilmRect,
    IReadOnlyList<PrintRect> PerforationRects,
    double PerforationCornerRadius)
{
    /// <summary>
    /// 계산합니다. 사진 크기나 설정이 말이 안 되면 null 입니다 — 억지로 한 장을 만들면 사용자는
    /// 왜 이상한 판이 나왔는지 알 수 없습니다.
    /// </summary>
    public static PrintCompositionLayout? Make(
        PrintSizeMm sourceSize,
        PrintCompositionSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        if (sourceSize.Width <= 0 || sourceSize.Height <= 0 ||
            !double.IsFinite(sourceSize.Width) || !double.IsFinite(sourceSize.Height) ||
            !settings.IsValid)
        {
            return null;
        }

        bool sourceIsLandscape = sourceSize.Width >= sourceSize.Height;
        PrintSizeMm page = PageDimensions(
            settings.PaperDimensionsMm,
            settings.Orientation,
            sourceIsLandscape);

        double pixelsPerMm = settings.Dpi / 25.4;
        PrintSizeMm canvas = new(
            Math.Max(1, Math.Round(page.Width * pixelsPerMm)),
            Math.Max(1, Math.Round(page.Height * pixelsPerMm)));
        double margin = settings.MarginMm * pixelsPerMm;
        PrintRect content = new PrintRect(0, 0, canvas.Width, canvas.Height).Inset(margin);
        if (content.Width <= 1 || content.Height <= 1)
        {
            return null;
        }

        if (settings.PerforationStyle == PrintPerforationStyle.None)
        {
            return new PrintCompositionLayout(
                canvas,
                content,
                AspectFit(sourceSize, content),
                null,
                [],
                0);
        }

        // ISO 1007 의 135 풀프레임 기준입니다 — 35mm 폭, 24×36mm 이미지 게이트, 프레임 피치
        // 38mm(4.75mm KS-1870 천공 8개). macOS 와 같은 수입니다.
        PrintSizeMm filmMm = sourceIsLandscape ? new(38, 35) : new(35, 38);
        PrintRect film = AspectFit(filmMm, content);
        double unit = sourceIsLandscape ? film.Height / 35 : film.Width / 35;
        PrintSizeMm gateMm = sourceIsLandscape ? new(36, 24) : new(24, 36);
        PrintRect gate = new(
            film.MidX - (gateMm.Width * unit / 2),
            film.MidY - (gateMm.Height * unit / 2),
            gateMm.Width * unit,
            gateMm.Height * unit);

        double pitch = 4.75 * unit;
        double railCenterOffset = 2.75 * unit;
        List<PrintRect> perforations = new(16);
        if (sourceIsLandscape)
        {
            PrintSizeMm hole = new(2.79 * unit, 1.98 * unit);
            double firstX = film.MidX - (((7 * pitch) + hole.Width) / 2);
            double bottomY = film.MinY + railCenterOffset - (hole.Height / 2);
            double topY = film.MaxY - railCenterOffset - (hole.Height / 2);
            for (int index = 0; index < 8; ++index)
            {
                double x = firstX + (index * pitch);
                perforations.Add(new PrintRect(x, bottomY, hole.Width, hole.Height));
                perforations.Add(new PrintRect(x, topY, hole.Width, hole.Height));
            }
        }
        else
        {
            PrintSizeMm hole = new(1.98 * unit, 2.79 * unit);
            double firstY = film.MidY - (((7 * pitch) + hole.Height) / 2);
            double leftX = film.MinX + railCenterOffset - (hole.Width / 2);
            double rightX = film.MaxX - railCenterOffset - (hole.Width / 2);
            for (int index = 0; index < 8; ++index)
            {
                double y = firstY + (index * pitch);
                perforations.Add(new PrintRect(leftX, y, hole.Width, hole.Height));
                perforations.Add(new PrintRect(rightX, y, hole.Width, hole.Height));
            }
        }

        return new PrintCompositionLayout(
            canvas,
            content,
            AspectFit(sourceSize, gate),
            film,
            perforations,
            0.51 * unit);
    }

    /// <summary>
    /// 방향을 정한 뒤의 용지 치수입니다. 자동은 사진을 따라갑니다 — 가로 사진에 세로 용지를
    /// 내밀면 사용자가 매번 방향을 고쳐야 합니다.
    /// </summary>
    internal static PrintSizeMm PageDimensions(
        PrintSizeMm paper,
        PrintPaperOrientation orientation,
        bool sourceIsLandscape)
    {
        double longEdge = Math.Max(paper.Width, paper.Height);
        double shortEdge = Math.Min(paper.Width, paper.Height);
        bool landscape = orientation switch
        {
            PrintPaperOrientation.Portrait => false,
            PrintPaperOrientation.Landscape => true,
            _ => sourceIsLandscape,
        };
        return landscape ? new PrintSizeMm(longEdge, shortEdge) : new PrintSizeMm(shortEdge, longEdge);
    }

    /// <summary>비율을 지키며 가운데 맞춰 넣습니다.</summary>
    internal static PrintRect AspectFit(PrintSizeMm size, PrintRect bounds)
    {
        double scale = Math.Min(bounds.Width / size.Width, bounds.Height / size.Height);
        double width = size.Width * scale;
        double height = size.Height * scale;
        return new PrintRect(
            bounds.MidX - (width / 2),
            bounds.MidY - (height / 2),
            width,
            height);
    }
}

/// <summary>
/// 공정별 겉모습입니다. 그림자와 하이라이트가 어느 색으로 가는지만 정합니다 — macOS
/// <c>PrintPresentationAppearance</c> 와 같은 수입니다.
/// </summary>
public readonly record struct PrintPresentationAppearance(
    double ShadowRed,
    double ShadowGreen,
    double ShadowBlue,
    double HighlightRed,
    double HighlightGreen,
    double HighlightBlue)
{
    public static PrintPresentationAppearance For(PrintPresentationStyle style) => style switch
    {
        // 시아노타입의 철염 이미지가 갖는 청색 단색 관계만 표현합니다.
        PrintPresentationStyle.Cyanotype => new(0.02, 0.10, 0.36, 0.96, 0.98, 1),
        _ => new(0, 0, 0, 1, 1, 1),
    };
}
