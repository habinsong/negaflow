using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// macOS GrainMend 검토 슬라이더(0.7...6.0)를 네이티브 검출기의 정규 감도로 옮깁니다.
/// 이 값은 검토 중 재검출에만 쓰며, 수락한 region 마스크가 유일한 영속 결과입니다.
/// </summary>
public static class GrainMendSensitivity
{
    public const double Minimum = 0.7;
    public const double Maximum = 6.0;
    public const double Default = Maximum;

    public static double Clamp(double value) =>
        !double.IsFinite(value) ? Default : Math.Clamp(value, Minimum, Maximum);

    public static GrainMendDetectionOptions ToDetectionOptions(
        double sliderValue,
        bool automatic,
        bool detectMicroSpecks = true)
    {
        double normalized = (Clamp(sliderValue) - Minimum) / (Maximum - Minimum);
        return new GrainMendDetectionOptions(
            normalized,
            Math.Min(1.0, normalized + 0.1),
            0.6,
            automatic,
            detectMicroSpecks);
    }
}
