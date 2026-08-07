using System.Runtime.InteropServices;

namespace Negaflow.Interop;

[StructLayout(LayoutKind.Sequential)]
internal struct NativeNegativeLimitsV1
{
    internal uint StructSize;
    internal float MinimumManualDmin;
    internal float MaximumManualDmin;
}

/// <summary>
/// 수동 필름 base 가 들어갈 수 있는 범위입니다.
/// </summary>
/// <remarks>
/// 엔진은 범위를 벗어난 값을 **거부하지 않고 조용히 clamp** 합니다. 그래서 UI 가 숫자를 베껴
/// 두면 사용자가 고른 값과 실제로 쓰인 값이 달라지고, 거부보다 알아채기 어렵습니다. 물어봅니다.
/// </remarks>
public sealed record NegativeLimits(float MinimumManualDmin, float MaximumManualDmin)
{
    public static unsafe NegativeLimits Read()
    {
        NativeNegativeLimitsV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeNegativeLimitsV1);

        uint status = NativeMethods.nf_get_negative_limits_v1(ref raw);
        if (status != 0)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                $"nf_get_negative_limits_v1 failed with status {status}.");
        }
        if (!float.IsFinite(raw.MinimumManualDmin) ||
            !float.IsFinite(raw.MaximumManualDmin) ||
            raw.MinimumManualDmin <= 0 ||
            raw.MinimumManualDmin >= raw.MaximumManualDmin)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native engine reported a manual base range that cannot bound a control.");
        }

        return new NegativeLimits(raw.MinimumManualDmin, raw.MaximumManualDmin);
    }

    public double ClampChannel(double value) =>
        double.IsFinite(value)
            ? Math.Clamp(value, MinimumManualDmin, MaximumManualDmin)
            : MinimumManualDmin;
}
