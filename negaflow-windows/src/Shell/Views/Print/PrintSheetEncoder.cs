using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace Negaflow.Shell.Views;

/// <summary>
/// 완성된 판을 파일로 굽습니다. 배치·그리기와 다른 이유로 바뀌므로(포맷, 해상도 태그) 따로
/// 둡니다.
/// </summary>
internal static class PrintSheetEncoder
{
    /// <summary>
    /// 판을 PNG 로 씁니다. **해상도를 파일에 적습니다** — 인화소는 그 값으로 실제 크기를
    /// 정하므로, 빠뜨리면 300dpi 로 짠 판이 72dpi 로 인쇄됩니다.
    /// </summary>
    public static async Task<bool> EncodeAsync(
        string destination,
        byte[] page,
        int width,
        int height,
        int dpi)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination) ?? ".");
            using IRandomAccessStream stream =
                await PrintSheetFile.OpenAsync(destination, FileAccess.ReadWrite);
            stream.Size = 0;
            BitmapEncoder encoder = await BitmapEncoder.CreateAsync(
                BitmapEncoder.PngEncoderId,
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
