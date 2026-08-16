using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class ToneLimitsContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        ToneLimits limits = ToneLimits.Read();

        // 값 자체를 여기에 다시 적으면 이 테스트가 바로 그 중복이 됩니다. 대신 이 값들이
        // 컨트롤을 실제로 묶을 수 있는 모양인지, 그리고 엔진이 거부하는 값을 clamp 가
        // 통과시키지 않는지를 봅니다.
        context.Check(limits.MaximumExposureStops > 0, "tone_limits_exposure_positive");
        context.Check(limits.MaximumToneControl > 0, "tone_limits_control_positive");
        context.Check(
            limits.MinimumFilmEmulationIntensity < limits.MaximumFilmEmulationIntensity,
            "tone_limits_intensity_range");

        context.Check(
            limits.ClampExposure(limits.MaximumExposureStops * 10) ==
                limits.MaximumExposureStops,
            "tone_limits_clamps_high_exposure");
        context.Check(
            limits.ClampExposure(-limits.MaximumExposureStops * 10) ==
                -limits.MaximumExposureStops,
            "tone_limits_clamps_low_exposure");
        context.Check(limits.ClampExposure(double.NaN) == 0.0, "tone_limits_clamps_nan");
        context.Check(
            limits.ClampToneControl(limits.MaximumToneControl * 10) ==
                limits.MaximumToneControl,
            "tone_limits_clamps_control");

        // clamp 를 지난 값은 엔진이 받아야 합니다. 받지 않으면 두 쪽이 어긋난 것입니다.
        string absentSource = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-tone-limit-{Guid.NewGuid():N}.tif");
        DevelopExportResult atLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-tone-limit.png"),
            ExposureStops = (float)limits.ClampExposure(double.MaxValue),
            Contrast = (float)limits.ClampToneControl(double.MaxValue),
            Density = (float)limits.ClampToneControl(double.MinValue),
            Highlight = (float)limits.ClampToneControl(double.MaxValue),
            Shadow = (float)limits.ClampToneControl(double.MinValue),
            Whites = (float)limits.ClampToneControl(double.MaxValue),
            Blacks = (float)limits.ClampToneControl(double.MinValue),
            Highlights = (float)limits.ClampToneControl(double.MinValue),
        });
        context.Check(
            atLimit.FailedStage == DevelopExportStage.ObserveSourceBefore,
            "tone_limits_clamped_values_pass_validation");

        // 반대로 범위를 넘으면 엔진이 거부해야 합니다. 그래야 위 확인이 의미를 가집니다.
        DevelopExportResult overLimit = NativeDevelopExporter.Run(new DevelopExportRequest
        {
            SourcePath = absentSource,
            DestinationPath = Path.Combine(Path.GetTempPath(), "negaflow-tone-limit.png"),
            ExposureStops = limits.MaximumExposureStops * 2,
        });
        context.Check(
            overLimit.FailedStage == DevelopExportStage.RequestValidation,
            "tone_limits_over_limit_is_rejected");
        context.Check(
            overLimit.FailureName == "invalid_tone_adjustment_parameter",
            "tone_limits_over_limit_reason");
    }
}
