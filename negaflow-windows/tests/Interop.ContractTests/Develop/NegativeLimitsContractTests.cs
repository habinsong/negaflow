using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class NegativeLimitsContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        NegativeLimits limits = NegativeLimits.Read();

        context.Check(limits.MinimumManualDmin > 0, "negative_limits_minimum_positive");
        context.Check(
            limits.MinimumManualDmin < limits.MaximumManualDmin,
            "negative_limits_range");
        context.Check(
            limits.ClampChannel(limits.MaximumManualDmin * 10) == limits.MaximumManualDmin,
            "negative_limits_clamps_high");
        context.Check(limits.ClampChannel(-1.0) == limits.MinimumManualDmin, "negative_limits_clamps_low");
        context.Check(limits.ClampChannel(double.NaN) == limits.MinimumManualDmin, "negative_limits_nan");

        // 톤 한계와 달리 엔진은 범위를 벗어난 dmin 을 **거부하지 않고 조용히 clamp** 합니다.
        // 그래서 "범위를 넘으면 거부된다" 는 대칭 확인을 여기서 할 수 없습니다. 대신 clamp 를
        // 지난 값이 develop 단계까지 도달하는지를 봅니다.
        string absentSource = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-base-limit-{Guid.NewGuid():N}.tif");
        DevelopExportResult atLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-base-limit.png"),
            DminRed = (float)limits.ClampChannel(double.MaxValue),
            DminGreen = (float)limits.ClampChannel(double.MinValue),
            DminBlue = (float)limits.ClampChannel(0.25),
        });
        context.Check(
            atLimit.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "negative_limits_clamped_values_pass_validation");
    }
}
