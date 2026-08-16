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

    internal static IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats(
        ScannerPluginCapabilities? capabilities) => capabilities is null
        ? []
        : FilmFrameFormats.Available(
            capabilities.MaxScanWidthMm,
            capabilities.MaxScanHeightMm);

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
