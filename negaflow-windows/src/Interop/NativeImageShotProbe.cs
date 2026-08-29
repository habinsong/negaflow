using System.Runtime.InteropServices;

namespace Negaflow.Interop;

/// <summary>
/// 파일에 적힌 촬영 기록입니다. 카메라가 남긴 값만 담으며, 없는 태그는 <see langword="null"/>
/// 로 둡니다 — 지어내지 않습니다.
/// </summary>
/// <remarks>
/// macOS <c>SourceEXIFMetadata</c> 의 노출 네 값과 같은 자리입니다. 필름 카메라는 EXIF 를
/// 남기지 않으므로 스캐너 TIFF 에는 없고, 사용자가 가져온 디지털 원본에만 있습니다.
/// </remarks>
public readonly record struct ImageShotMetadata(
    int? IsoSpeed,
    double? ExposureTimeSeconds,
    double? FNumber,
    double? FocalLengthMm)
{
    public bool IsEmpty =>
        IsoSpeed is null && ExposureTimeSeconds is null && FNumber is null &&
        FocalLengthMm is null;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeImageShotInfoV1
{
    internal uint StructSize;
    internal uint Status;
    internal uint PresentMask;
    internal uint IsoSpeed;
    internal double ExposureTimeSeconds;
    internal double FNumber;
    internal double FocalLengthMm;
}

public static unsafe class NativeImageShotProbe
{
    private const uint StatusOk = 0;
    private const uint ProbeOk = 0;
    private const uint HasIsoSpeed = 0x1;
    private const uint HasExposureTime = 0x2;
    private const uint HasFNumber = 0x4;
    private const uint HasFocalLength = 0x8;

    /// <remarks>
    /// WIC 로 파일을 엽니다. STA 스레드에서 부르면 COM 이 <c>RPC_E_CHANGED_MODE</c> 를
    /// 돌려주어 <b>멀쩡한 파일이 "촬영 기록 없음" 으로 보입니다</b> — 크기 프로브와 같은
    /// 이유로 여기서도 아파트를 옮겨 부릅니다(<see cref="NativeApartment"/> 주석 참고).
    /// </remarks>
    public static bool TryRead(string sourcePath, out ImageShotMetadata shot)
    {
        if (NativeApartment.IsSingleThreaded)
        {
            ProbeOutcome moved = NativeApartment.Run(() => ProbeOutcome.From(sourcePath));
            shot = moved.Shot;
            return moved.Read;
        }
        return Probe(sourcePath, out shot);
    }

    private readonly record struct ProbeOutcome(bool Read, ImageShotMetadata Shot)
    {
        internal static ProbeOutcome From(string sourcePath) =>
            new(Probe(sourcePath, out ImageShotMetadata shot), shot);
    }

    private static bool Probe(string sourcePath, out ImageShotMetadata shot)
    {
        shot = default;
        if (string.IsNullOrWhiteSpace(sourcePath) || !Path.IsPathFullyQualified(sourcePath))
        {
            return false;
        }
        NativeImageShotInfoV1 result = default;
        result.StructSize = (uint)sizeof(NativeImageShotInfoV1);
        uint status;
        fixed (char* path = sourcePath)
        {
            status = NativeSourceProbe.nf_probe_image_shot_v1(path, &result);
        }
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_probe_image_shot_v1 failed with status {status}.");
        }
        if (result.Status != ProbeOk)
        {
            return false;
        }
        shot = new ImageShotMetadata(
            (result.PresentMask & HasIsoSpeed) != 0 ? (int)result.IsoSpeed : null,
            (result.PresentMask & HasExposureTime) != 0 ? result.ExposureTimeSeconds : null,
            (result.PresentMask & HasFNumber) != 0 ? result.FNumber : null,
            (result.PresentMask & HasFocalLength) != 0 ? result.FocalLengthMm : null);
        return true;
    }
}
