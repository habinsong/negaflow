using Negaflow.Interop;

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
    /// <para>
    /// 굽는 일은 <b>네이티브 엔진</b>이 합니다. WinRT <c>BitmapEncoder</c> 에는 색 문맥을 받는
    /// 자리가 없어서, 앞 판은 랩이 고른 ICC 안의 화소를 프로파일 없이 내보냈습니다 — 파일을 받은
    /// 쪽은 그것을 sRGB 로 읽습니다. 엔진 쪽은 현상 내보내기에서 이미
    /// <c>IWICBitmapFrameEncode::SetColorContexts</c> 로 같은 일을 하고 있습니다.
    /// </para>
    /// <para>
    /// **워커에서 부릅니다.** 네이티브 WIC 는 <c>COINIT_MULTITHREADED</c> 를 걸므로 WinUI 의
    /// STA 스레드에서는 <c>com_apartment_mismatch</c> 로 물러납니다.
    /// </para>
    /// <para>
    /// 화소는 16-bit 그대로 넘어갑니다. 형식이 심도를 정합니다 — PNG·TIFF 는 16-bit, JPEG 만
    /// 8-bit 로 떨어뜨립니다.
    /// </para>
    /// </remarks>
    public static async Task<bool> EncodeAsync(
        string destination,
        ushort[] page,
        int width,
        int height,
        int dpi,
        DevelopExportFormat format = DevelopExportFormat.Png16,
        double jpegQuality = 1.0,
        byte[]? outputIccProfile = null,
        DevelopTiffCompression tiffCompression = DevelopTiffCompression.Lzw)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination) ?? ".");
        }
        catch (Exception error) when (
            error is IOException or UnauthorizedAccessException or ArgumentException)
        {
            ExportTrace.Write("print destination folder failed: " + error.GetType().Name);
            return false;
        }

        PrintSheetPublishOutcome outcome = await Task.Run(() =>
            NativePrintSheetPublisher.Publish(
                destination,
                page,
                width,
                height,
                format,
                dpi,
                jpegQuality,
                tiffCompression,
                outputIccProfile ?? []))
            .ConfigureAwait(true);

        if (outcome.IsSuccess)
        {
            ExportTrace.Write(
                $"    sheet published bits={outcome.BitsPerSample} " +
                $"icc={outcome.ColorProfileBytes} bytes={outcome.ArtifactBytes} " +
                $"path={destination}");
            return true;
        }
        // 어느 자리에서 멈췄는지 남깁니다. "쓰지 못했습니다" 만으로는 사용자가 할 수 있는 일이
        // 다시 눌러 보는 것밖에 없습니다.
        ExportTrace.Write(
            $"    sheet publish failed status={PrintSheetPublishStatusName.For(outcome.Status)} " +
            $"native=0x{outcome.NativeErrorCode:X} path={destination}");
        return false;
    }
}
