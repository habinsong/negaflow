using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 판(16-bit RGB 버퍼)에 워터마크 띠를 그립니다. 배치는 <see cref="PrintWatermarkBandLayout"/> 이
/// 정하고, 미리보기(<c>PrintWatermarkPreview</c>)도 같은 배치를 씁니다.
/// </summary>
/// <remarks>
/// 순서: 띠 바탕 → (호출자가 사진을 얹음) → <see cref="PaintContentAsync"/> 로 글자·로고·세로선·
/// 히스토그램. 사진은 띠 바깥에만 놓이므로 바탕을 먼저 깔아도 사진 화소는 바뀌지 않습니다.
/// </remarks>
internal static class PrintWatermarkPainter
{
    private static ushort Widen(byte value) => (ushort)(value * 257);

    private static ushort Code(double unit) =>
        (ushort)Math.Clamp((int)Math.Round(unit * 65535, MidpointRounding.AwayFromZero), 0, 65535);

    /// <summary>띠 바탕(흰색·검정·블러)을 깝니다. 사진 자리는 건드리지 않습니다.</summary>
    internal static void PaintBackgrounds(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        PrintRect unit,
        PrintWatermarkFrameLayout frame,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference)
    {
        foreach (PrintRect band in Bands(frame))
        {
            PrintRect onPage = frame.Place(band, unit);
            if (settings.Background == PrintWatermarkBackground.Blur && reference?.Blur is { } blur)
            {
                FillBlur(page, pageWidth, pageHeight, onPage, unit, frame, blur);
                continue;
            }
            // 블러를 골랐는데 참조 그림이 없으면 흰 띠로 둡니다(글자색 규칙이 흰 바탕과 같지는
            // 않으므로 사용자가 고른 글자색이 보이도록 바탕만 바꿉니다).
            byte level = settings.Background == PrintWatermarkBackground.Black ? (byte)0x00 : (byte)0xFF;
            PrintPageCanvas.Fill(page, pageWidth, pageHeight, onPage, level, level, level);
        }
    }

    /// <summary>띠 위의 글자·로고·세로선·히스토그램을 그립니다.</summary>
    internal static async Task PaintContentAsync(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        PrintRect unit,
        PrintWatermarkFrameLayout frame,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        Microsoft.UI.Xaml.Controls.Panel? textHost)
    {
        double? logoAspect = await PrintWatermarkRaster.LogoAspectAsync(settings.LogoPng);
        bool hasHistogram = reference?.Histogram is not null;
        PrintRect bottom = frame.Place(frame.BottomBand, unit);
        await PaintBandAsync(
            page, pageWidth, pageHeight, bottom, settings, reference, textHost,
            PrintWatermarkBandLayout.Bottom(
                settings, Math.Round(bottom.Width), bottom.Height, logoAspect, hasHistogram,
                PrintWatermarkRaster.Measure));
        if (frame.TopBand is { } topBand && PrintWatermarkBandLayout.HasTopItems(settings, hasHistogram))
        {
            PrintRect top = frame.Place(topBand, unit);
            await PaintBandAsync(
                page, pageWidth, pageHeight, top, settings, reference, textHost,
                PrintWatermarkBandLayout.Top(
                    settings, Math.Round(top.Width), top.Height, hasHistogram, PrintWatermarkRaster.Measure));
        }
    }

    private static IEnumerable<PrintRect> Bands(PrintWatermarkFrameLayout frame)
    {
        yield return frame.BottomBand;
        if (frame.TopBand is { } top)
        {
            yield return top;
        }
    }

    private static async Task PaintBandAsync(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        PrintRect band,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        Microsoft.UI.Xaml.Controls.Panel? textHost,
        PrintWatermarkBandDrawing drawing)
    {
        if (textHost is not null)
        {
            foreach (PrintWatermarkTextItem item in drawing.Texts)
            {
                if (await PrintWatermarkRaster.RenderTextAsync(
                        textHost, item, PrintWatermarkRaster.Ink(settings.TextInk, item.Secondary))
                    is { } rendered)
                {
                    BlendPremultiplied(
                        page, pageWidth, pageHeight, rendered.Pixels, rendered.Width, rendered.Height,
                        (int)Math.Round(band.X + item.X), (int)Math.Round(band.Y + item.Y));
                }
            }
        }
        if (drawing.Separator is { } separator)
        {
            Windows.UI.Color color = PrintWatermarkRaster.Ink(settings.TextInk, secondary: true);
            PrintPageCanvas.Fill(
                page, pageWidth, pageHeight,
                new PrintRect(band.X + separator.X, band.Y + separator.Y, separator.Width, separator.Height),
                color.R, color.G, color.B);
        }
        if (drawing.Logo is { } logo && settings.LogoPng is { } png)
        {
            int width = Math.Max(1, (int)Math.Round(logo.Width));
            int height = Math.Max(1, (int)Math.Round(logo.Height));
            if (await PrintWatermarkRaster.DecodeLogoAsync(png, width, height) is { } pixels)
            {
                BlendPremultiplied(
                    page, pageWidth, pageHeight, pixels, width, height,
                    (int)Math.Round(band.X + logo.X), (int)Math.Round(band.Y + logo.Y));
            }
        }
        if (drawing.Histogram is { } histogram && reference?.Histogram is { } columns)
        {
            PaintHistogram(
                page, pageWidth, pageHeight,
                new PrintRect(band.X + histogram.X, band.Y + histogram.Y, histogram.Width, histogram.Height),
                columns,
                PrintWatermarkRaster.Ink(settings.HistogramInk, secondary: false));
        }
    }

    /// <summary>점으로 된 세로 막대입니다. 빈 자리도 옅은 점으로 찍습니다(macOS 와 같다).</summary>
    private static void PaintHistogram(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        PrintRect rect,
        IReadOnlyList<double> columns,
        Windows.UI.Color color)
    {
        int rows = PrintWatermarkMetrics.HistogramRows;
        double pitchX = rect.Width / columns.Count;
        double pitchY = rect.Height / rows;
        double radius = Math.Min(pitchX, pitchY) * PrintWatermarkMetrics.HistogramDotFill / 2;
        for (int column = 0; column < columns.Count; ++column)
        {
            double value = columns[column];
            int lit = value > 0
                ? Math.Min(rows, Math.Max(1, (int)Math.Round(value * rows, MidpointRounding.AwayFromZero)))
                : 0;
            double centerX = rect.X + ((column + 0.5) * pitchX);
            for (int row = 0; row < rows; ++row)
            {
                // 아래에서부터 쌓습니다(판은 위가 원점이므로 아래 칸부터 셉니다).
                double centerY = rect.MaxY - ((row + 0.5) * pitchY);
                double opacity = row < lit ? 1 : PrintWatermarkMetrics.HistogramEmptyDotAlpha;
                FillDot(page, pageWidth, pageHeight, centerX, centerY, radius, color, opacity);
            }
        }
    }

    /// <summary>가장자리를 덮인 넓이만큼 섞어 계단이 보이지 않는 점입니다.</summary>
    private static void FillDot(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        double centerX,
        double centerY,
        double radius,
        Windows.UI.Color color,
        double opacity)
    {
        int left = Math.Max(0, (int)Math.Floor(centerX - radius - 1));
        int right = Math.Min(pageWidth - 1, (int)Math.Ceiling(centerX + radius + 1));
        int top = Math.Max(0, (int)Math.Floor(centerY - radius - 1));
        int bottom = Math.Min(pageHeight - 1, (int)Math.Ceiling(centerY + radius + 1));
        ushort red = Widen(color.R);
        ushort green = Widen(color.G);
        ushort blue = Widen(color.B);
        for (int y = top; y <= bottom; ++y)
        {
            for (int x = left; x <= right; ++x)
            {
                double distance = Math.Sqrt(
                    Math.Pow(x + 0.5 - centerX, 2) + Math.Pow(y + 0.5 - centerY, 2));
                double coverage = Math.Clamp(radius + 0.5 - distance, 0, 1) * opacity;
                if (coverage <= 0)
                {
                    continue;
                }
                int at = ((y * pageWidth) + x) * PrintPageCanvas.Channels;
                page[at] = (ushort)Math.Round((red * coverage) + (page[at] * (1 - coverage)));
                page[at + 1] = (ushort)Math.Round((green * coverage) + (page[at + 1] * (1 - coverage)));
                page[at + 2] = (ushort)Math.Round((blue * coverage) + (page[at + 2] * (1 - coverage)));
            }
        }
    }

    /// <summary>BGRA(premultiplied) 그림을 판에 얹습니다.</summary>
    private static void BlendPremultiplied(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        byte[] bgra,
        int width,
        int height,
        int left,
        int top)
    {
        for (int y = 0; y < height; ++y)
        {
            int pageY = top + y;
            if (pageY < 0 || pageY >= pageHeight)
            {
                continue;
            }
            for (int x = 0; x < width; ++x)
            {
                int pageX = left + x;
                if (pageX < 0 || pageX >= pageWidth)
                {
                    continue;
                }
                int from = ((y * width) + x) * 4;
                byte alpha = bgra[from + 3];
                if (alpha == 0)
                {
                    continue;
                }
                int to = ((pageY * pageWidth) + pageX) * PrintPageCanvas.Channels;
                for (int channel = 0; channel < PrintPageCanvas.Channels; ++channel)
                {
                    // premultiplied: 결과 = 원본 + 바탕 × (1 − α). BGRA 이므로 R·G·B 를 거꾸로 읽습니다.
                    int source = Widen(bgra[from + (2 - channel)]);
                    page[to + channel] = (ushort)Math.Min(65535,
                        source + (page[to + channel] * (255 - alpha) / 255));
                }
            }
        }
    }

    private static void FillBlur(
        ushort[] page,
        int pageWidth,
        int pageHeight,
        PrintRect onPage,
        PrintRect unit,
        PrintWatermarkFrameLayout frame,
        PrintWatermarkPixels.BlurField blur)
    {
        double scale = unit.Width / frame.FrameSize.Width;
        int left = Math.Max(0, (int)Math.Round(onPage.X));
        int top = Math.Max(0, (int)Math.Round(onPage.Y));
        int right = Math.Min(pageWidth, (int)Math.Round(onPage.MaxX));
        int bottom = Math.Min(pageHeight, (int)Math.Round(onPage.MaxY));
        for (int y = top; y < bottom; ++y)
        {
            double frameY = (y + 0.5 - unit.Y) / scale;
            int row = y * pageWidth * PrintPageCanvas.Channels;
            for (int x = left; x < right; ++x)
            {
                double frameX = (x + 0.5 - unit.X) / scale;
                (double red, double green, double blue) =
                    blur.SampleFill(frame.FrameSize.Width, frame.FrameSize.Height, frameX, frameY);
                int at = row + (x * PrintPageCanvas.Channels);
                page[at] = Code(red);
                page[at + 1] = Code(green);
                page[at + 2] = Code(blue);
            }
        }
    }
}
