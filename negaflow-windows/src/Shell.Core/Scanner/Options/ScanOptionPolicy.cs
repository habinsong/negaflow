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

    /// <summary>
    /// macOS <c>AppModel.usesFlatbedRegionWorkflow</c> —
    /// <c>supportsPositionedScanArea &amp;&amp; supportsPreview &amp;&amp; physicalScanAreaBounds != nil</c>.
    /// </summary>
    internal static bool UsesFlatbedRegionWorkflow(ScannerPluginCapabilities? capabilities) =>
        capabilities is { SupportsPositionedScanArea: true, SupportsPreview: true } &&
        capabilities.PhysicalScanAreaBounds is not null;

    /// <summary>
    /// 프레임 규격 고르개에 넣을 목록입니다. macOS <c>AppModel.availableScanFrameFormats</c> 를
    /// 그대로 옮겼습니다.
    ///
    /// macOS 는 <c>supportsPositionedScanArea != true || supportsPreview</c> 라는 조건을
    /// 하나 더 겁니다. **영역을 지정할 수 있는데 프리뷰가 없는 장치**는 판 위 어디에 필름이
    /// 있는지 볼 방법이 없어 프레임 규격을 고르게 해 봐야 소용이 없기 때문입니다. 이 조건이
    /// 빠져 있으면 그런 장치에서 Windows 만 프레임 UI 가 뜹니다.
    ///
    /// 목록이 비면 프레임 규격·프레임 찾기·선택 줄이 통째로 사라집니다 — OpticFilm 8100 같은
    /// 35mm 전용 필름 스캐너가 그 경우입니다.
    /// </summary>
    internal static IReadOnlyList<FlatbedFrameFormat> AvailableFrameFormats(
        ScannerPluginCapabilities? capabilities)
    {
        // macOS: `guard let capabilities,
        // capabilities.supportsPositionedScanArea != true || capabilities.supportsPreview,
        // let maximum = hardwareScanAreaBounds?.maximum else { return [] }`
        //
        // 판 크기를 **모르면 빈 목록**입니다. `FilmFrameFormats.Available` 은 null 을 받으면
        // 전체 목록을 내주므로 여기서 그대로 넘기면 정반대가 됩니다 — 판 크기를 안 내는
        // 35mm 전용 필름 스캐너에서 Windows 만 프레임 규격 줄이 뜹니다.
        if (capabilities is null ||
            (capabilities.SupportsPositionedScanArea && !capabilities.SupportsPreview) ||
            capabilities.PhysicalScanAreaBounds is not { } bounds)
        {
            return [];
        }
        return FilmFrameFormats.Available(bounds.Maximum.WidthMm, bounds.Maximum.HeightMm);
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
        // macOS `clampScannerChoices()` 와 같은 규칙입니다. 목록의 마지막(=최대) 값을 쓰면
        // 50dpi 부터 12800dpi 까지 내는 평판에서 기본값이 12800 으로 튑니다.
        int resolution = resolutions.Contains(options.ResolutionDpi)
            ? options.ResolutionDpi
            : PreferredScanResolution(
                  resolutions,
                  capabilities?.SupportsPositionedScanArea == true) ?? 0;
        int depth = depths.Contains(options.BitDepth)
            ? options.BitDepth
            : depths.Contains(16) ? 16 : depths.Count > 0 ? depths[0] : 0;
        string mode = modes.Contains(options.ColorMode)
            ? options.ColorMode
            : modes.Contains(ColorModeColor) ? ColorModeColor
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

    /// <summary>macOS 필름 스캔 기본 해상도 목표값(<c>targetScanDPI</c>)입니다.</summary>
    internal const int TargetScanDpi = 3600;

    /// <summary>
    /// macOS <c>targetFlatbedScanDPI</c> — 평판은 목록 상단이 필름에서 분해되지 않습니다.
    /// </summary>
    internal const int TargetFlatbedScanDpi = 2400;

    /// <summary>
    /// macOS <c>targetFlatbedPreviewDPI</c> — 프리뷰는 그 위에서 프레임을 잡는 작업면입니다.
    /// </summary>
    internal const int TargetFlatbedPreviewDpi = 300;

    /// <summary>macOS <c>preferredScanResolution(in:isFlatbed:)</c>.</summary>
    internal static int? PreferredScanResolution(IReadOnlyList<int> resolutions, bool isFlatbed) =>
        NearestSupportedResolution(isFlatbed ? TargetFlatbedScanDpi : TargetScanDpi, resolutions);

    /// <summary>macOS <c>preferredFlatbedPreviewResolution(in:)</c>.</summary>
    internal static int? PreferredFlatbedPreviewResolution(IReadOnlyList<int> resolutions) =>
        NearestSupportedResolution(TargetFlatbedPreviewDpi, resolutions);

    /// <summary>
    /// macOS <c>nearestSupportedResolution(to:in:)</c> — 목표 dpi 에 가장 가까운 지원 값이고,
    /// 거리가 같으면 큰 쪽입니다.
    /// </summary>
    internal static int? NearestSupportedResolution(int dpi, IReadOnlyList<int> resolutions)
    {
        ArgumentNullException.ThrowIfNull(resolutions);
        int? best = null;
        foreach (int candidate in resolutions)
        {
            if (candidate <= 0)
            {
                continue;
            }
            if (candidate == dpi)
            {
                return candidate;
            }
            if (best is not { } current)
            {
                best = candidate;
                continue;
            }
            int candidateDistance = Math.Abs(candidate - dpi);
            int currentDistance = Math.Abs(current - dpi);
            if (candidateDistance < currentDistance ||
                (candidateDistance == currentDistance && candidate > current))
            {
                best = candidate;
            }
        }
        return best;
    }

    /// <summary>
    /// macOS <c>ScanArea.fullFrame35mm</c> — 장치가 판 크기를 내지 않을 때 쓰는 기본 영역입니다.
    /// 플러그인 계약은 <c>scanArea</c> 를 필수로 요구하므로 비워 보낼 수 없습니다.
    /// </summary>
    internal static ScannerPluginScanArea FullFrame35mm { get; } = new(0.0, 0.0, 36.0, 24.0);

    /// <summary>
    /// macOS <c>resolvedHardwareScanArea(for:)</c> — 판 최대 영역을 장치 격자에 맞춰 접습니다.
    /// </summary>
    internal static ScannerPluginScanArea? ResolvedHardwareScanArea(
        ScannerPluginCapabilities capabilities)
    {
        ArgumentNullException.ThrowIfNull(capabilities);
        return capabilities.PhysicalScanAreaBounds is not { } bounds
            ? null
            : capabilities.ClampedPhysicalScanArea(bounds.Maximum);
    }

    /// <summary>
    /// 지금 옵션으로 플러그인에 보낼 요청입니다. macOS <c>AppModel+PreviewScanning</c> ·
    /// <c>AppModel+FullScanPlan</c> 이 <c>ScanOptions</c> 를 채우는 차례를 그대로 따릅니다.
    /// </summary>
    /// <remarks>
    /// <para>
    /// <c>scanArea</c> 는 <b>비울 수 없습니다.</b> 플러그인 protocol v2 는 이것을 필수 객체로
    /// 읽고, 없으면 요청 JSON 자체가 파싱에서 떨어져 호스트에는 프로세스 실패로만 보입니다.
    /// macOS 의 <c>ScanOptions.scanArea</c> 도 옵셔널이 아니라 <c>.fullFrame35mm</c> 기본값을
    /// 가진 값 타입입니다.
    /// </para>
    /// <para>
    /// 본 스캔은 <c>outputRawTIFF=true</c> 만 받습니다. 프리뷰는 <c>false</c> 이되,
    /// 평판 영역 워크플로의 프리뷰는 양수 dpi 로 나가므로 계약상 <c>true</c> 여야 합니다.
    /// </para>
    /// </remarks>
    internal static ScannerPluginScanRequest? BuildRequest(
        ScannerPluginDevice? device,
        ScannerPluginCapabilities? capabilities,
        ScanOptions options,
        bool preview,
        string destinationVisiblePath,
        FlatbedScanRegion? region,
        FlatbedPreviewArea previewArea,
        ImageRotation rotation)
    {
        ArgumentNullException.ThrowIfNull(options);
        if (device is null || capabilities is null)
        {
            return null;
        }

        IReadOnlyList<int> depths = BitDepths(capabilities);
        IReadOnlyList<string> modes = ColorModes(capabilities);
        bool flatbed = UsesFlatbedRegionWorkflow(capabilities);
        int resolutionDpi;
        int bitDepth;
        string colorMode;
        bool outputRawTiff;
        ScannerPluginScanArea scanArea;

        if (preview)
        {
            // macOS: 프로필 없는 8bit TIFF 는 감마 인코딩으로 읽히므로 16bit 를 먼저 청합니다.
            bitDepth = depths.Contains(16) ? 16 : depths.Contains(8) ? 8 : options.BitDepth;
            colorMode = modes.Contains(ColorModeColor) ? ColorModeColor : options.ColorMode;
            scanArea = capabilities.PhysicalScanAreaBounds is { } bounds
                ? bounds.Maximum
                : FullFrame35mm;
            resolutionDpi = 0;
            outputRawTiff = false;
            if (flatbed &&
                PreferredFlatbedPreviewResolution(capabilities.ResolutionsDpi) is { } previewDpi)
            {
                resolutionDpi = previewDpi;
                outputRawTiff = true;
            }
        }
        else
        {
            resolutionDpi = options.ResolutionDpi;
            bitDepth = options.BitDepth;
            colorMode = options.ColorMode;
            outputRawTiff = true;
            // 프레임 자리는 프리뷰 안의 비율입니다. 프리뷰가 담은 영역을 자로 써서
            // 판 기준 밀리미터로 되돌립니다 - macOS 도 `unitRect` 를 프리뷰 영역으로
            // 환산해 하드웨어에 보냅니다.
            ScannerPluginScanArea? requested = flatbed ? region?.ToScanArea(previewArea) : null;
            scanArea = requested is not null
                ? capabilities.ClampedPhysicalScanArea(requested) ?? requested
                : ResolvedHardwareScanArea(capabilities) ?? FullFrame35mm;
        }

        // wire 의 `preview` 는 **화면의 의도가 아니라 해상도를 따릅니다.** macOS 도
        // `opts.resolution == .preview ? startPreviewScan : startFullScan` 으로 갈라,
        // 해상도를 명시한 평판 프리뷰는 저해상도 **본 스캔**으로 나갑니다. 플러그인 계약이
        // `preview=true` 에 dpi 0 과 `outputRawTIFF=false` 를 함께 요구하기 때문입니다.
        // 프리뷰로 다루는 것은 결과뿐이고, 그 판단은 부르는 쪽(`ScanRunCoordinator`)이 합니다.
        return new ScannerPluginScanRequest(
            device,
            capabilities,
            DevelopProcesses.From(options.FilmType, isDigitalSource: false),
            resolutionDpi,
            bitDepth,
            colorMode,
            Preview: resolutionDpi == 0,
            !preview && options.Infrared && capabilities.SupportsInfrared &&
                AllowsInfrared(options.FilmType),
            MultiExposure: false,
            ScanArea: scanArea,
            OutputRawTiff: outputRawTiff,
            destinationVisiblePath,
            Rotation: preview ? ImageRotation.Degrees0 : rotation);
    }
}
