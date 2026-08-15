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

        TextBlock block = new()
        {
            Text = text,
            // 칸 높이의 3분의 2 를 글자 높이로 씁니다. 칸을 꽉 채우면 위아래가 붙어 읽기
            // 어렵고, macOS 캡션도 여백을 남깁니다.
            FontSize = Math.Max(6, height * 2.0 / 3.0),
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
            Width = width,
            Height = height,
            VerticalAlignment = VerticalAlignment.Center,
        };

        host.Children.Add(block);
        try
        {
            block.Measure(new Windows.Foundation.Size(width, height));
            block.Arrange(new Windows.Foundation.Rect(0, 0, width, height));
            block.UpdateLayout();

            RenderTargetBitmap target = new();
            await target.RenderAsync(block, width, height);
            Windows.Storage.Streams.IBuffer buffer = await target.GetPixelsAsync();
            byte[] pixels = new byte[buffer.Length];
            using (Windows.Storage.Streams.DataReader reader =
                Windows.Storage.Streams.DataReader.FromBuffer(buffer))
            {
                reader.ReadBytes(pixels);
            }
            return pixels.Length >= target.PixelWidth * target.PixelHeight * 4
                ? (pixels, target.PixelWidth, target.PixelHeight)
                : null;
        }
        catch (Exception exception) when (exception is InvalidOperationException or
            System.Runtime.InteropServices.COMException)
        {
            // 렌더러가 거절하면 캡션만 빠집니다. 사진은 그대로 나갑니다.
            return null;
        }
        finally
        {
            host.Children.Remove(block);
        }
    }
}
