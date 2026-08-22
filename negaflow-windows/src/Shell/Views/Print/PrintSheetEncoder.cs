using Negaflow.Interop;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 완성된 판을 파일로 굽습니다. 배치·그리기와 다른 이유로 바뀌므로(포맷, 해상도 태그) 따로
/// 둡니다.
/// </summary>
internal static class PrintSheetEncoder
{
    /// <summary>내보낼 형식의 파일 확장자입니다.</summary>
    public static string ExtensionFor(DevelopExportFormat format) => format switch
    {
        DevelopExportFormat.Jpeg8 => ".jpg",
        DevelopExportFormat.Tiff16 => ".tif",
        _ => ".png",
    };

    /// <summary>
    /// 판을 고른 형식으로 씁니다. **해상도를 파일에 적습니다** — 인화소는 그 값으로 실제
    /// 크기를 정하므로, 빠뜨리면 300dpi 로 짠 판이 72dpi 로 인쇄됩니다.
    /// </summary>
    /// <remarks>
    /// 형식은 출력 탭에서 고른 것을 그대로 씁니다. macOS 도 인화 배치에
    /// <c>exportFormat</c> · <c>quickExportFormat</c> 을 그대로 넘깁니다 - 여기서 PNG 로
    /// 못 박으면 TIFF 를 골라도 PNG 가 나옵니다.
    /// </remarks>
    public static async Task<bool> EncodeAsync(
        string destination,
        byte[] page,
        int width,
        int height,
        int dpi,
        DevelopExportFormat format = DevelopExportFormat.Png16,
        double jpegQuality = 1.0)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination) ?? ".");
            using IRandomAccessStream stream =
                await PrintSheetFile.OpenAsync(destination, FileAccess.ReadWrite);
            stream.Size = 0;
            BitmapEncoder encoder = format == DevelopExportFormat.Jpeg8
                ? await BitmapEncoder.CreateAsync(
                    BitmapEncoder.JpegEncoderId,
                    stream,
                    [
                        new KeyValuePair<string, BitmapTypedValue>(
                            "ImageQuality",
                            new BitmapTypedValue(
                                (float)Math.Clamp(jpegQuality, 0.0, 1.0),
                                Windows.Foundation.PropertyType.Single)),
                    ])
                : await BitmapEncoder.CreateAsync(
                    format == DevelopExportFormat.Tiff16
                        ? BitmapEncoder.TiffEncoderId
                        : BitmapEncoder.PngEncoderId,
                    stream);
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Ignore,
                (uint)width,
                (uint)height,
                dpi,
                dpi,
                page);
            await encoder.FlushAsync();
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }
}
