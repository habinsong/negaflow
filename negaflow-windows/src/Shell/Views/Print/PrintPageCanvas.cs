using Negaflow.Shell.Print;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 인화 판 한 장의 화소 버퍼에 그리는 일입니다. 어디에 놓을지는
/// <see cref="PrintCompositionLayout"/> 이 정하고, 여기서는 그 자리에 칠하기만 합니다.
/// 판을 어떻게 굽는지(<see cref="PrintSheetEncoder"/>)와는 다른 이유로 바뀝니다.
/// </summary>
internal static class PrintPageCanvas
{
    /// <summary>BGRA8 한 장입니다. 종이 색으로 채워 시작합니다.</summary>
    public static byte[] NewPage(int width, int height, PrintSheetBackground background)
    {
        byte level = background switch
        {
            PrintSheetBackground.Black => 0x00,
            PrintSheetBackground.Gray => 0x80,
            _ => 0xFF,
        };
        byte[] page = new byte[checked(width * height * 4)];
        for (int index = 0; index < page.Length; index += 4)
        {
            page[index] = level;
            page[index + 1] = level;
            page[index + 2] = level;
            page[index + 3] = 0xFF;
        }
        return page;
    }

    public static void Fill(
        byte[] page,
        int width,
        int height,
        PrintRect rect,
        byte blue,
        byte green,
        byte red)
    {
        int left = Math.Max(0, (int)Math.Round(rect.X));
        int top = Math.Max(0, (int)Math.Round(rect.Y));
        int right = Math.Min(width, (int)Math.Round(rect.MaxX));
        int bottom = Math.Min(height, (int)Math.Round(rect.MaxY));
        for (int y = top; y < bottom; ++y)
        {
            int row = y * width * 4;
            for (int x = left; x < right; ++x)
            {
                int at = row + (x * 4);
                page[at] = blue;
                page[at + 1] = green;
                page[at + 2] = red;
                page[at + 3] = 0xFF;
            }
        }
    }

    /// <summary>
    /// 재단선 한 줄입니다. 가로나 세로로만 놓이므로 기울어진 선을 그릴 일이 없습니다 — macOS 도
    /// 칸 모서리에서 수평·수직으로만 뻗습니다.
    /// </summary>
    public static void DrawLine(
        byte[] page,
        int width,
        int height,
        PrintLineSegment segment,
        bool light)
    {
        byte level = light ? (byte)0xFF : (byte)0x00;
        int x0 = (int)Math.Round(Math.Min(segment.StartX, segment.EndX));
        int x1 = (int)Math.Round(Math.Max(segment.StartX, segment.EndX));
        int y0 = (int)Math.Round(Math.Min(segment.StartY, segment.EndY));
        int y1 = (int)Math.Round(Math.Max(segment.StartY, segment.EndY));
        // 한 화소 선은 눈에 잘 띄지 않습니다. macOS 와 같이 얇게 두되 최소 한 화소는 채웁니다.
        Fill(
            page,
            width,
            height,
            new PrintRect(x0, y0, Math.Max(1, x1 - x0), Math.Max(1, y1 - y0)),
            level,
            level,
            level);
    }

    /// <summary>
    /// 캡션 글자를 판에 얹습니다. 글자 화소의 알파로 섞으므로 글자 둘레가 종이 색과 자연스럽게
    /// 이어집니다 — 알파를 무시하면 글자마다 네모난 상자가 남습니다.
    /// </summary>
    public static async Task DrawCaptionAsync(
        byte[] page,
        int pageWidth,
        int pageHeight,
        Microsoft.UI.Xaml.Controls.Panel textHost,
        string text,
        PrintRect rect,
        PrintPackageCaptionAlignment alignment,
        bool light)
    {
        int width = Math.Max(1, (int)Math.Round(rect.Width));
        int height = Math.Max(1, (int)Math.Round(rect.Height));
        if (await PrintTextRasterizer.RenderAsync(textHost, text, width, height, alignment, light)
            is not { } rendered)
        {
            return;
        }
        int left = (int)Math.Round(rect.X);
        int top = (int)Math.Round(rect.Y);
        for (int y = 0; y < rendered.Height; ++y)
        {
            int pageY = top + y;
            if (pageY < 0 || pageY >= pageHeight)
            {
                continue;
            }
            for (int x = 0; x < rendered.Width; ++x)
            {
                int pageX = left + x;
                if (pageX < 0 || pageX >= pageWidth)
                {
                    continue;
                }
                int from = ((y * rendered.Width) + x) * 4;
                byte alpha = rendered.Pixels[from + 3];
                if (alpha == 0)
                {
                    continue;
                }
                int to = ((pageY * pageWidth) + pageX) * 4;
                for (int channel = 0; channel < 3; ++channel)
                {
                    page[to + channel] = (byte)(
                        ((rendered.Pixels[from + channel] * alpha) +
                            (page[to + channel] * (255 - alpha))) / 255);
                }
            }
        }
    }

    /// <summary>
    /// 현상된 사진을 그 자리에 놓습니다. 크기 맞추기는 <b>WIC 가</b> 합니다 — 직접 재표본화하면
    /// 내보내기의 긴 변 축소와 다른 결과가 나옵니다.
    /// </summary>
    public static async Task<bool> BlitAsync(
        byte[] page,
        int pageWidth,
        int pageHeight,
        string sourcePath,
        PrintRect rect,
        int quarterTurns)
    {
        int width = Math.Max(1, (int)Math.Round(rect.Width));
        int height = Math.Max(1, (int)Math.Round(rect.Height));
        // 돌려 놓을 자리라면 원본을 돌린 뒤의 크기로 뽑아야 합니다.
        bool turned = quarterTurns % 2 != 0;
        BitmapTransform transform = new()
        {
            ScaledWidth = (uint)(turned ? height : width),
            ScaledHeight = (uint)(turned ? width : height),
            InterpolationMode = BitmapInterpolationMode.Fant,
            // macOS `PrintPackageRenderer.placedImage` 는 `CGAffineTransform(a:0,b:1,c:-1,d:0)`
            // 을 turns 번 겹칩니다 — Core Image 의 y-up 에서 <b>반시계</b> 90° 입니다. WIC 은
            // 시계 방향으로만 셈하므로 같은 결과가 되는 각을 씁니다(반시계 90° = 시계 270°).
            // 앞 판은 시계 방향으로 돌려 macOS 와 정확히 180° 어긋난 사진을 냈습니다.
            Rotation = (quarterTurns % 4) switch
            {
                1 => BitmapRotation.Clockwise270Degrees,
                2 => BitmapRotation.Clockwise180Degrees,
                3 => BitmapRotation.Clockwise90Degrees,
                _ => BitmapRotation.None,
            },
        };

        using IRandomAccessStream stream =
            await PrintSheetFile.OpenAsync(sourcePath, FileAccess.Read);
        BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
        PixelDataProvider pixels = await decoder.GetPixelDataAsync(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Ignore,
            transform,
            ExifOrientationMode.IgnoreExifOrientation,
            ColorManagementMode.DoNotColorManage);
        byte[] tile = pixels.DetachPixelData();
        if (tile.Length < width * height * 4)
        {
            return false;
        }

        int left = (int)Math.Round(rect.X);
        int top = (int)Math.Round(rect.Y);
        for (int y = 0; y < height; ++y)
        {
            int pageY = top + y;
            if (pageY < 0 || pageY >= pageHeight)
            {
                continue;
            }
            int sourceRow = y * width * 4;
            int pageRow = pageY * pageWidth * 4;
            for (int x = 0; x < width; ++x)
            {
                int pageX = left + x;
                if (pageX < 0 || pageX >= pageWidth)
                {
                    continue;
                }
                int from = sourceRow + (x * 4);
                int to = pageRow + (pageX * 4);
                page[to] = tile[from];
                page[to + 1] = tile[from + 1];
                page[to + 2] = tile[from + 2];
                page[to + 3] = 0xFF;
            }
        }
        return true;
    }
}
