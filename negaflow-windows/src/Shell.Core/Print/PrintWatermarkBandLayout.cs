namespace Negaflow.Shell.Print;

/// <summary>글 한 줄의 폭을 잽니다. 화면은 XAML 글자 측정을, 시험은 고정 폭을 넘깁니다.</summary>
public delegate double PrintWatermarkTextWidth(string text, double fontSize, bool bold);

/// <summary>띠 위 글 한 줄입니다. 좌표는 띠 안의 왼쪽 위 원점이며 높이는 글자 크기 × 1.2 입니다.</summary>
public sealed record PrintWatermarkTextItem(
    string Text,
    double X,
    double Y,
    double Width,
    double FontSize,
    bool Bold,
    bool Secondary);

/// <summary>한 띠에 그릴 것들입니다. 비어 있는 항목은 그리지 않습니다.</summary>
public sealed record PrintWatermarkBandDrawing(
    IReadOnlyList<PrintWatermarkTextItem> Texts,
    PrintRect? Logo,
    PrintRect? Separator,
    PrintRect? Histogram)
{
    public bool IsEmpty => Texts.Count == 0 && Logo is null && Separator is null && Histogram is null;
}

/// <summary>
/// 띠 안의 배치입니다. macOS <c>PrintWatermarkRenderer</c> 의 <c>drawBottomBand</c> ·
/// <c>drawTopBand</c> 와 같은 규칙이며, 글이 띠 폭을 넘으면 들어갈 때까지 전체를 같은 비율로 줄입니다.
/// </summary>
public static class PrintWatermarkBandLayout
{
    /// <summary>아래 띠: 왼쪽 카메라·렌즈, 오른쪽 로고·노출·일시, 가운데 히스토그램·이름.</summary>
    public static PrintWatermarkBandDrawing Bottom(
        PrintWatermarkSettings settings,
        double width,
        double band,
        double? logoAspect,
        bool hasHistogram,
        PrintWatermarkTextWidth measure)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(measure);
        double inset = PrintWatermarkMetrics.HorizontalInset * band;
        double gap = PrintWatermarkMetrics.ItemGap * band;
        double available = width - (2 * inset);
        if (available <= 0 || band <= 0)
        {
            return Empty;
        }

        if (Fit(
                available,
                scale => (
                    Leading: new TwoLine(settings.CameraName, settings.LensName, band, scale, measure),
                    Trailing: new Trailing(settings, logoAspect, band, scale, measure),
                    Center: new Slot(settings, PrintWatermarkPlacement.BottomCenter, hasHistogram, band, scale, measure)),
                parts => parts.Center.IsEmpty
                    ? (parts.Leading.Width + parts.Trailing.Width, gap)
                    : ((2 * Math.Max(parts.Leading.Width, parts.Trailing.Width)) + parts.Center.Width, 2 * gap))
            is not { } bottomParts)
        {
            return Empty;
        }
        var (leading, trailing, center) = bottomParts;

        List<PrintWatermarkTextItem> texts = [];
        leading.Place(inset, band, texts);
        PrintRect? logo = null;
        PrintRect? separator = null;
        if (!trailing.IsEmpty)
        {
            (logo, separator) = trailing.Place(width - inset, band, texts);
        }
        PrintRect? histogram = null;
        if (!center.IsEmpty)
        {
            histogram = center.PlaceCentered(width / 2, band, texts);
        }
        return new PrintWatermarkBandDrawing(texts, logo, separator, histogram);
    }

    /// <summary>위 띠: 왼쪽·가운데·오른쪽 자리.</summary>
    public static PrintWatermarkBandDrawing Top(
        PrintWatermarkSettings settings,
        double width,
        double band,
        bool hasHistogram,
        PrintWatermarkTextWidth measure)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentNullException.ThrowIfNull(measure);
        double inset = PrintWatermarkMetrics.HorizontalInset * band;
        double available = width - (2 * inset);
        if (available <= 0 || band <= 0)
        {
            return Empty;
        }
        double gap = PrintWatermarkMetrics.ItemGap * band;
        if (Fit(
                available,
                scale => (
                    Leading: new Slot(settings, PrintWatermarkPlacement.TopLeading, hasHistogram, band, scale, measure),
                    Center: new Slot(settings, PrintWatermarkPlacement.TopCenter, hasHistogram, band, scale, measure),
                    Trailing: new Slot(settings, PrintWatermarkPlacement.TopTrailing, hasHistogram, band, scale, measure)),
                parts => parts.Center.IsEmpty
                    ? (parts.Leading.Width + parts.Trailing.Width, gap)
                    : ((2 * Math.Max(parts.Leading.Width, parts.Trailing.Width)) + parts.Center.Width, 2 * gap))
            is not { } topParts)
        {
            return Empty;
        }
        var (leading, center, trailing) = topParts;
        List<PrintWatermarkTextItem> texts = [];
        // 히스토그램은 자리를 하나만 고르므로 세 자리 중 많아야 한 곳에서만 나옵니다.
        PrintRect? leadingHistogram = leading.Place(inset, band, texts);
        PrintRect? centerHistogram = center.IsEmpty ? null : center.PlaceCentered(width / 2, band, texts);
        PrintRect? trailingHistogram = trailing.Place(width - inset - trailing.Width, band, texts);
        return new PrintWatermarkBandDrawing(
            texts, null, null, leadingHistogram ?? centerHistogram ?? trailingHistogram);
    }

    /// <summary>위 띠에 놓을 것이 있는지입니다.</summary>
    public static bool HasTopItems(PrintWatermarkSettings settings, bool hasHistogram)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return settings.AddsTopBand &&
            new[] { PrintWatermarkPlacement.TopLeading, PrintWatermarkPlacement.TopCenter, PrintWatermarkPlacement.TopTrailing }
                .Any(placement =>
                    Shows(settings, hasHistogram, histogram: true, placement) ||
                    Shows(settings, hasHistogram, histogram: false, placement));
    }

    private static readonly PrintWatermarkBandDrawing Empty = new([], null, null, null);

    /// <summary>
    /// 띠 폭에 들어가도록 전체를 같은 비율로 줄인 배치입니다. 하한은 두지 않습니다 — 글이 길거나
    /// 세로 사진이라 띠가 좁으면 글이 작아질 뿐 띠(사진) 밖으로 나가거나 서로 겹치지 않습니다.
    /// 글 폭은 글자 크기에 딱 비례하지 않으므로(측정 반올림, 1px 세로선) 들어갈 때까지 다시 잽니다.
    /// 블록 사이 간격만으로 폭이 모자라면 null 입니다.
    /// </summary>
    private static T? Fit<T>(
        double available,
        Func<double, T> make,
        Func<T, (double Content, double Gaps)> width)
        where T : struct
    {
        double scale = 1;
        T parts = make(scale);
        for (int attempt = 0; attempt < FitAttempts; ++attempt)
        {
            (double content, double gaps) = width(parts);
            if (content <= 0 || content + gaps <= available)
            {
                return parts;
            }
            double room = available - gaps;
            if (room <= 0)
            {
                return null;
            }
            scale *= room / content;
            parts = make(scale);
        }
        return parts;
    }

    private const int FitAttempts = 6;

    private static bool Shows(
        PrintWatermarkSettings settings,
        bool hasHistogram,
        bool histogram,
        PrintWatermarkPlacement placement) =>
        histogram
            ? settings.ShowsHistogram && hasHistogram &&
                settings.EffectivePlacement(settings.HistogramPlacement) == placement
            : !string.IsNullOrWhiteSpace(settings.UserName) &&
                settings.EffectivePlacement(settings.UserNamePlacement) == placement;

    private static double LineHeight(double fontSize) => fontSize * PrintWatermarkMetrics.LineHeightFactor;

    /// <summary>굵은 줄 + 보조 줄 두 줄 묶음입니다. 한 줄만 있으면 그 줄을 가운데에 둡니다.</summary>
    private readonly struct TwoLine
    {
        private readonly string first;
        private readonly string second;
        private readonly double firstSize;
        private readonly double secondSize;
        private readonly double firstWidth;
        private readonly double secondWidth;
        private readonly double gap;

        public TwoLine(string? first, string? second, double band, double scale, PrintWatermarkTextWidth measure)
        {
            this.first = (first ?? string.Empty).Trim();
            this.second = (second ?? string.Empty).Trim();
            firstSize = PrintWatermarkMetrics.PrimaryFontSize * band * scale;
            secondSize = PrintWatermarkMetrics.SecondaryFontSize * band * scale;
            firstWidth = this.first.Length > 0 ? measure(this.first, firstSize, true) : 0;
            secondWidth = this.second.Length > 0 ? measure(this.second, secondSize, false) : 0;
            gap = PrintWatermarkMetrics.LineGap * band * scale;
        }

        public double Width => Math.Max(firstWidth, secondWidth);

        public bool IsEmpty => first.Length == 0 && second.Length == 0;

        public void Place(double x, double band, List<PrintWatermarkTextItem> texts)
        {
            if (first.Length > 0 && second.Length > 0)
            {
                double height = LineHeight(firstSize) + gap + LineHeight(secondSize);
                double top = (band - height) / 2;
                texts.Add(new(first, x, top, firstWidth, firstSize, true, false));
                texts.Add(new(second, x, top + LineHeight(firstSize) + gap, secondWidth, secondSize, false, true));
            }
            else if (first.Length > 0)
            {
                texts.Add(new(first, x, (band - LineHeight(firstSize)) / 2, firstWidth, firstSize, true, false));
            }
            else if (second.Length > 0)
            {
                texts.Add(new(second, x, (band - LineHeight(secondSize)) / 2, secondWidth, secondSize, false, true));
            }
        }
    }

    /// <summary>로고 + 세로선 + 노출·일시 두 줄입니다. 로고나 글 한쪽만 있으면 세로선은 없습니다.</summary>
    private readonly struct Trailing
    {
        private readonly TwoLine text;
        private readonly double logoWidth;
        private readonly double logoHeight;
        private readonly double separatorGap;
        private readonly double separatorWidth;
        private readonly double separatorHeight;

        public Trailing(
            PrintWatermarkSettings settings,
            double? logoAspect,
            double band,
            double scale,
            PrintWatermarkTextWidth measure)
        {
            text = new TwoLine(settings.ExposureLine, settings.CaptureDate, band, scale, measure);
            if (logoAspect is { } aspect && double.IsFinite(aspect) && aspect > 0)
            {
                double height = PrintWatermarkMetrics.LogoHeight * band * scale;
                logoWidth = Math.Min(PrintWatermarkMetrics.LogoMaximumWidth * band * scale, height * aspect);
                logoHeight = logoWidth / aspect;
            }
            else
            {
                logoWidth = 0;
                logoHeight = 0;
            }
            separatorGap = PrintWatermarkMetrics.SeparatorGap * band * scale;
            separatorWidth = Math.Max(1, Math.Round(0.012 * band, MidpointRounding.AwayFromZero));
            separatorHeight = PrintWatermarkMetrics.SeparatorHeight * band * scale;
        }

        private bool HasLogo => logoWidth > 0;

        private bool HasSeparator => HasLogo && !text.IsEmpty;

        public double Width =>
            (HasLogo ? logoWidth : 0) +
            (HasSeparator ? (2 * separatorGap) + separatorWidth : 0) +
            text.Width;

        public bool IsEmpty => !HasLogo && text.IsEmpty;

        public (PrintRect? Logo, PrintRect? Separator) Place(
            double trailingEdge,
            double band,
            List<PrintWatermarkTextItem> texts)
        {
            double cursor = trailingEdge - Width;
            PrintRect? logo = null;
            PrintRect? separator = null;
            if (HasLogo)
            {
                logo = new PrintRect(cursor, (band - logoHeight) / 2, logoWidth, logoHeight);
                cursor += logoWidth;
            }
            if (HasSeparator)
            {
                cursor += separatorGap;
                separator = new PrintRect(
                    Math.Round(cursor, MidpointRounding.AwayFromZero),
                    (band - separatorHeight) / 2,
                    separatorWidth,
                    separatorHeight);
                cursor += separatorWidth + separatorGap;
            }
            text.Place(cursor, band, texts);
            return (logo, separator);
        }
    }

    /// <summary>
    /// 한 자리에 히스토그램과 이름이 함께 있으면 위아래로 놓고 각각 가운데를 맞춥니다.
    /// </summary>
    private readonly struct Slot
    {
        private readonly string name;
        private readonly double nameSize;
        private readonly double nameWidth;
        private readonly double histogramWidth;
        private readonly double histogramHeight;
        private readonly double verticalGap;

        public Slot(
            PrintWatermarkSettings settings,
            PrintWatermarkPlacement placement,
            bool hasHistogram,
            double band,
            double scale,
            PrintWatermarkTextWidth measure)
        {
            HasHistogram = Shows(settings, hasHistogram, histogram: true, placement);
            name = Shows(settings, hasHistogram, histogram: false, placement) ? settings.UserName.Trim() : string.Empty;
            nameSize = PrintWatermarkMetrics.SecondaryFontSize * band * scale;
            nameWidth = name.Length > 0 ? measure(name, nameSize, false) : 0;
            histogramWidth = PrintWatermarkMetrics.HistogramWidth * band * scale;
            histogramHeight = PrintWatermarkMetrics.HistogramHeight * band * scale;
            verticalGap = PrintWatermarkMetrics.LineGap * band * scale;
        }

        private bool HasBoth => HasHistogram && name.Length > 0;

        public bool HasHistogram { get; }

        public bool IsEmpty => !HasHistogram && name.Length == 0;

        /// <summary>세로로 쌓는 항목 가운데 더 넓은 폭입니다.</summary>
        public double Width => Math.Max(HasHistogram ? histogramWidth : 0, nameWidth);

        /// <summary>가운데 축 <paramref name="centerX"/> 를 기준으로 놓습니다.</summary>
        public PrintRect? PlaceCentered(double centerX, double band, List<PrintWatermarkTextItem> texts)
        {
            if (HasBoth)
            {
                double top = (band - histogramHeight - verticalGap - LineHeight(nameSize)) / 2;
                PrintRect histogram = new(
                    centerX - (histogramWidth / 2), top, histogramWidth, histogramHeight);
                AddName(centerX - (nameWidth / 2), band, texts, top + histogramHeight + verticalGap);
                return histogram;
            }
            if (HasHistogram)
            {
                return new PrintRect(centerX - (histogramWidth / 2), (band - histogramHeight) / 2, histogramWidth, histogramHeight);
            }
            AddName(centerX - (nameWidth / 2), band, texts);
            return null;
        }

        private void AddName(double x, double band, List<PrintWatermarkTextItem> texts, double? y = null)
        {
            if (name.Length > 0)
            {
                // 사용자 이름은 보조 줄 크기지만 색은 굵은 줄과 같은 글자색입니다(macOS 와 같다).
                texts.Add(new(name, x, y ?? (band - LineHeight(nameSize)) / 2, nameWidth, nameSize, false, false));
            }
        }

        /// <summary>놓고 히스토그램 자리를 돌려줍니다(없으면 null).</summary>
        public PrintRect? Place(double x, double band, List<PrintWatermarkTextItem> texts)
        {
            return PlaceCentered(x + (Width / 2), band, texts);
        }
    }
}
