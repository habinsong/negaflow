using Negaflow.Interop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 위치 지정이 안 되는 장치(필름 스캐너)의 스캔 영역입니다. macOS
/// <c>applyFixedScannerArea(for:)</c> · <c>clampHardwareScanAreaSelection()</c> ·
/// <c>resolvedHardwareScanArea(for:)</c> 와 같은 규칙인지 봅니다. 예전 Windows 는 이 상태가 없어
/// 규격이나 수동 비율을 골라도 필름 스캐너는 늘 최대 영역을 스캔했습니다.
/// </summary>
internal static class ScannerHardwareAreaTests
{
    internal static void Run()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "hardware-area-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        var session = new ScanSessionController(
            new FakeScannerGateway(Path.Combine(isolatedBase, "none")),
            new ScannerPluginTrustStore(Path.Combine(isolatedBase, "trust.json")),
            new ImmediateUiDispatcher());
        session.SetSimulatorEnabled(true);
        session.RefreshDevicesAsync().GetAwaiter().GetResult();
        // 시뮬레이터 필름 스캐너: 최대 영역 36×24, 위치 지정 불가.
        Check(!session.UsesFlatbedRegionWorkflow &&
              session.Capabilities?.SupportsPositionedScanArea == false,
            "hardware_area_film_scanner_is_fixed");
        Check(Is(session.Options.HardwareScanArea, 0, 0, 36, 24),
            "hardware_area_starts_at_the_frame_size",
            () => Describe(session.Options.HardwareScanArea));

        Check(session.SelectFrameFormat(FlatbedFrameFormat.HalfFrame35mm) &&
              Is(session.Options.HardwareScanArea, 9, 0, 18, 24),
            "hardware_area_centres_the_half_frame",
            () => Describe(session.Options.HardwareScanArea));
        Check(session.SelectCustomFrameRatio() &&
              session.UpdateCustomFrameRatio(4, 5) == CustomFrameRatioUpdate.Changed &&
              Is(session.Options.HardwareScanArea, 8.4, 0, 19.2, 24),
            "hardware_area_follows_the_custom_ratio",
            () => Describe(session.Options.HardwareScanArea));

        ScannerPluginScanRequest? full = session.BuildRequest(false, Path.Combine(isolatedBase, "a.tif"));
        ScannerPluginScanRequest? preview = session.BuildRequest(true, Path.Combine(isolatedBase, "p.tif"));
        Check(Is(full?.ScanArea, 8.4, 0, 19.2, 24), "hardware_area_reaches_the_full_scan",
            () => Describe(full?.ScanArea));
        Check(Is(preview?.ScanArea, 0, 0, 36, 24), "hardware_area_preview_keeps_the_whole_area",
            () => Describe(preview?.ScanArea));

        // 사용자가 고친 영역은 다른 옵션을 바꿔도 남고, 최대 영역 밖은 잘립니다.
        session.UpdateOptions(options => options with
        {
            HardwareScanArea = options.HardwareScanArea! with { WidthMm = 30 },
        });
        session.UpdateOptions(options => options with { BatchCount = 3 });
        Check(session.Options.HardwareScanArea?.WidthMm == 30, "hardware_area_keeps_user_edits",
            () => Describe(session.Options.HardwareScanArea));
        session.UpdateOptions(options => options with
        {
            HardwareScanArea = options.HardwareScanArea! with { WidthMm = 100 },
        });
        Check(Is(session.Options.HardwareScanArea, 0, 0, 36, 24),
            "hardware_area_is_clamped_to_the_device",
            () => Describe(session.Options.HardwareScanArea));

        // 평판(위치 지정 가능)은 프레임 자리로 스캔하므로 규격이 스캔 영역을 바꾸지 않습니다.
        session.SelectDeviceAsync(SimulatedScannerGateway.FlatbedScannerId).GetAwaiter().GetResult();
        ScannerPluginScanArea? before = session.Options.HardwareScanArea;
        _ = session.SelectFrameFormat(FlatbedFrameFormat.Medium66);
        Check(session.Options.HardwareScanArea == before, "hardware_area_flatbed_is_untouched",
            () => Describe(session.Options.HardwareScanArea));
    }

    private static bool Is(ScannerPluginScanArea? area, double x, double y, double width, double height) =>
        area is { } value &&
        Math.Abs(value.OriginXmm - x) < 1e-9 && Math.Abs(value.OriginYmm - y) < 1e-9 &&
        Math.Abs(value.WidthMm - width) < 1e-9 && Math.Abs(value.HeightMm - height) < 1e-9;

    private static string Describe(ScannerPluginScanArea? area) =>
        area is { } value
            ? $"{value.OriginXmm},{value.OriginYmm} {value.WidthMm}x{value.HeightMm}"
            : "none";
}
