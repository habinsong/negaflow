using System;

namespace Negaflow.Interop;

/// <summary>
/// 프루프가 무엇을 흉내 내는지입니다.
/// </summary>
public enum SoftProofSimulation
{
    /// <summary>프로파일 공간에서 보여주기만 합니다. 값은 바뀌지 않습니다.</summary>
    ProfileOnly = 0,

    /// <summary>용지 흰색과 잉크 검정까지 흉내 냅니다. 값이 바뀝니다.</summary>
    PaperAndBlackInk = 1,
}

/// <summary>
/// 채널별 계수입니다. 색도 변환이 아니라 D50 대비 비율이고, 이것이 macOS 가 하는 계산입니다.
/// </summary>
public readonly record struct SoftProofRgb(double Red, double Green, double Blue)
{
    public static SoftProofRgb White => new(1.0, 1.0, 1.0);

    public static SoftProofRgb Black => new(0.0, 0.0, 0.0);
}

/// <summary>
/// 목적지 프로파일에서 읽어낸 것입니다.
/// </summary>
/// <remarks>
/// <see cref="IsRgbOutputProfile"/> 이 false 인 프로파일은 프루프 목적지로 쓸 수 없습니다 —
/// CMYK 인쇄 프로파일이나 입력 전용 스캐너 프로파일이 여기에 걸립니다. 고르는 시점과 복원하는
/// 시점이 같은 관문을 쓰도록, 이 판정을 그대로 사용하십시오.
/// </remarks>
public sealed class SoftProofMedia
{
    internal SoftProofMedia(
        bool isRgbOutputProfile,
        bool hasWhite,
        bool hasBlack,
        SoftProofRgb paperWhite,
        SoftProofRgb blackInk)
    {
        IsRgbOutputProfile = isRgbOutputProfile;
        HasWhite = hasWhite;
        HasBlack = hasBlack;
        PaperWhite = paperWhite;
        BlackInk = blackInk;
    }

    public bool IsRgbOutputProfile { get; }

    public bool HasWhite { get; }

    public bool HasBlack { get; }

    /// <summary>측정된 흰색이 없으면 중립 흰색입니다.</summary>
    public SoftProofRgb PaperWhite { get; }

    /// <summary>측정된 검정이 없으면 0 입니다.</summary>
    public SoftProofRgb BlackInk { get; }
}

/// <summary>
/// 한 번의 미리보기에 실리는 프루프 설정입니다.
/// </summary>
/// <remarks>
/// 현상 레시피가 아닙니다. 내보내기에는 이 값을 받을 자리가 없고, 그것이 인화물이 보기용
/// 시뮬레이션을 담지 못하도록 하는 구조적 보장입니다.
/// </remarks>
public sealed class SoftProofSettings
{
    public static readonly SoftProofSettings Disabled = new(
        false,
        SoftProofSimulation.ProfileOnly,
        SoftProofRgb.White,
        SoftProofRgb.Black);

    public SoftProofSettings(
        bool isEnabled,
        SoftProofSimulation simulation,
        SoftProofRgb paperWhite,
        SoftProofRgb blackInk,
        bool warnOutOfGamut = false)
    {
        IsEnabled = isEnabled;
        Simulation = simulation;
        PaperWhite = paperWhite;
        BlackInk = blackInk;
        WarnOutOfGamut = warnOutOfGamut;
    }

    /// <summary>프로파일에서 읽은 용지와 잉크로 프루프를 켭니다.</summary>
    public static SoftProofSettings From(SoftProofMedia media, SoftProofSimulation simulation)
    {
        ArgumentNullException.ThrowIfNull(media);
        return new SoftProofSettings(true, simulation, media.PaperWhite, media.BlackInk);
    }

    public bool IsEnabled { get; }

    public SoftProofSimulation Simulation { get; }

    public SoftProofRgb PaperWhite { get; }

    public SoftProofRgb BlackInk { get; }

    /// <summary>
    /// 출력 공간이 재현하지 못하는 화소를 미리보기 위에 표시할지입니다. 판정은 ICM 이 하며,
    /// 하지 못하면 아무것도 표시하지 않습니다 — 근사하면 macOS 와 다른 화소가 표시됩니다.
    /// </summary>
    public bool WarnOutOfGamut { get; }
}

/// <summary>
/// ICC 프로파일에서 용지와 잉크를 읽습니다.
/// </summary>
public static unsafe class NativeSoftProof
{
    private const uint StatusOk = 0;
    private const uint StatusInvalidArgument = 1;
    private const uint StatusStructTooSmall = 2;

    /// <summary>
    /// 프로파일을 읽는 것은 태그 테이블을 도는 일이므로, 프로파일을 고를 때 한 번만 부르고
    /// 결과를 들고 있으십시오. 프레임마다 다시 부를 이유가 없습니다.
    /// </summary>
    public static SoftProofMedia ReadMedia(ReadOnlySpan<byte> iccProfile)
    {
        NativeSoftProofMediaV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeSoftProofMediaV1);
        uint status;
        fixed (byte* bytes = iccProfile)
        {
            status = NativeColorProof.nf_read_soft_proof_media_v1(
                bytes,
                checked((uint)iccProfile.Length),
                &raw);
        }

        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                status switch
                {
                    StatusInvalidArgument =>
                        "nf_read_soft_proof_media_v1 rejected the arguments.",
                    StatusStructTooSmall =>
                        "nf_read_soft_proof_media_v1 rejected the struct size.",
                    _ => $"nf_read_soft_proof_media_v1 failed with status {status}.",
                });
        }

        return new SoftProofMedia(
            raw.IsRgbOutputProfile != 0U,
            raw.HasWhite != 0U,
            raw.HasBlack != 0U,
            new SoftProofRgb(raw.PaperWhiteRgb[0], raw.PaperWhiteRgb[1], raw.PaperWhiteRgb[2]),
            new SoftProofRgb(raw.BlackInkRgb[0], raw.BlackInkRgb[1], raw.BlackInkRgb[2]));
    }
}
