using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views.Print.Preview;

/// <summary>
/// 인화 미리보기의 워터마크 띠입니다. 판(<see cref="PrintWatermarkPainter"/>)과 같은 배치 계산
/// (<see cref="PrintWatermarkBandLayout"/>)과 같은 참조 그림(필름스트립 썸네일)을 씁니다.
/// </summary>
/// <remarks>
/// 썸네일·로고를 푸는 일은 비동기라, 처음 그릴 때는 자리만 잡고 풀리면 <c>redraw</c> 로 한 번 더
/// 그립니다. 푼 결과는 사진·설정이 같으면 다시 풀지 않습니다.
/// <para>
/// <b>다시 푸는 동안에는 직전 결과를 그대로 그립니다.</b> 판은 필름스트립 썸네일·현상본이 도착할
/// 때마다 다시 그려지는데, 그때 참조를 비운 채 그리면 띠가 흰색 ↔ 블러로, 히스토그램이 있다 없다
/// 바뀌며 깜빡였습니다(사용자 신고). 로고도 새 파일을 읽는 동안 이전 로고를 둡니다.
/// </para>
/// </remarks>
internal sealed class PrintWatermarkPreview
{
    private readonly Action redraw;
    private readonly Dictionary<string, PrintWatermarkReference?> references = [];
    private readonly HashSet<string> pendingReferences = [];
    /// <summary>사진·설정별로 마지막에 그린 참조입니다. 새 참조를 푸는 동안 대신 그립니다.</summary>
    private readonly Dictionary<string, PrintWatermarkReference> lastReferences = [];
    /// <summary>블러 바탕 그림은 참조마다 한 번만 만듭니다(다시 그릴 때마다 새 비트맵을 걸지 않습니다).</summary>
    private readonly System.Runtime.CompilerServices.ConditionalWeakTable<PrintWatermarkReference, ImageSource> blurImages = new();
    /// <summary>
    /// 읽은 로고입니다. <c>Exists</c> 는 읽을 때의 파일 유무 — 이것이 바뀔 때만 다시 읽습니다. 그림
    /// 유무로 비교하면 파일은 있는데 그림으로 못 읽는 경우 읽기 → 다시 그리기가 끝없이 돕니다.
    /// </summary>
    private (string Key, bool Exists, double? Aspect, ImageSource? Image)? logo;
    private bool logoPending;

    internal PrintWatermarkPreview(Action redraw) => this.redraw = redraw;

    /// <summary>
    /// 썸네일이 새로 오면 참조를 다시 풉니다. 풀리는 동안은 직전 참조(<c>lastReferences</c>)를 그립니다.
    /// </summary>
    internal void Invalidate() => references.Clear();

    /// <summary>띠 바탕을 그립니다. 사진 타일보다 먼저 부릅니다.</summary>
    internal void AddBackground(
        Canvas canvas,
        PrintRect unit,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        double scale)
    {
        Brush fill;
        if (settings.Background == PrintWatermarkBackground.Blur && reference?.Blur is { } blur)
        {
            // 판과 같은 aspect fill: 띠 포함 한 장 전체를 흐린 그림으로 채우고 남는 쪽을 자릅니다.
            fill = new ImageBrush
            {
                ImageSource = blurImages.GetValue(reference, _ => PrintWatermarkRaster.BlurBitmap(blur)),
                Stretch = Stretch.UniformToFill,
            };
        }
        else
        {
            byte level = settings.Background == PrintWatermarkBackground.Black ? (byte)0x00 : (byte)0xFF;
            fill = new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, level, level, level));
        }
        Rectangle background = new()
        {
            Width = Math.Max(1, unit.Width * scale),
            Height = Math.Max(1, unit.Height * scale),
            Fill = fill,
        };
        Canvas.SetLeft(background, unit.X * scale);
        Canvas.SetTop(background, unit.Y * scale);
        canvas.Children.Add(background);
    }

    /// <summary>띠 위의 글자·로고·세로선·히스토그램을 그립니다. 사진 타일 다음에 부릅니다.</summary>
    internal void AddContent(
        Canvas canvas,
        PrintRect unit,
        PrintWatermarkFrameLayout frame,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        double scale)
    {
        double? logoAspect = LogoAspect(settings);
        bool hasHistogram = reference?.Histogram is not null;
        PrintWatermarkTextWidth measure = (text, fontSize, bold) =>
            PrintWatermarkRaster.Measure(canvas, text, fontSize, bold);
        PrintRect bottom = Scaled(frame.Place(frame.BottomBand, unit), scale);
        AddBand(canvas, bottom, settings, reference,
            PrintWatermarkBandLayout.Bottom(
                settings, bottom.Width, bottom.Height, logoAspect, hasHistogram, measure));
        if (frame.TopBand is { } topBand && PrintWatermarkBandLayout.HasTopItems(settings, hasHistogram))
        {
            PrintRect top = Scaled(frame.Place(topBand, unit), scale);
            AddBand(canvas, top, settings, reference,
                PrintWatermarkBandLayout.Top(
                    settings, top.Width, top.Height, hasHistogram, measure));
        }
    }

    /// <summary>
    /// 참조 그림(블러·히스토그램)입니다. 아직 풀지 않았으면 풀기 시작하고, 그동안은 같은 사진·설정의
    /// 직전 참조(없으면 null)를 돌려줍니다.
    /// </summary>
    internal PrintWatermarkReference? Reference(
        LibraryFrameSnapshot frame,
        PrintSizeMm photoSize,
        PrintWatermarkSettings settings,
        PrintPresentationStyle presentation,
        ThumbnailService? thumbnails)
    {
        if (settings.Background != PrintWatermarkBackground.Blur && !settings.ShowsHistogram)
        {
            return null;
        }
        byte[]? jpeg = thumbnails?.TryGet(frame.Id);
        ThumbnailService.DevelopedPreview developed = default;
        bool hasDeveloped = thumbnails?.TryGetPrintDeveloped(frame, out developed) == true;
        string slot = string.Join('|', frame.Id, settings.Background, settings.ShowsHistogram, presentation);
        string key = string.Join('|', slot, jpeg?.Length ?? 0, hasDeveloped ? developed.Width : 0);
        if (references.TryGetValue(key, out PrintWatermarkReference? known))
        {
            if (known is not null)
            {
                Remember(slot, known);
            }
            return known ?? lastReferences.GetValueOrDefault(slot);
        }
        if (pendingReferences.Add(key))
        {
            _ = LoadReferenceAsync(key, jpeg, hasDeveloped ? developed : null, photoSize, settings, presentation);
        }
        // 새 참조가 풀릴 때까지 같은 사진·설정의 직전 참조를 그립니다(없으면 처음 한 번만 비어 있습니다).
        return lastReferences.GetValueOrDefault(slot);
    }

    /// <summary>
    /// 직전 참조를 기억합니다. 판은 한 번에 한 사진만 띠를 그리므로 몇 개만 두고, 넘치면 지금 것만
    /// 남깁니다(참조마다 블러 장이 있어 사진을 넘길수록 쌓이지 않게 합니다).
    /// </summary>
    private void Remember(string slot, PrintWatermarkReference reference)
    {
        if (lastReferences.Count >= 8 && !lastReferences.ContainsKey(slot))
        {
            lastReferences.Clear();
        }
        lastReferences[slot] = reference;
    }

    private async Task LoadReferenceAsync(
        string key,
        byte[]? jpeg,
        ThumbnailService.DevelopedPreview? developed,
        PrintSizeMm photoSize,
        PrintWatermarkSettings settings,
        PrintPresentationStyle presentation)
    {
        PrintWatermarkReference? reference = null;
        // 필름스트립 썸네일이 먼저입니다. 없거나 비율이 다르면(오래됨) 화면 현상본을 줄여 씁니다.
        if (jpeg is { Length: > 0 } &&
            await PrintWatermarkRaster.DecodeReferenceAsync(jpeg) is { } thumbnail)
        {
            reference = PrintWatermarkReference.From(thumbnail, photoSize, settings, presentation);
        }
        if (reference is null && developed is { } preview)
        {
            reference = PrintWatermarkReference.From(
                (preview.Pixels, preview.Width, preview.Height), photoSize, settings, presentation);
        }
        references[key] = reference;
        pendingReferences.Remove(key);
        if (reference is not null)
        {
            redraw();
        }
    }

    /// <summary>
    /// 로고의 가로/세로 비입니다. 경로(비었으면 negaflow 로고)에서 읽고, 아직이면 읽기를 시작하고 null 을
    /// 돌려줍니다. 파일이 지워졌으면 로고 없이 그립니다(사실은 하단 상태 점·진단에 남습니다).
    /// </summary>
    private double? LogoAspect(PrintWatermarkSettings settings)
    {
        if (!settings.ShowsLogo)
        {
            return null;
        }
        string key = settings.LogoSourcePath;
        // 파일이 지워졌거나 다시 생겼으면 다시 읽습니다(그동안 지워진 그림을 계속 보여 주지 않습니다).
        bool exists = key.Length == 0 || File.Exists(key);
        if (logo is { } known && known.Key == key && known.Exists == exists)
        {
            return known.Aspect;
        }
        if (!logoPending)
        {
            logoPending = true;
            _ = LoadLogoAsync(settings, key, exists);
        }
        // 새로 읽는 동안은 이전 로고를 둡니다 — 띠의 오른쪽 블록이 비었다 차며 움직이지 않습니다.
        // 지워진 파일이면 이전 그림을 남기지 않습니다.
        return exists ? logo?.Aspect : null;
    }

    private async Task LoadLogoAsync(PrintWatermarkSettings settings, string key, bool exists)
    {
        double? aspect = null;
        ImageSource? image = null;
        try
        {
            if (await PrintWatermarkLogo.LoadAsync(settings) is { } png &&
                await PrintWatermarkRaster.LogoBitmapAsync(png) is { } bitmap)
            {
                aspect = (double)bitmap.PixelWidth / bitmap.PixelHeight;
                image = bitmap;
            }
        }
        finally
        {
            // 읽다가 예외가 나도 "읽는 중" 을 풉니다. 남아 있으면 로고를 다시는 읽지 않습니다.
            logoPending = false;
        }
        // 로고가 없던 것이 계속 없으면(읽을 수 없는 파일) 다시 그릴 것이 없습니다.
        bool stillNone = logo is { Image: null } && image is null;
        logo = (key, exists, aspect, image);
        if (!stillNone)
        {
            redraw();
        }
    }

    private void AddBand(
        Canvas canvas,
        PrintRect band,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        PrintWatermarkBandDrawing drawing)
    {
        // 띠 하나를 제 크기의 층에 모아 띠 밖으로는 아무것도 그려지지 않게 합니다(판의 띠 비트맵과 같다).
        Canvas layer = new()
        {
            Width = Math.Max(1, band.Width),
            Height = Math.Max(1, band.Height),
            Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, band.Width, band.Height) },
        };
        canvas.Children.Add(Positioned(layer, band.X, band.Y));
        foreach (PrintWatermarkTextItem item in drawing.Texts)
        {
            TextBlock block = PrintWatermarkRaster.TextBlockFor(
                item, PrintWatermarkRaster.Ink(settings.TextInk, item.Secondary));
            layer.Children.Add(Positioned(block, item.X, item.Y));
        }
        if (drawing.Separator is { } separator)
        {
            layer.Children.Add(Positioned(
                new Rectangle
                {
                    Width = Math.Max(1, separator.Width),
                    Height = separator.Height,
                    Fill = new SolidColorBrush(PrintWatermarkRaster.Ink(settings.TextInk, secondary: true)),
                },
                separator.X,
                separator.Y));
        }
        if (drawing.Logo is { } logoRect && logo?.Image is { } image)
        {
            layer.Children.Add(Positioned(
                new Image { Source = image, Width = logoRect.Width, Height = logoRect.Height, Stretch = Stretch.Uniform },
                logoRect.X,
                logoRect.Y));
        }
        if (drawing.Histogram is { } histogram && reference?.Histogram is { } columns)
        {
            AddHistogram(
                layer,
                histogram,
                columns,
                PrintWatermarkRaster.Ink(settings.HistogramInk, secondary: false));
        }
    }

    private static void AddHistogram(Canvas canvas, PrintRect rect, IReadOnlyList<double> columns, Windows.UI.Color color)
    {
        int rows = PrintWatermarkMetrics.HistogramRows;
        double pitchX = rect.Width / columns.Count;
        double pitchY = rect.Height / rows;
        double diameter = Math.Min(pitchX, pitchY) * PrintWatermarkMetrics.HistogramDotFill;
        SolidColorBrush lit = new(color);
        SolidColorBrush faint = new(color) { Opacity = PrintWatermarkMetrics.HistogramEmptyDotAlpha };
        for (int column = 0; column < columns.Count; ++column)
        {
            double value = columns[column];
            int count = value > 0
                ? Math.Min(rows, Math.Max(1, (int)Math.Round(value * rows, MidpointRounding.AwayFromZero)))
                : 0;
            double centerX = rect.X + ((column + 0.5) * pitchX);
            for (int row = 0; row < rows; ++row)
            {
                double centerY = rect.MaxY - ((row + 0.5) * pitchY);
                canvas.Children.Add(Positioned(
                    new Ellipse { Width = diameter, Height = diameter, Fill = row < count ? lit : faint },
                    centerX - (diameter / 2),
                    centerY - (diameter / 2)));
            }
        }
    }

    private static UIElement Positioned(UIElement element, double left, double top)
    {
        Canvas.SetLeft(element, left);
        Canvas.SetTop(element, top);
        return element;
    }

    private static PrintRect Scaled(PrintRect rect, double scale) =>
        new(rect.X * scale, rect.Y * scale, rect.Width * scale, rect.Height * scale);
}
