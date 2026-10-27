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
    private static readonly FontFamily Font = new("Segoe UI");

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

    /// <summary>글 한 줄의 폭입니다. 미리보기와 판이 같은 측정을 씁니다.</summary>
    internal static double Measure(string text, double fontSize, bool bold)
    {
        TextBlock block = TextBlockFor(new PrintWatermarkTextItem(text, 0, 0, 0, fontSize, bold, false), Microsoft.UI.Colors.Black);
        block.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        return block.DesiredSize.Width;
    }

    /// <summary>글 한 줄을 BGRA(premultiplied) 화소로 만듭니다. 그릴 수 없으면 null 입니다.</summary>
    internal static async Task<(byte[] Pixels, int Width, int Height)?> RenderTextAsync(
        Panel host,
        PrintWatermarkTextItem item,
        Windows.UI.Color color)
    {
        int width = Math.Max(1, (int)Math.Ceiling(item.Width) + 2);
        int height = Math.Max(1, (int)Math.Ceiling(item.FontSize * PrintWatermarkMetrics.LineHeightFactor) + 1);
        TextBlock block = TextBlockFor(item, color);
        block.Width = width;
        block.Height = height;
        host.Children.Add(block);
        try
        {
            block.Measure(new Windows.Foundation.Size(width, height));
            block.Arrange(new Windows.Foundation.Rect(0, 0, width, height));
            block.UpdateLayout();
            RenderTargetBitmap target = new();
            await target.RenderAsync(block, width, height);
            IBuffer buffer = await target.GetPixelsAsync();
            byte[] pixels = buffer.ToArray();
            return pixels.Length >= target.PixelWidth * target.PixelHeight * 4
                ? (pixels, target.PixelWidth, target.PixelHeight)
                : null;
        }
        catch (Exception exception) when (exception is InvalidOperationException or
            System.Runtime.InteropServices.COMException)
        {
            // 글자를 못 그리면 그 줄만 빠집니다. 사진과 띠 바탕은 그대로 나갑니다.
            return null;
        }
        finally
        {
            host.Children.Remove(block);
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
