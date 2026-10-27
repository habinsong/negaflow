using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Negaflow.Catalog;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views.Print.Preview;

/// <summary>
/// 인화 미리보기의 워터마크 띠입니다. 판(<see cref="PrintWatermarkPainter"/>)과 같은 배치 계산
/// (<see cref="PrintWatermarkBandLayout"/>)과 같은 참조 그림(필름스트립 썸네일)을 씁니다.
/// </summary>
/// <remarks>
/// 썸네일·로고를 푸는 일은 비동기라, 처음 그릴 때는 자리만 잡고 풀리면 <c>redraw</c> 로 한 번 더
/// 그립니다. 푼 결과는 사진·설정이 같으면 다시 풀지 않습니다.
/// </remarks>
internal sealed class PrintWatermarkPreview
{
    private readonly Action redraw;
    private readonly Dictionary<string, PrintWatermarkReference?> references = [];
    private readonly HashSet<string> pendingReferences = [];
    private (string Key, double? Aspect, ImageSource? Image)? logo;
    private bool logoPending;

    internal PrintWatermarkPreview(Action redraw) => this.redraw = redraw;

    /// <summary>썸네일이 새로 오면 참조를 버립니다(다음 그리기에서 다시 풉니다).</summary>
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
                ImageSource = PrintWatermarkRaster.BlurBitmap(blur),
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
        PrintRect bottom = Scaled(frame.Place(frame.BottomBand, unit), scale);
        AddBand(canvas, bottom, settings, reference,
            PrintWatermarkBandLayout.Bottom(
                settings, bottom.Width, bottom.Height, logoAspect, hasHistogram, PrintWatermarkRaster.Measure));
        if (frame.TopBand is { } topBand && PrintWatermarkBandLayout.HasTopItems(settings, hasHistogram))
        {
            PrintRect top = Scaled(frame.Place(topBand, unit), scale);
            AddBand(canvas, top, settings, reference,
                PrintWatermarkBandLayout.Top(
                    settings, top.Width, top.Height, hasHistogram, PrintWatermarkRaster.Measure));
        }
    }

    /// <summary>
    /// 참조 그림(블러·히스토그램)입니다. 아직 풀지 않았으면 풀기 시작하고 null 을 돌려줍니다.
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
        string key = string.Join('|',
            frame.Id,
            jpeg?.Length ?? 0,
            hasDeveloped ? developed.Width : 0,
            settings.Background,
            settings.ShowsHistogram,
            presentation);
        if (references.TryGetValue(key, out PrintWatermarkReference? known))
        {
            return known;
        }
        if (pendingReferences.Add(key))
        {
            _ = LoadReferenceAsync(key, jpeg, hasDeveloped ? developed : null, photoSize, settings, presentation);
        }
        return null;
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
        if (logo is { } known && known.Key == key && (known.Image is not null) == exists)
        {
            return known.Aspect;
        }
        if (!logoPending)
        {
            logoPending = true;
            _ = LoadLogoAsync(settings, key);
        }
        return null;
    }

    private async Task LoadLogoAsync(PrintWatermarkSettings settings, string key)
    {
        double? aspect = null;
        ImageSource? image = null;
        if (await PrintWatermarkLogo.LoadAsync(settings) is { } png)
        {
            aspect = await PrintWatermarkRaster.LogoAspectAsync(png);
            BitmapImage bitmap = new();
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(png.AsBuffer());
            stream.Seek(0);
            await bitmap.SetSourceAsync(stream);
            image = bitmap;
        }
        logo = (key, aspect, image);
        logoPending = false;
        redraw();
    }

    private void AddBand(
        Canvas canvas,
        PrintRect band,
        PrintWatermarkSettings settings,
        PrintWatermarkReference? reference,
        PrintWatermarkBandDrawing drawing)
    {
        foreach (PrintWatermarkTextItem item in drawing.Texts)
        {
            TextBlock block = PrintWatermarkRaster.TextBlockFor(
                item, PrintWatermarkRaster.Ink(settings.TextInk, item.Secondary));
            Canvas.SetLeft(block, band.X + item.X);
            Canvas.SetTop(block, band.Y + item.Y);
            canvas.Children.Add(block);
        }
        if (drawing.Separator is { } separator)
        {
            canvas.Children.Add(Positioned(
                new Rectangle
                {
                    Width = Math.Max(1, separator.Width),
                    Height = separator.Height,
                    Fill = new SolidColorBrush(PrintWatermarkRaster.Ink(settings.TextInk, secondary: true)),
                },
                band.X + separator.X,
                band.Y + separator.Y));
        }
        if (drawing.Logo is { } logoRect && logo?.Image is { } image)
        {
            canvas.Children.Add(Positioned(
                new Image { Source = image, Width = logoRect.Width, Height = logoRect.Height, Stretch = Stretch.Uniform },
                band.X + logoRect.X,
                band.Y + logoRect.Y));
        }
        if (drawing.Histogram is { } histogram && reference?.Histogram is { } columns)
        {
            AddHistogram(
                canvas,
                new PrintRect(band.X + histogram.X, band.Y + histogram.Y, histogram.Width, histogram.Height),
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
