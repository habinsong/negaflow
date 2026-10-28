using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Shell.Print;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 워터마크 띠의 글자·로고·참조 그림을 화소로 바꿉니다. 글자는 화면과 같은 XAML 글자 그리기를
/// 거치므로(<see cref="PrintTextRasterizer"/> 와 같은 이유) 미리보기와 판이 같은 글꼴로 나옵니다.
/// </summary>
internal static class PrintWatermarkRaster
{
    /// <summary>
    /// 띠 글꼴입니다. macOS 는 Helvetica Neue(굵게·보통)를 씁니다. Windows 에는 그 글꼴이 없어 Helvetica 와
    /// 글자 폭을 맞춰 만든 Arial 을 씁니다 — Segoe UI 는 글자 모양과 폭이 달라 띠가 맥과 다르게 짜였습니다.
    /// </summary>
    private static readonly FontFamily Font = new("Arial");

    /// <summary>띠 글자 색입니다. macOS 와 같은 값 — 흰 바탕은 검정·회색, 검정 바탕은 모두 흰색.</summary>
    internal static Windows.UI.Color Ink(PrintWatermarkInk ink, bool secondary) => ink == PrintWatermarkInk.Black
        ? (secondary
            ? Windows.UI.Color.FromArgb(0xFF, 0x87, 0x87, 0x87)
            : Windows.UI.Color.FromArgb(0xFF, 0x12, 0x12, 0x12))
        : Windows.UI.Color.FromArgb(0xFF, 0xFF, 0xFF, 0xFF);

    internal static TextBlock TextBlockFor(PrintWatermarkTextItem item, Windows.UI.Color color) => new()
    {
        Text = item.Text,
        FontFamily = Font,
        FontSize = Math.Max(1, item.FontSize),
        FontWeight = item.Bold ? FontWeights.Bold : FontWeights.Normal,
        // 줄 높이를 글자 크기 × 1.2 로 고정해 배치 계산(`PrintWatermarkBandLayout`)과 같은 높이를 씁니다.
        LineHeight = Math.Max(1, item.FontSize * PrintWatermarkMetrics.LineHeightFactor),
        LineStackingStrategy = LineStackingStrategy.BlockLineHeight,
        Foreground = new SolidColorBrush(color),
        TextWrapping = TextWrapping.NoWrap,
        IsTextScaleFactorEnabled = false,
    };

    /// <summary>
    /// 글 한 줄의 폭입니다. 미리보기와 판이 같은 측정을 씁니다. 글자를 그릴 화면 트리(<paramref name="host"/>)에
    /// 잠깐 붙여 그릴 때와 같은 조건에서 잽니다 — 띠 배치는 이 폭으로 오른쪽 블록의 시작점을 정하므로
    /// 폭이 실제보다 작으면 블록이 오른쪽으로 밀려 띠 밖으로 나갑니다.
    /// </summary>
    internal static double Measure(Panel? host, string text, double fontSize, bool bold)
    {
        TextBlock block = TextBlockFor(new PrintWatermarkTextItem(text, 0, 0, 0, fontSize, bold, false), Microsoft.UI.Colors.Black);
        Windows.Foundation.Size unbounded = new(double.PositiveInfinity, double.PositiveInfinity);
        if (host is null)
        {
            block.Measure(unbounded);
            return block.DesiredSize.Width;
        }
        host.Children.Add(block);
        try
        {
            block.Measure(unbounded);
            return block.DesiredSize.Width;
        }
        finally
        {
            host.Children.Remove(block);
        }
    }

    /// <summary>
    /// 띠 한 장의 글자를 미리보기와 같은 <see cref="TextBlock"/> 배치로 한 번에 화소로 만듭니다. 결과는
    /// <paramref name="width"/> × <paramref name="height"/>(판 화소) BGRA(premultiplied)이며, 그릴 수 없으면 null 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="RenderTargetBitmap"/> 은 요소를 그 창의 화면 배율(<c>XamlRoot.RasterizationScale</c>)로 그립니다. 그래서
    /// 글자와 자리를 배율로 나눠 놓아 판 화소 그대로 받고, 그래도 크기가 다르면 <see cref="PrintRasterFit"/> 로 판
    /// 크기에 맞춥니다 — 배율이 몇이든 판에는 배치 계산 크기 그대로 찍혀 미리보기와 같습니다. 예전에는 글자 줄마다
    /// 따로 그려 받은 크기 그대로 붙여, 150% 화면에서 모든 글자가 1.5배로 커져 띠 밖으로 나갔고 줄마다 렌더러를
    /// 기다려 내보내기도 느렸습니다.
    /// </remarks>
    internal static async Task<byte[]?> RenderTextLayerAsync(
        Panel host,
        IReadOnlyList<PrintWatermarkTextItem> texts,
        int width,
        int height,
        Func<PrintWatermarkTextItem, Windows.UI.Color> ink)
    {
        if (texts.Count == 0 || width < 1 || height < 1)
        {
            return null;
        }
        double scale = host.XamlRoot?.RasterizationScale is double rasterization && rasterization > 0
            ? rasterization
            : 1;
        Canvas layer = new()
        {
            Width = width / scale,
            Height = height / scale,
            // 배경이 없으면 렌더러는 층이 아니라 글자가 있는 경계만 그립니다(실측: 1825x237 을 바랐는데
            // 1612x128). 완전히 투명한 배경을 깔아 층 전체를 그리게 하고, 층 밖으로 나간 글자는 자릅니다.
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, width / scale, height / scale) },
        };
        foreach (PrintWatermarkTextItem item in texts)
        {
            TextBlock block = TextBlockFor(item with { FontSize = item.FontSize / scale }, ink(item));
            Canvas.SetLeft(block, item.X / scale);
            Canvas.SetTop(block, item.Y / scale);
            layer.Children.Add(block);
        }
        host.Children.Add(layer);
        try
        {
            layer.Measure(new Windows.Foundation.Size(layer.Width, layer.Height));
            layer.Arrange(new Windows.Foundation.Rect(0, 0, layer.Width, layer.Height));
            layer.UpdateLayout();
            RenderTargetBitmap target = new();
            await target.RenderAsync(layer);
            byte[] pixels = (await target.GetPixelsAsync()).ToArray();
            if (target.PixelWidth != width || target.PixelHeight != height)
            {
                Negaflow.Shell.ExportTrace.Write(
                    $"      watermark text layer rendered {target.PixelWidth}x{target.PixelHeight} for {width}x{height} (scale {scale})");
            }
            return target.PixelWidth > 0 && target.PixelHeight > 0 &&
                   pixels.Length >= target.PixelWidth * target.PixelHeight * 4
                ? PrintRasterFit.ToSize(pixels, target.PixelWidth, target.PixelHeight, width, height)
                : null;
        }
        catch (Exception exception) when (exception is InvalidOperationException or ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            // 글자를 못 그리면 글자만 빠집니다. 사진과 띠 바탕·로고·히스토그램은 그대로 나갑니다.
            return null;
        }
        finally
        {
            host.Children.Remove(layer);
        }
    }

    /// <summary>
    /// 로고 PNG 를 화면에 걸 그림으로 풉니다. 풀 수 없으면 null 입니다.
    /// </summary>
    /// <remarks>
    /// <c>BitmapImage.SetSourceAsync</c> 는 그림을 나중에 풀 수 있어, 스트림을 바로 닫으면 로고가 보일 때도 있고 안
    /// 보일 때도 있었습니다(사용자 신고). 판과 같은 디코더로 화소까지 풀어 <see cref="WriteableBitmap"/> 에 바로 담습니다.
    /// </remarks>
    internal static async Task<WriteableBitmap?> LogoBitmapAsync(byte[] png)
    {
        try
        {
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(png.AsBuffer());
            stream.Seek(0);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            uint width = decoder.OrientedPixelWidth;
            uint height = decoder.OrientedPixelHeight;
            if (width == 0 || height == 0)
            {
                return null;
            }
            PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                new BitmapTransform(),
                ExifOrientationMode.RespectExifOrientation,
                ColorManagementMode.ColorManageToSRgb);
            byte[] bgra = pixels.DetachPixelData();
            WriteableBitmap bitmap = new((int)width, (int)height);
            using (Stream buffer = bitmap.PixelBuffer.AsStream())
            {
                buffer.Write(bgra, 0, Math.Min(bgra.Length, (int)bitmap.PixelBuffer.Capacity));
            }
            bitmap.Invalidate();
            return bitmap;
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    /// <summary>로고 PNG 를 그 자리 크기의 BGRA(premultiplied)로 풉니다.</summary>
    internal static async Task<byte[]?> DecodeLogoAsync(byte[] png, int width, int height)
    {
        try
        {
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(png.AsBuffer());
            stream.Seek(0);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                new BitmapTransform
                {
                    ScaledWidth = (uint)Math.Max(1, width),
                    ScaledHeight = (uint)Math.Max(1, height),
                    InterpolationMode = BitmapInterpolationMode.Fant,
                },
                ExifOrientationMode.RespectExifOrientation,
                ColorManagementMode.ColorManageToSRgb);
            return pixels.DetachPixelData();
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    /// <summary>로고의 가로/세로 비입니다. 풀 수 없으면 null 입니다.</summary>
    internal static async Task<double?> LogoAspectAsync(byte[]? png)
    {
        if (png is not { Length: > 0 })
        {
            return null;
        }
        try
        {
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(png.AsBuffer());
            stream.Seek(0);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            return decoder.OrientedPixelHeight > 0
                ? (double)decoder.OrientedPixelWidth / decoder.OrientedPixelHeight
                : null;
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    /// <summary>
    /// 사용자가 고른 그림 파일(jpg·png·bmp·heic 등 WIC 가 여는 것)을 로고 PNG 로 맞춥니다. 긴 변을
    /// 1024 로 줄이고, 결과가 상한을 넘거나 열 수 없으면 null 입니다 — macOS
    /// <c>normalizedLogoPNG(from:)</c>.
    /// </summary>
    internal static async Task<byte[]?> NormalizeLogoAsync(IRandomAccessStream source)
    {
        const int maximumPixels = 1024;
        try
        {
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(source);
            uint width = decoder.OrientedPixelWidth;
            uint height = decoder.OrientedPixelHeight;
            if (width == 0 || height == 0)
            {
                return null;
            }
            double scale = Math.Min(1, (double)maximumPixels / Math.Max(width, height));
            uint outWidth = Math.Max(1, (uint)Math.Round(width * scale, MidpointRounding.AwayFromZero));
            uint outHeight = Math.Max(1, (uint)Math.Round(height * scale, MidpointRounding.AwayFromZero));
            PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                new BitmapTransform
                {
                    ScaledWidth = outWidth,
                    ScaledHeight = outHeight,
                    InterpolationMode = BitmapInterpolationMode.Fant,
                },
                ExifOrientationMode.RespectExifOrientation,
                ColorManagementMode.ColorManageToSRgb);
            using InMemoryRandomAccessStream output = new();
            BitmapEncoder encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, output);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                outWidth,
                outHeight,
                96,
                96,
                pixels.DetachPixelData());
            await encoder.FlushAsync();
            byte[] png = new byte[output.Size];
            output.Seek(0);
            await output.ReadAsync(png.AsBuffer(), (uint)png.Length, InputStreamOptions.None);
            return png.Length is > 0 and <= PrintWatermarkSettings.MaximumLogoBytes ? png : null;
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException or NotSupportedException)
        {
            return null;
        }
    }

    /// <summary>
    /// 블러·히스토그램의 참조 그림(필름스트립 썸네일 JPEG)을 BGRA(불투명)로 풉니다.
    /// </summary>
    internal static async Task<(byte[] Pixels, int Width, int Height)?> DecodeReferenceAsync(byte[] encoded)
    {
        try
        {
            using InMemoryRandomAccessStream stream = new();
            await stream.WriteAsync(encoded.AsBuffer());
            stream.Seek(0);
            return await DecodeReferenceAsync(stream);
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    /// <summary>파일·스트림을 참조 그림 크기(긴 변 256)로 줄여 풉니다.</summary>
    internal static async Task<(byte[] Pixels, int Width, int Height)?> DecodeReferenceAsync(IRandomAccessStream stream)
    {
        try
        {
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
            uint width = decoder.PixelWidth;
            uint height = decoder.PixelHeight;
            if (width == 0 || height == 0)
            {
                return null;
            }
            double scale = Math.Min(1, PrintWatermarkMetrics.BlurWorkingLongEdge / Math.Max(width, height));
            uint outWidth = Math.Max(1, (uint)Math.Round(width * scale, MidpointRounding.AwayFromZero));
            uint outHeight = Math.Max(1, (uint)Math.Round(height * scale, MidpointRounding.AwayFromZero));
            PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                new BitmapTransform
                {
                    ScaledWidth = outWidth,
                    ScaledHeight = outHeight,
                    InterpolationMode = BitmapInterpolationMode.Fant,
                },
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            byte[] bgra = pixels.DetachPixelData();
            for (int index = 3; index < bgra.Length; index += 4)
            {
                bgra[index] = 0xFF;
            }
            return (bgra, (int)outWidth, (int)outHeight);
        }
        catch (Exception exception) when (exception is ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            return null;
        }
    }

    /// <summary>흐린 바탕을 화면에 걸 그림으로 만듭니다.</summary>
    internal static WriteableBitmap BlurBitmap(PrintWatermarkPixels.BlurField field)
    {
        byte[] bgra = field.EncodedBgra();
        WriteableBitmap bitmap = new(field.Width, field.Height);
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(bgra, 0, Math.Min(bgra.Length, (int)bitmap.PixelBuffer.Capacity));
        }
        bitmap.Invalidate();
        return bitmap;
    }
}

/// <summary>
/// 한 장의 블러 바탕과 히스토그램입니다. 참조 그림이 사진과 다른 비율이면(오래된 썸네일) 쓰지
/// 않습니다 — macOS 와 같은 판정입니다.
/// </summary>
internal sealed record PrintWatermarkReference(PrintWatermarkPixels.BlurField? Blur, double[]? Histogram)
{
    internal static PrintWatermarkReference? From(
        (byte[] Pixels, int Width, int Height) image,
        PrintSizeMm photoSize,
        PrintWatermarkSettings settings,
        PrintPresentationStyle presentation)
    {
        if (image.Width < 1 || image.Height < 1 || photoSize.Height <= 0 ||
            Math.Abs(((double)image.Width / image.Height) - (photoSize.Width / photoSize.Height)) >= 0.02)
        {
            return null;
        }
        (byte[] pixels, int width, int height) = PrintWatermarkPixels.Downscale(
            image.Pixels, image.Width, image.Height, (int)PrintWatermarkMetrics.BlurWorkingLongEdge);
        // 공정 겉모습(시아노타입 등)은 사진에 입힌 것과 같이 참조에도 입힙니다.
        PrintPresentationFilter.Apply(pixels, presentation);
        return new PrintWatermarkReference(
            settings.Background == PrintWatermarkBackground.Blur
                ? PrintWatermarkPixels.Blur(pixels, width, height)
                : null,
            settings.ShowsHistogram
                ? PrintWatermarkPixels.HistogramColumns(pixels, width, height)
                : null);
    }
}
