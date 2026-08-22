using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Negaflow.Shell;

/// <summary>프리뷰 한 장의 밝기 값입니다. 자동 프레임 찾기가 이것으로 프레임을 셉니다.</summary>
/// <param name="PhysicalWidthMm">
/// 파일이 밝히는 가로 실제 크기(원본 픽셀 / 해상도 * 25.4)입니다. 해상도를 모르면 0 입니다.
/// macOS <c>FlatbedFrameGridDetector.physicalSizeMM(url:)</c> 자리이며, 프레임 찾기가
/// "36x24mm 가 몇 px 인가" 를 이 값으로 셉니다.
/// </param>
public readonly record struct PreviewLuminance(
    float[] Values,
    uint Width,
    uint Height,
    double PhysicalWidthMm = 0,
    double PhysicalHeightMm = 0)
{
    public bool IsEmpty => Values.Length == 0 || Width == 0U || Height == 0U;

    /// <summary>파일이 실제 크기를 밝혔는지입니다. 아니면 검출이 다른 단서로 물러납니다.</summary>
    public bool HasPhysicalSize =>
        double.IsFinite(PhysicalWidthMm) && double.IsFinite(PhysicalHeightMm) &&
        PhysicalWidthMm > 0 && PhysicalHeightMm > 0;

    public static PreviewLuminance None => new([], 0U, 0U);
}

/// <summary>
/// 프리뷰 스캔을 밝기 배열로 읽습니다. WIC(<c>BitmapDecoder</c>)가 TIFF 를 읽으므로 우리가
/// 디코더를 새로 만들지 않습니다.
/// </summary>
/// <remarks>
/// 검출기는 판 전체의 상대적인 밝기만 봅니다. 색 정확도가 필요 없으므로 8-bit BGRA 로 받아
/// Rec.709 휘도로 접습니다 — 여기서 16-bit 을 고집하면 프리뷰 한 장에 네 배의 메모리를 씁니다.
/// </remarks>
public static class PreviewLuminanceReader
{
    /// <summary>검출에 넘길 최대 긴 변입니다. 프리뷰는 이보다 클 이유가 없습니다.</summary>
    public const uint MaximumLongEdge = 2048;

    public static async Task<PreviewLuminance> ReadAsync(string path)
    {
        ArgumentException.ThrowIfNullOrEmpty(path);
        try
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(path);
            using IRandomAccessStream stream = await file.OpenAsync(FileAccessMode.Read);
            BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);

            uint width = decoder.PixelWidth;
            uint height = decoder.PixelHeight;
            if (width == 0U || height == 0U)
            {
                return PreviewLuminance.None;
            }
            // 실제 크기는 **줄이기 전** 픽셀과 해상도로 셉니다. 줄인 뒤 값으로 세면 같은
            // 그림이 갑자기 작아진 것처럼 보여 프레임 크기 후보가 통째로 어긋납니다.
            //
            // 1 dpi 같은 자리표시자는 크기를 모르는 것으로 봅니다 - macOS
            // `physicalSizeMM(url:)` 도 `dpiX > 1, dpiY > 1` 을 요구합니다. 96 은 WIC 이
            // 해상도 태그가 없을 때 넣는 기본값이라 함께 버립니다.
            double physicalWidthMm = decoder.DpiX > 1 && decoder.DpiX != 96
                ? width / decoder.DpiX * 25.4
                : 0;
            double physicalHeightMm = decoder.DpiY > 1 && decoder.DpiY != 96
                ? height / decoder.DpiY * 25.4
                : 0;
            PreviewTrace.Write(
                $"preview luminance {width}x{height} dpi={decoder.DpiX:F1}x{decoder.DpiY:F1} " +
                $"mm={physicalWidthMm:F1}x{physicalHeightMm:F1}");
            uint longEdge = Math.Max(width, height);
            if (longEdge > MaximumLongEdge)
            {
                double scale = (double)MaximumLongEdge / longEdge;
                width = Math.Max(1U, (uint)Math.Round(width * scale));
                height = Math.Max(1U, (uint)Math.Round(height * scale));
            }

            PixelDataProvider pixels = await decoder.GetPixelDataAsync(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                new BitmapTransform
                {
                    ScaledWidth = width,
                    ScaledHeight = height,
                    // WIC 의 기본 보간은 **최근접**입니다. 그대로 두면 줄일 때 화소를 골라
                    // 버려서 35mm 프레임 사이 2mm 여백이 통째로 사라집니다 - 실측(V700,
                    // 3슬롯 홀더 2906 -> 2048): 최근접 12컷(가운데 줄 전멸), Fant 18컷.
                    //
                    // macOS 는 `CGImageSourceCreateThumbnailAtIndex` 로 줄이며 그쪽도
                    // 필터를 겁니다. Fant 는 WIC 에서 축소용으로 가장 좋은 필터입니다.
                    InterpolationMode = BitmapInterpolationMode.Fant,
                },
                ExifOrientationMode.IgnoreExifOrientation,
                ColorManagementMode.DoNotColorManage);
            byte[] bgra = pixels.DetachPixelData();
            long expected = (long)width * height * 4L;
            if (bgra.LongLength < expected)
            {
                return PreviewLuminance.None;
            }

            float[] luminance = new float[(int)((long)width * height)];
            for (int index = 0; index < luminance.Length; ++index)
            {
                int at = index * 4;
                // Rec.709. 검출기는 상대 밝기만 보므로 sRGB 를 선형으로 되돌리지 않습니다.
                luminance[index] =
                    ((0.0722f * bgra[at]) +
                     (0.7152f * bgra[at + 1]) +
                     (0.2126f * bgra[at + 2])) / 255.0f;
            }
            return new PreviewLuminance(
                luminance, width, height, physicalWidthMm, physicalHeightMm);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException or
            System.Runtime.InteropServices.COMException)
        {
            // 읽지 못한 프리뷰는 없는 프리뷰입니다. 찾은 척하지 않습니다.
            return PreviewLuminance.None;
        }
    }
}
