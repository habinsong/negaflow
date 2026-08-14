using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Negaflow.Shell;

/// <summary>프리뷰 한 장의 밝기 값입니다. 자동 프레임 찾기가 이것으로 프레임을 셉니다.</summary>
public readonly record struct PreviewLuminance(float[] Values, uint Width, uint Height)
{
    public bool IsEmpty => Values.Length == 0 || Width == 0U || Height == 0U;

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
                new BitmapTransform { ScaledWidth = width, ScaledHeight = height },
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
            return new PreviewLuminance(luminance, width, height);
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
