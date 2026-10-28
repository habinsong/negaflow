using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.Views;

/// <summary>
/// 캡션 글자를 판에 찍을 화소로 바꿉니다.
/// </summary>
/// <remarks>
/// **화면이 쓰는 글자 그리기를 그대로 씁니다.** <see cref="RenderTargetBitmap"/> 은 XAML 이
/// 화면에 글자를 그릴 때 쓰는 것과 같은 글꼴 처리를 거치므로, 미리보기의 캡션과 파일의 캡션이
/// 다른 글꼴로 나오지 않습니다. 새 그리기 엔진을 들이면 그 보장이 사라집니다.
///
/// 렌더러는 UI 스레드에서만 돌고 살아 있는 시각 트리 안의 요소만 그릴 수 있습니다. 그래서
/// 판을 쓰는 쪽은 눈에 보이지 않는 host 를 하나 넘겨 주어야 합니다.
/// </remarks>
public static class PrintTextRasterizer
{
    /// <summary>
    /// 글자 한 줄을 BGRA 화소로 만듭니다. 그릴 수 없으면 null 이며, 그때는 캡션 없이 판이
    /// 나갑니다 — 글자 하나 때문에 인화 전체를 실패시키지 않습니다.
    /// </summary>
    public static async Task<(byte[] Pixels, int Width, int Height)?> RenderAsync(
        Panel host,
        string text,
        int width,
        int height,
        PrintPackageCaptionAlignment alignment,
        bool lightForeground)
    {
        ArgumentNullException.ThrowIfNull(host);
        if (string.IsNullOrEmpty(text) || width < 1 || height < 1)
        {
            return null;
        }

        // RenderTargetBitmap 은 그 창의 화면 배율(RasterizationScale)로 그립니다. 글자와 칸을 배율로 나눠
        // 놓아 판 화소 그대로 받고, 그래도 다르면 판 크기에 맞춥니다 — 받은 크기 그대로 붙이면 150% 화면에서
        // 캡션이 1.5배로 커져 칸 밖으로 나갑니다(워터마크 글자와 같은 원인).
        double scale = host.XamlRoot?.RasterizationScale is double rasterization && rasterization > 0
            ? rasterization
            : 1;
        double boxWidth = width / scale;
        double boxHeight = height / scale;
        TextBlock block = new()
        {
            Text = text,
            // 칸 높이의 3분의 2 를 글자 높이로 씁니다. 칸을 꽉 채우면 위아래가 붙어 읽기
            // 어렵고, macOS 캡션도 여백을 남깁니다.
            FontSize = Math.Max(6, height * 2.0 / 3.0) / scale,
            FontWeight = FontWeights.Normal,
            Foreground = new SolidColorBrush(lightForeground
                ? Microsoft.UI.Colors.White
                : Microsoft.UI.Colors.Black),
            TextAlignment = alignment switch
            {
                PrintPackageCaptionAlignment.Leading => TextAlignment.Left,
                PrintPackageCaptionAlignment.Trailing => TextAlignment.Right,
                _ => TextAlignment.Center,
            },
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap,
            VerticalAlignment = VerticalAlignment.Center,
        };
        // 렌더러는 배경 없는 요소의 경우 글자가 있는 경계만 그립니다. 완전히 투명한 배경의 칸에 담아 칸 전체를
        // 그리게 합니다(워터마크 글자 층과 같은 이유).
        Grid box = new()
        {
            Width = boxWidth,
            Height = boxHeight,
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
        };
        box.Children.Add(block);

        host.Children.Add(box);
        try
        {
            box.Measure(new Windows.Foundation.Size(boxWidth, boxHeight));
            box.Arrange(new Windows.Foundation.Rect(0, 0, boxWidth, boxHeight));
            box.UpdateLayout();

            RenderTargetBitmap target = new();
            await target.RenderAsync(box);
            Windows.Storage.Streams.IBuffer buffer = await target.GetPixelsAsync();
            byte[] pixels = new byte[buffer.Length];
            using (Windows.Storage.Streams.DataReader reader =
                Windows.Storage.Streams.DataReader.FromBuffer(buffer))
            {
                reader.ReadBytes(pixels);
            }
            return target.PixelWidth > 0 && target.PixelHeight > 0 &&
                   pixels.Length >= target.PixelWidth * target.PixelHeight * 4
                ? (PrintRasterFit.ToSize(pixels, target.PixelWidth, target.PixelHeight, width, height), width, height)
                : null;
        }
        catch (Exception exception) when (exception is InvalidOperationException or ArgumentException or
            System.Runtime.InteropServices.COMException)
        {
            // 렌더러가 거절하면 캡션만 빠집니다. 사진은 그대로 나갑니다.
            return null;
        }
        finally
        {
            host.Children.Remove(box);
        }
    }
}
