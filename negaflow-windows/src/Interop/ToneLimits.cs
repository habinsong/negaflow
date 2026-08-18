using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeToneLimitsV1
{
    internal uint StructSize;
    internal float MaximumExposureStops;
    internal float MaximumToneControl;
    internal float MaximumEndpointToneControl;
    internal double MinimumFilmEmulationIntensity;
    internal double MaximumFilmEmulationIntensity;
}

/// <summary>
/// 엔진의 validator 가 실제로 허용하는 범위입니다.
/// </summary>
/// <remarks>
/// 이 값을 관리 쪽에 상수로 베껴 두면, 엔진이 범위를 바꾼 날 UI 는 여전히 옛 범위를 제시하고
/// 사용자는 엔진이 거부할 값을 고를 수 있게 됩니다. 그래서 숫자를 물어봅니다.
/// </remarks>
public sealed record ToneLimits(
    float MaximumExposureStops,
    float MaximumToneControl,
    float MaximumEndpointToneControl,
    double MinimumFilmEmulationIntensity,
    double MaximumFilmEmulationIntensity)
{
    public static unsafe ToneLimits Read()
    {
        NativeToneLimitsV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeToneLimitsV1);

        uint status = NativeLimits.nf_get_tone_limits_v1(ref raw);
        if (status != 0)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_get_tone_limits_v1 failed with status {status}.");
        }
        if (!float.IsFinite(raw.MaximumExposureStops) ||
            raw.MaximumExposureStops <= 0 ||
            !float.IsFinite(raw.MaximumToneControl) ||
            raw.MaximumToneControl <= 0 ||
            !float.IsFinite(raw.MaximumEndpointToneControl) ||
            raw.MaximumEndpointToneControl < raw.MaximumToneControl ||
            !double.IsFinite(raw.MinimumFilmEmulationIntensity) ||
            !double.IsFinite(raw.MaximumFilmEmulationIntensity) ||
            raw.MinimumFilmEmulationIntensity >= raw.MaximumFilmEmulationIntensity)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native engine reported tone limits that cannot bound a control.");
        }

        return new ToneLimits(
            raw.MaximumExposureStops,
            raw.MaximumToneControl,
            raw.MaximumEndpointToneControl,
            raw.MinimumFilmEmulationIntensity,
            raw.MaximumFilmEmulationIntensity);
    }

    public double ClampExposure(double value) =>
        double.IsFinite(value)
            ? Math.Clamp(value, -MaximumExposureStops, MaximumExposureStops)
            : 0.0;

    public double ClampFilmEmulationIntensity(double value) =>
        double.IsFinite(value)
            ? Math.Clamp(
                value,
                MinimumFilmEmulationIntensity,
                MaximumFilmEmulationIntensity)
            : MinimumFilmEmulationIntensity;

    /// <summary>
    /// 흰색 계열 / 검정 계열 전용입니다. macOS <c>DevelopToneRange.whites</c>·<c>blacks</c> 가
    /// <c>-2...2</c> 라 나머지 톤 컨트롤(±1)보다 넓습니다 — 끝점(백점·흑점) 제어라 ±1 로는
    /// 밀리지 않는 장면이 있습니다.
    /// </summary>
    public double ClampEndpointToneControl(double value) =>
        double.IsFinite(value)
            ? Math.Clamp(value, -MaximumEndpointToneControl, MaximumEndpointToneControl)
            : 0.0;

    public double ClampToneControl(double value) =>
        double.IsFinite(value)
            ? Math.Clamp(value, -MaximumToneControl, MaximumToneControl)
            : 0.0;
}
