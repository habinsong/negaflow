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

    /// <summary>
    /// 고른 ICC 파일의 자리입니다. 이름만 담아 두면 다음 실행에서 용지 흰색과 잉크 검정을
    /// 다시 읽을 수 없어, 프루프가 "용지와 잉크" 를 골라도 중립 흰색으로 돌아갑니다.
    /// </summary>
    public string ProfilePath { get; init; } = string.Empty;

    /// <summary>
    /// 인화 대상이 쓰는 출력 프로파일의 자리입니다. macOS <c>printerOutputICCProfileData</c> 와
    /// 같은 뜻이며, 현상 대상이 PRINT 일 때 프루프 목적지를 이것으로 바꿉니다.
    /// </summary>
    public string PrinterProfilePath { get; init; } = string.Empty;

    public SoftProofPreferences Normalize() => this with
    {
        ProfilePath = (ProfilePath ?? string.Empty).Trim(),
        PrinterProfilePath = (PrinterProfilePath ?? string.Empty).Trim(),
        Simulation = Enum.IsDefined(Simulation) ? Simulation : SoftProofSimulation.ProfileOnly,
        ProfileName = (ProfileName ?? string.Empty).Trim(),
        // 색영역 경고는 프루프와 <b>별개의 스위치</b>입니다. macOS 도
        // `destinationGamutWarningEnabled` 를 따로 들고 있고, 프루프가 꺼져 있다고 이 값을
        // 끄지 않습니다 — 여기서 강제로 끄면 켬 단추를 눌러도 곧바로 되돌아가 아예 눌리지
        // 않는 것처럼 보입니다. 실제로 표시할 수 있는지는 출력 프로파일이 정합니다.

    };

    /// <summary>
    /// 현상 대상에 맞는 프루프 목적지입니다. macOS <c>displaySoftProofSettings</c> 와 같이,
    /// **PRINT 로 현상할 때는 프린터 출력 프로파일**이 목적지가 됩니다 — 인화할 종이가
    /// 목적지여야 프루프가 인화 결과를 보여 줍니다.
    /// </summary>
    public string DestinationProfilePath(Catalog.DevelopTarget target) =>
        target == Catalog.DevelopTarget.Print && PrinterProfilePath.Length > 0
            ? PrinterProfilePath
            : ProfilePath;

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
