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
/// <c>drawTopBand</c> 와 같은 규칙이며, 글이 띠 폭을 넘으면 전체를 같은 비율로 줄입니다.
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

        TwoLine Leading(double scale) =>
            new(settings.CameraName, settings.LensName, band, scale, measure);
        Trailing TrailingAt(double scale) =>
            new(settings, logoAspect, band, scale, measure);
        Slot Center(double scale) =>
            new(settings, PrintWatermarkPlacement.BottomCenter, hasHistogram, band, scale, measure);

        TwoLine leading = Leading(1);
        Trailing trailing = TrailingAt(1);
        Slot center = Center(1);
        double needed = center.IsEmpty
            ? leading.Width + trailing.Width + gap
            : (2 * Math.Max(leading.Width, trailing.Width)) + center.Width + (2 * gap);
        double scale = FitScale(available, needed);
        if (scale < 1)
        {
            leading = Leading(scale);
            trailing = TrailingAt(scale);
            center = Center(scale);
        }

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
        Slot LeadingAt(double scale) =>
            new(settings, PrintWatermarkPlacement.TopLeading, hasHistogram, band, scale, measure);
        Slot CenterAt(double scale) =>
            new(settings, PrintWatermarkPlacement.TopCenter, hasHistogram, band, scale, measure);
        Slot TrailingAt(double scale) =>
            new(settings, PrintWatermarkPlacement.TopTrailing, hasHistogram, band, scale, measure);
        Slot leading = LeadingAt(1);
        Slot center = CenterAt(1);
        Slot trailing = TrailingAt(1);
        double needed = center.IsEmpty
            ? leading.Width + trailing.Width + gap
            : (2 * Math.Max(leading.Width, trailing.Width)) + center.Width + (2 * gap);
        double scale = FitScale(available, needed);
        if (scale < 1)
        {
            leading = LeadingAt(scale);
            center = CenterAt(scale);
            trailing = TrailingAt(scale);
        }
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

    private static double FitScale(double available, double needed) =>
        needed > available && needed > 0
            ? Math.Max(PrintWatermarkMetrics.MinimumFitScale, available / needed)
            : 1;

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
