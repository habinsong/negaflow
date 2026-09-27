using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>
/// 위치 지정이 안 되는 장치(필름 스캐너)의 스캔 영역입니다. macOS <c>selectedHardwareScanArea</c>
/// 와 그것을 다루는 <c>applyFixedScannerArea(for:)</c> · <c>clampHardwareScanAreaSelection()</c> ·
/// <c>resolvedHardwareScanArea(for:)</c> 를 옮겼습니다.
/// </summary>
/// <remarks>
/// 예전 Windows 는 이 상태가 없어 필름 스캐너는 늘 판 최대 영역을 스캔했습니다 — 규격(예: 24×18)이나
/// 수동 비율을 골라도 스캔 영역이 바뀌지 않았습니다. macOS 는 그 크기로 가운데를 잡습니다.
/// </remarks>
internal static class ScanHardwareArea
{
    /// <summary>
    /// macOS <c>applyFixedScannerArea(for:)</c> — 프레임 크기를 최대 영역 가운데에 놓습니다. 위치를
    /// 지정할 수 있는 장치(평판)나 최대 영역을 모르는 장치는 <see langword="null"/> 입니다.
    /// </summary>
    internal static ScannerPluginScanArea? Fixed(
        ScannerPluginCapabilities? capabilities,
        FlatbedFrameDimensions frame)
    {
        if (capabilities is null || capabilities.SupportsPositionedScanArea ||
            capabilities.PhysicalScanAreaBounds is not { } bounds)
        {
            return null;
        }
        ScannerPluginScanArea maximum = bounds.Maximum;
        return capabilities.ClampedPhysicalScanArea(new ScannerPluginScanArea(
            maximum.OriginXmm + Math.Max(0, (maximum.WidthMm - frame.AlongMm) / 2),
            maximum.OriginYmm + Math.Max(0, (maximum.HeightMm - frame.AcrossMm) / 2),
            frame.AlongMm,
            frame.AcrossMm));
    }

    /// <summary>
    /// macOS <c>clampHardwareScanAreaSelection()</c> · <c>resolvedHardwareScanArea(for:)</c> —
    /// 고른 영역(없으면 최대 영역)을 장치 격자에 맞춥니다. 최대 영역을 모르면 <see langword="null"/>.
    /// </summary>
    internal static ScannerPluginScanArea? Clamp(
        ScannerPluginCapabilities? capabilities,
        ScannerPluginScanArea? selected) =>
        capabilities?.PhysicalScanAreaBounds is { } bounds
            ? capabilities.ClampedPhysicalScanArea(selected ?? bounds.Maximum)
            : null;

    /// <summary>
    /// 규격·수동 비율이 바뀌었거나 성능을 새로 읽은 뒤입니다. 고정 영역 장치면 스캔 영역을 그
    /// 크기로 맞춥니다(macOS <c>applyScanFrameSizeChange</c> · <c>clampScanFrameFormatSelection</c>).
    /// </summary>
    internal static ScanOptions AfterFrameSizeChange(
        ScanOptions options,
        ScannerPluginCapabilities? capabilities)
    {
        ArgumentNullException.ThrowIfNull(options);
        return Fixed(capabilities, ScanFrameSizing.Current(options)) is { } area
            ? options with { HardwareScanArea = area }
            : options;
    }
}
