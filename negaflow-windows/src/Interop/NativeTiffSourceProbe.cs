using System.Runtime.InteropServices;

namespace Negaflow.Interop;

public readonly record struct TiffSourceMetadata(
    ulong FileBytes,
    uint PixelWidth,
    uint PixelHeight,
    ushort SamplesPerPixel,
    ushort BitsPerSample,
    ushort SampleFormat,
    ushort Orientation);

[StructLayout(LayoutKind.Sequential)]
internal struct NativeTiffSourceInfoV1
{
    internal uint StructSize;
    internal uint Status;
    internal uint PixelWidth;
    internal uint PixelHeight;
    internal ushort SamplesPerPixel;
    internal ushort BitsPerSample;
    internal ushort SampleFormat;
    internal ushort Orientation;
    internal ulong FileBytes;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeStandardImageSourceInfoV1
{
    internal uint StructSize;
    internal uint Status;
    internal uint PixelWidth;
    internal uint PixelHeight;
    internal ushort SamplesPerPixel;
    internal ushort BitsPerSample;
    internal ushort SampleFormat;
    internal ushort Orientation;
    internal ulong FileBytes;
}

public static unsafe class NativeTiffSourceProbe
{
    private const uint StatusOk = 0;
    private const uint ProbeOk = 0;

    public static bool TryRead(string sourcePath, out TiffSourceMetadata metadata)
    {
        metadata = default;
        if (string.IsNullOrWhiteSpace(sourcePath) || !Path.IsPathFullyQualified(sourcePath))
        {
            return false;
        }
        NativeTiffSourceInfoV1 result = default;
        result.StructSize = (uint)sizeof(NativeTiffSourceInfoV1);
        uint status;
        fixed (char* path = sourcePath)
        {
            status = NativeSourceProbe.nf_probe_tiff_source_v1(path, &result);
        }
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_probe_tiff_source_v1 failed with status {status}.");
        }
        if (result.Status != ProbeOk || result.FileBytes == 0 || result.PixelWidth == 0 ||
            result.PixelHeight == 0 || result.SamplesPerPixel == 0 || result.BitsPerSample == 0 ||
            result.SampleFormat == 0 || result.Orientation is < 1 or > 8)
        {
            return false;
        }
        metadata = new TiffSourceMetadata(
            result.FileBytes,
            result.PixelWidth,
            result.PixelHeight,
            result.SamplesPerPixel,
            result.BitsPerSample,
            result.SampleFormat,
            result.Orientation);
        return true;
    }
}

public static unsafe class NativeStandardImageSourceProbe
{
    private const uint StatusOk = 0;
    private const uint ProbeOk = 0;

    /// <remarks>
    /// 이 프로브만 WIC 로 파일을 엽니다(TIFF 쪽은 우리 파서입니다). STA 스레드에서 부르면 COM 이
    /// <c>RPC_E_CHANGED_MODE</c> 를 돌려주어 <b>멀쩡한 파일이 "읽을 수 없음" 으로 보입니다</b> —
    /// <see cref="NativeApartment"/> 주석 참고.
    /// </remarks>
    public static bool TryRead(string sourcePath, out TiffSourceMetadata metadata)
    {
        if (NativeApartment.IsSingleThreaded)
        {
            ProbeOutcome moved = NativeApartment.Run(() => ProbeOutcome.From(sourcePath));
            metadata = moved.Metadata;
            return moved.Read;
        }
        return Probe(sourcePath, out metadata);
    }

    private readonly record struct ProbeOutcome(bool Read, TiffSourceMetadata Metadata)
    {
        internal static ProbeOutcome From(string sourcePath) =>
            new(Probe(sourcePath, out TiffSourceMetadata metadata), metadata);
    }

    private static bool Probe(string sourcePath, out TiffSourceMetadata metadata)
    {
        metadata = default;
        if (string.IsNullOrWhiteSpace(sourcePath) || !Path.IsPathFullyQualified(sourcePath))
        {
            return false;
        }
        NativeStandardImageSourceInfoV1 result = default;
        result.StructSize = (uint)sizeof(NativeStandardImageSourceInfoV1);
        uint status;
        fixed (char* path = sourcePath)
        {
            status = NativeSourceProbe.nf_probe_standard_image_source_v1(path, &result);
        }
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_probe_standard_image_source_v1 failed with status {status}.");
        }
        if (result.Status != ProbeOk || result.FileBytes == 0 || result.PixelWidth == 0 ||
            result.PixelHeight == 0 || result.SamplesPerPixel != 4 || result.BitsPerSample != 16 ||
            result.SampleFormat != 1 || result.Orientation != 1)
        {
            return false;
        }
        metadata = new TiffSourceMetadata(
            result.FileBytes,
            result.PixelWidth,
            result.PixelHeight,
            result.SamplesPerPixel,
            result.BitsPerSample,
            result.SampleFormat,
            result.Orientation);
        return true;
    }
}
