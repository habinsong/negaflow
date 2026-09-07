using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>완성된 인화 판 한 장을 게시한 결과입니다.</summary>
/// <param name="Status">
/// 0 이면 파일이 올라갔습니다. 그 밖의 값은 native 의 <c>PrintSheetPublishStatus</c> 이며
/// 이름은 <see cref="PrintSheetPublishStatusName.For(uint)"/> 가 답니다.
/// </param>
/// <param name="BitsPerSample">
/// 파일이 <b>실제로</b> 담은 심도입니다. 고른 형식이 아니라 인코더가 쓴 값이므로, 16-bit 를
/// 골랐는데 8-bit 가 나오는 일을 여기서 잡습니다.
/// </param>
public readonly record struct PrintSheetPublishOutcome(
    uint Status,
    uint NativeErrorCode,
    uint BitsPerSample,
    uint ColorProfileBytes,
    ulong ArtifactBytes,
    bool Published)
{
    public bool IsSuccess => Status == 0U && Published;
}

/// <summary>native <c>PrintSheetPublishStatus</c> 의 이름입니다. 실패 줄에 적습니다.</summary>
public static class PrintSheetPublishStatusName
{
    private static readonly string[] Names =
    [
        "ok",
        "invalid_dimensions",
        "invalid_format",
        "buffer_size_mismatch",
        "memory_limit_exceeded",
        "com_apartment_mismatch",
        "wic_unavailable",
        "destination_profile_unavailable",
        "destination_profile_invalid",
        "destination_exists",
        "staging_create_failed",
        "encoder_initialization_failed",
        "unexpected_encoder",
        "pixel_format_coerced",
        "encode_failed",
        "flush_failed",
        "publish_failed",
        "published_file_invalid",
    ];

    public static string For(uint status) =>
        status < (uint)Names.Length ? Names[status] : "unknown_print_sheet_publish_status";
}

/// <summary>
/// 인화 판을 파일로 굽는 유일한 자리입니다.
/// </summary>
/// <remarks>
/// <para>
/// **WinRT <c>BitmapEncoder</c> 로는 ICC 를 못 답니다.** 그 형에는 색 문맥을 받는 자리가
/// 없어서, 앞 판은 랩이 고른 프로파일 안의 화소를 sRGB 로 읽히는 파일에 담아 내보냈습니다.
/// 엔진 쪽은 이미 <c>IWICBitmapFrameEncode::SetColorContexts</c> 로 현상 내보내기의 ICC 를
/// 달고 있으므로 같은 자리를 씁니다.
/// </para>
/// <para>
/// 화소는 <b>16-bit 그대로</b> 넘깁니다. 판을 BGRA8 로 합성하던 앞 판은 16-bit TIFF/PNG 를
/// 골라도 8-bit 로 양자화된 판을 냈습니다.
/// </para>
/// </remarks>
public static unsafe partial class NativePrintSheetPublisher
{
    private const string LibraryName = NativeMethods.LibraryName;

    [StructLayout(LayoutKind.Sequential)]
    private struct RequestV1
    {
        internal uint StructSize;
        internal uint Format;
        internal char* DestinationPath;
        internal ushort* Samples;
        internal ulong SampleCount;
        internal uint Width;
        internal uint Height;
        internal uint StrideBytes;
        internal uint OutputDpi;
        internal float JpegQuality;
        internal uint TiffCompression;
        internal byte* OutputIccProfile;
        internal uint OutputIccProfileSize;
        internal uint Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ResultV1
    {
        internal uint StructSize;
        internal uint Status;
        internal uint NativeErrorCode;
        internal uint CleanupErrorCode;
        internal uint BitsPerSample;
        internal uint ColorProfileBytes;
        internal ulong ArtifactBytes;
        internal uint Published;
        internal uint Reserved;
    }

    [LibraryImport(LibraryName, EntryPoint = "nf_publish_print_sheet_v1")]
    [UnmanagedCallConv(CallConvs = [typeof(CallConvCdecl)])]
    private static partial uint nf_publish_print_sheet_v1(RequestV1* request, ResultV1* result);

    /// <summary>
    /// 3 채널 RGB16 판을 고른 형식으로 씁니다. <paramref name="page"/> 는 행마다
    /// <c>width * 3</c> 개씩 놓인 코드값이며 이미 게시할 색공간 안에 있습니다.
    /// </summary>
    public static PrintSheetPublishOutcome Publish(
        string destination,
        ReadOnlySpan<ushort> page,
        int width,
        int height,
        DevelopExportFormat format,
        int dpi,
        double jpegQuality = 1.0,
        DevelopTiffCompression tiffCompression = DevelopTiffCompression.Lzw,
        ReadOnlySpan<byte> outputIccProfile = default)
    {
        ArgumentException.ThrowIfNullOrEmpty(destination);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        ResultV1 result = new() { StructSize = (uint)sizeof(ResultV1) };
        fixed (char* destinationPath = destination)
        fixed (ushort* samples = page)
        fixed (byte* profile = outputIccProfile)
        {
            RequestV1 request = new()
            {
                StructSize = (uint)sizeof(RequestV1),
                Format = (uint)format,
                DestinationPath = destinationPath,
                Samples = samples,
                SampleCount = (ulong)page.Length,
                Width = (uint)width,
                Height = (uint)height,
                StrideBytes = (uint)(width * 3 * sizeof(ushort)),
                OutputDpi = dpi > 0 ? (uint)dpi : 0U,
                JpegQuality = (float)Math.Clamp(jpegQuality, 0.0, 1.0),
                TiffCompression = (uint)tiffCompression,
                OutputIccProfile = outputIccProfile.Length >= 128 ? profile : null,
                OutputIccProfileSize = outputIccProfile.Length >= 128
                    ? (uint)outputIccProfile.Length
                    : 0U,
                Reserved = 0U,
            };
            uint status = nf_publish_print_sheet_v1(&request, &result);
            if (status != 0U)
            {
                // ABI 자체가 요청을 거절했습니다. 게시 상태로 섞지 않습니다 - 그쪽 값은
                // 인코더가 답한 것이고 이것은 인자 검사입니다.
                return new PrintSheetPublishOutcome(
                    Status: 2U, NativeErrorCode: status, BitsPerSample: 0U,
                    ColorProfileBytes: 0U, ArtifactBytes: 0UL, Published: false);
            }
        }
        return new PrintSheetPublishOutcome(
            result.Status,
            result.NativeErrorCode,
            result.BitsPerSample,
            result.ColorProfileBytes,
            result.ArtifactBytes,
            result.Published != 0U);
    }
}
