using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 장치 × 필름의 채널 밀도 범위(R·G·B 곱, 기하평균 1)입니다. macOS
/// <c>DevelopParameters.channelRange</c> 와 같은 뜻이고, 프레임이 잰 "모양"과 롤이 정한 "교정값"이
/// 같은 형식입니다.
/// </summary>
public readonly record struct ChannelRangeRgb(double Red, double Green, double Blue);

/// <summary>
/// 자동 밸런스 OFF 의 고정 반전은 세 채널에 같은 밀도 범위를 쓰므로 장치·필름이 정하는 실제 채널
/// 범위비만큼 회색이 기웁니다. 렌더가 프레임마다 한 번 잰 모양을 같은 롤(없으면 같은 스캔 폴더)에서
/// 모아 채널별 ln 중앙값 하나로 정하는 규칙입니다. macOS <c>ChannelRangeCalibration</c> 과 같은
/// 규칙·같은 상수입니다(작성자 카탈로그 실측: 묶음마다 ln(B/R) 중앙값이 0.23~0.61 로 다르고, 같은 묶음
/// 안 프레임 사이 강건 σ 는 0.02~0.11 이었습니다).
/// </summary>
public static class ChannelRangeCalibration
{
    /// <summary>채널 곱으로 받아들이는 범위입니다. 이 밖은 측정 실패로 보고 버립니다.</summary>
    public const double MinimumMultiplier = 0.5;

    public const double MaximumMultiplier = 2.0;

    /// <summary>교정을 정하는 데 필요한 최소 프레임 수입니다.</summary>
    public const int MinimumFrameCount = 3;

    /// <summary>
    /// 프레임 측정값의 허용 흩어짐(채널별 ln 의 강건 σ = 1.4826·MAD)입니다. 실측 묶음 안의 값은
    /// 0.02~0.11 이었고, 서로 다른 필름이 섞인 묶음은 이보다 크게 벌어집니다. 설계 선택이며
    /// 측정으로 검증한 경계는 아닙니다.
    /// </summary>
    public const double MaximumSpread = 0.20;

    /// <summary>유한하고 양수이며 허용 범위 안일 때만 돌려주고 기하평균 1 로 맞춥니다.</summary>
    public static ChannelRangeRgb? Sanitized(ChannelRangeRgb value)
    {
        if (!double.IsFinite(value.Red) || !double.IsFinite(value.Green) || !double.IsFinite(value.Blue) ||
            value.Red <= 0.0 || value.Green <= 0.0 || value.Blue <= 0.0)
        {
            return null;
        }
        double geometric = Math.Cbrt(value.Red * value.Green * value.Blue);
        ChannelRangeRgb normalized = new(value.Red / geometric, value.Green / geometric, value.Blue / geometric);
        return InRange(normalized.Red) && InRange(normalized.Green) && InRange(normalized.Blue)
            ? normalized
            : null;
    }

    /// <summary>
    /// 여러 프레임의 측정을 하나로 합칩니다. 채널별 ln 중앙값이라 한 프레임(하늘 독점 장면 등)이
    /// 끌고 가지 못합니다. 표본이 <see cref="MinimumFrameCount"/> 미만이거나 프레임 사이 흩어짐이
    /// <see cref="MaximumSpread"/> 를 넘으면(필름이 섞였을 가능성) null 입니다.
    /// </summary>
    public static ChannelRangeRgb? Combine(IEnumerable<ChannelRangeRgb> measurements)
    {
        ArgumentNullException.ThrowIfNull(measurements);
        List<ChannelRangeRgb> valid = [];
        foreach (ChannelRangeRgb measurement in measurements)
        {
            if (Sanitized(measurement) is { } sanitized)
            {
                valid.Add(sanitized);
            }
        }
        if (valid.Count < MinimumFrameCount)
        {
            return null;
        }
        double[] center = new double[3];
        for (int channel = 0; channel < 3; channel++)
        {
            double[] logs = valid.Select(value => Math.Log(Channel(value, channel))).ToArray();
            double middle = Median(logs);
            double spread = 1.4826 * Median(logs.Select(log => Math.Abs(log - middle)).ToArray());
            if (spread > MaximumSpread)
            {
                return null;
            }
            center[channel] = middle;
        }
        return Sanitized(new ChannelRangeRgb(
            Math.Exp(center[0]), Math.Exp(center[1]), Math.Exp(center[2])));
    }

    internal static JsonArray ToJson(ChannelRangeRgb value) => new(value.Red, value.Green, value.Blue);

    private static bool InRange(double value) => value is >= MinimumMultiplier and <= MaximumMultiplier;

    private static double Channel(ChannelRangeRgb value, int channel) =>
        channel switch { 0 => value.Red, 1 => value.Green, _ => value.Blue };

    private static double Median(double[] values)
    {
        double[] sorted = [.. values.Order()];
        int middle = sorted.Length / 2;
        return sorted.Length % 2 == 0 ? 0.5 * (sorted[middle - 1] + sorted[middle]) : sorted[middle];
    }
}
