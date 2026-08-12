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
            status = NativeMethods.nf_probe_tiff_source_v1(path, &result);
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
