using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

internal static class ScanOptionPolicy
{
    internal const string ColorModeColor = "color";
    internal const string ColorModeGray = "gray";
    internal const int MinimumSelectableScanDpi = 600;
    internal const int MaximumBatchCount = 12;

    internal static bool UsesFlatbedRegionWorkflow(ScannerPluginCapabilities? capabilities) =>
        capabilities is { SupportsPositionedScanArea: true, SupportsPreview: true } &&
        capabilities.MaxScanWidthMm is not null &&
        capabilities.MaxScanHeightMm is not null;

    /// <summary>
    /// 프레임 규격 고르개에 넣을 목록입니다. macOS <c>AppModel.availableScanFrameFormats</c> 를
    /// 그대로 옮겼습니다.
    ///
    /// ☠️ macOS 는 <c>supportsPositionedScanArea != true || supportsPreview</c> 라는 조건을
    ///    하나 더 겁니다. **영역을 지정할 수 있는데 프리뷰가 없는 장치**는 판 위 어디에 필름이
    ///    있는지 볼 방법이 없어 프레임 규격을 고르게 해 봐야 소용이 없기 때문입니다. 이 조건이
    ///    빠져 있으면 그런 장치에서 Windows 만 프레임 UI 가 뜹니다.
    ///
    /// 목록이 비면 프레임 규격·프레임 찾기·선택 줄이 통째로 사라집니다 — OpticFilm 8100 같은
    /// 35mm 전용 필름 스캐너가 그 경우입니다.
    /// </summary>
    internal static IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats(
        ScannerPluginCapabilities? capabilities)
    {
        // macOS: `guard let capabilities,
        //             capabilities.supportsPositionedScanArea != true || capabilities.supportsPreview,
        //             let maximum = hardwareScanAreaBounds?.maximum else { return [] }`
        //
        // ☠️ 판 크기를 **모르면 빈 목록**입니다. `FilmFrameFormats.Available` 은 null 을 받으면
        //    전체 목록을 내주므로 여기서 그대로 넘기면 정반대가 됩니다 — 판 크기를 안 내는
        //    35mm 전용 필름 스캐너에서 Windows 만 프레임 규격 줄이 뜹니다.
        if (capabilities is null ||
            (capabilities.SupportsPositionedScanArea && !capabilities.SupportsPreview) ||
            capabilities.MaxScanWidthMm is not { } width ||
            capabilities.MaxScanHeightMm is not { } height)
        {
            return [];
        }
        return FilmFrameFormats.Available(width, height);
    }

    internal static IReadOnlyList<int> Resolutions(
        ScannerPluginCapabilities? capabilities,
        int selectedDpi)
    {
        IReadOnlyList<int> supported = capabilities?.ResolutionsDpi ?? [];
        int[] positive = [.. supported.Where(dpi => dpi > 0).Distinct().Order()];
        int[] usable = [.. positive.Where(dpi => dpi >= MinimumSelectableScanDpi)];
        if (usable.Length == 0)
        {
            return positive;
        }
        return usable.Contains(selectedDpi) || selectedDpi == 0
            ? usable
            : [.. usable.Append(selectedDpi).Order()];
    }

    internal static IReadOnlyList<int> BitDepths(ScannerPluginCapabilities? capabilities) =>
        [.. (capabilities?.BitDepths ?? []).Where(depth => depth > 0).Distinct().Order()];

    internal static IReadOnlyList<string> ColorModes(ScannerPluginCapabilities? capabilities) =>
        [.. (capabilities?.Modes ?? []).Where(mode =>
            string.Equals(mode, ColorModeColor, StringComparison.Ordinal) ||
            string.Equals(mode, ColorModeGray, StringComparison.Ordinal))];

    internal static bool HasUsableCapabilities(ScannerPluginCapabilities? capabilities) =>
        capabilities is not null &&
        capabilities.ResolutionsDpi.Any(dpi => dpi > 0) &&
        ColorModes(capabilities).Count > 0 &&
        BitDepths(capabilities).Count > 0;

    internal static bool AllowsInfrared(FilmType filmType) =>
        filmType is FilmType.ColorNegative or FilmType.ColorPositive;

    internal static ScanOptions Clamp(
        ScannerPluginCapabilities? capabilities,
        int currentSelectedDpi,
        ScanOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        IReadOnlyList<int> resolutions = Resolutions(capabilities, currentSelectedDpi);
        IReadOnlyList<int> depths = BitDepths(capabilities);
        IReadOnlyList<string> modes = ColorModes(capabilities);
        int resolution = resolutions.Contains(options.ResolutionDpi)
            ? options.ResolutionDpi
            : resolutions.Count > 0 ? resolutions[^1] : 0;
        int depth = depths.Contains(options.BitDepth)
            ? options.BitDepth
            : depths.Count > 0 ? depths[^1] : 0;
        string mode = modes.Contains(options.ColorMode)
            ? options.ColorMode
            : modes.Count > 0 ? modes[0] : ColorModeColor;
        bool infrared = options.Infrared &&
            capabilities?.SupportsInfrared == true &&
            AllowsInfrared(options.FilmType);
        IReadOnlyList<FlatbedFrameFormat> formats = AvailableFrameFormats(capabilities);
        return options with
        {
            FrameFormat = formats.Count == 0 || formats.Contains(options.FrameFormat)
                ? options.FrameFormat
                : formats[0],
            ResolutionDpi = resolution,
            BitDepth = depth,
            ColorMode = mode,
            Infrared = infrared,
            BatchCount = Math.Clamp(options.BatchCount, 1, MaximumBatchCount),
            FolderName = ExportNamingTemplate.SanitizeComponent(options.FolderName),
        };
    }

    internal static ScannerPluginScanRequest? BuildRequest(
        ScannerPluginDevice? device,
        ScannerPluginCapabilities? capabilities,
        ScanOptions options,
        bool preview,
        string destinationVisiblePath,
        FlatbedScanRegion? region,
        ImageRotation rotation)
    {
        if (device is null || capabilities is null)
        {
            return null;
        }

        return new ScannerPluginScanRequest(
            device,
            capabilities,
            DevelopProcesses.From(options.FilmType, isDigitalSource: false),
            preview ? 0 : options.ResolutionDpi,
            options.BitDepth,
            options.ColorMode,
            preview,
            !preview && options.Infrared,
            MultiExposure: false,
            ScanArea: preview ? null : region?.ToScanArea(),
            OutputRawTiff: false,
            destinationVisiblePath,
            Rotation: preview ? ImageRotation.Degrees0 : rotation);
    }
}
