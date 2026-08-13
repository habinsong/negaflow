using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 현상 프로세스 목록과 이름입니다. macOS <c>DevelopmentProcess</c> 와 같은 여섯 항목이며
/// 순서도 같습니다.
/// </summary>
/// <remarks>
/// 이름은 번역하지 않습니다 — C-41/E-6/D-76 은 실제 현상 공정의 규격 이름이고, macOS 도
/// 언어와 무관하게 그대로 씁니다.
/// </remarks>
public static class DevelopProcesses
{
    public static IReadOnlyList<DevelopmentProcess> All { get; } =
    [
        DevelopmentProcess.C41,
        DevelopmentProcess.E6,
        DevelopmentProcess.D76,
        DevelopmentProcess.BlackAndWhiteReversal,
        DevelopmentProcess.DigitalColor,
        DevelopmentProcess.DigitalBlackAndWhite,
    ];

    /// <summary>
    /// 저장된 film type 과 digital 표시에서 프로세스를 되읽습니다. macOS 와 같이 **디지털
    /// 표시는 포지티브에만** 있습니다 — 음화에 남아 있으면 필름으로 읽습니다.
    /// </summary>
    public static DevelopmentProcess From(FilmType filmType, bool isDigitalSource) =>
        (filmType, isDigitalSource) switch
        {
            (FilmType.ColorPositive, true) => DevelopmentProcess.DigitalColor,
            (FilmType.BlackAndWhitePositive, true) => DevelopmentProcess.DigitalBlackAndWhite,
            (FilmType.ColorPositive, _) => DevelopmentProcess.E6,
            (FilmType.BlackAndWhiteNegative, _) => DevelopmentProcess.D76,
            (FilmType.BlackAndWhitePositive, _) => DevelopmentProcess.BlackAndWhiteReversal,
            _ => DevelopmentProcess.C41,
        };

    public static string DisplayName(DevelopmentProcess process) => process switch
    {
        DevelopmentProcess.E6 => "E-6",
        DevelopmentProcess.D76 => "D-76",
        DevelopmentProcess.BlackAndWhiteReversal => "B&W Reversal",
        DevelopmentProcess.DigitalColor => "Digital Color",
        DevelopmentProcess.DigitalBlackAndWhite => "Digital B&W",
        _ => "C-41/ECN-2",
    };
}
