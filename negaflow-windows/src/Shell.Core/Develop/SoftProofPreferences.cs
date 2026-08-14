using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 소프트 프루프는 <em>보기</em>용 시뮬레이션입니다. macOS 처럼 앱 전체에 하나만 있고,
/// 미리보기에만 걸리며 게시하는 파일에는 들어가지 않습니다 — 인화물은 시뮬레이션을 담지
/// 않습니다.
/// </summary>
public sealed record SoftProofPreferences
{
    public bool IsEnabled { get; init; }

    /// <summary>프로파일만 볼지, 용지 흰색과 검정 잉크까지 흉내 낼지입니다.</summary>
    public SoftProofSimulation Simulation { get; init; } = SoftProofSimulation.ProfileOnly;

    /// <summary>
    /// 색역을 벗어나는 화소를 표시할지입니다. 표시할 수 있는지는 출력 프로파일이 정하므로,
    /// 이 값이 켜져 있어도 실제로 보이지 않을 수 있습니다.
    /// </summary>
    public bool GamutWarningEnabled { get; init; }

    /// <summary>
    /// 고른 ICC 프로파일의 이름입니다. 비어 있으면 내보내기 색공간의 이름을 씁니다 —
    /// 프루프 대상이 곧 게시할 공간이기 때문입니다.
    /// </summary>
    public string ProfileName { get; init; } = string.Empty;

    public SoftProofPreferences Normalize() => this with
    {
        Simulation = Enum.IsDefined(Simulation) ? Simulation : SoftProofSimulation.ProfileOnly,
        ProfileName = (ProfileName ?? string.Empty).Trim(),
        // 프루프가 꺼져 있으면 색역 경고도 의미가 없습니다. 켤 때 함께 살아납니다.
        GamutWarningEnabled = IsEnabled && GamutWarningEnabled,
    };

    /// <summary>
    /// 미리보기에 넘길 값입니다. 꺼져 있으면 <see cref="SoftProofSettings.Disabled"/> 이며,
    /// 그 결과는 프루프를 도입하기 전과 바이트 단위로 같습니다.
    /// </summary>
    public SoftProofSettings ToSettings(SoftProofMedia? media) =>
        !IsEnabled
            ? SoftProofSettings.Disabled
            : media is null
                // 프로파일을 아직 읽지 못했으면 용지·잉크를 흉내 내지 않습니다. 없는 값을
                // 지어내느니 프로파일만 보는 쪽이 정직합니다.
                ? new SoftProofSettings(
                    true,
                    SoftProofSimulation.ProfileOnly,
                    SoftProofRgb.White,
                    SoftProofRgb.Black,
                    GamutWarningEnabled)
                : new SoftProofSettings(
                    true,
                    Simulation,
                    media.PaperWhite,
                    media.BlackInk,
                    GamutWarningEnabled);
}
