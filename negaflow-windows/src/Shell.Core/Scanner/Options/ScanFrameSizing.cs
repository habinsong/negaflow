using Negaflow.Interop;

namespace Negaflow.Shell;

/// <summary>수동 비율 값을 바꾼 결과입니다.</summary>
public enum CustomFrameRatioUpdate
{
    /// <summary>비율로 쓸 수 없거나 어떤 필름 폭으로도 스캐너 영역에 들어가지 않습니다.</summary>
    Rejected,

    /// <summary>지금 적용된 값과 같습니다.</summary>
    Unchanged,

    /// <summary>받았습니다.</summary>
    Changed,
}

/// <summary>
/// 프레임 규격 선택지의 규칙입니다. 목록의 규격 하나이거나, 목록에 없는 필름용 수동 비율입니다.
/// macOS <c>AppModel+ScanFrameSize</c> 를 그대로 옮겼습니다. 상태를 들지 않고 옵션을 받아
/// 새 옵션을 돌려주므로, 세션은 결과를 적용하고 알리기만 합니다.
/// </summary>
internal static class ScanFrameSizing
{
    /// <summary>
    /// 배치·비율 맞춤·시뮬레이터가 쓰는 치수입니다. 수동 비율이면 그 비율을 기억해 둔 필름
    /// 폭에 맞춰 세웁니다. 비율 맞춤은 비율만 보므로 사용자가 그린 크기는 그대로 둡니다.
    /// macOS <c>scanFrameSize</c>.
    /// </summary>
    internal static FlatbedFrameDimensions Current(ScanOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);
        return options.UsesCustomFrameRatio && options.CustomFrameRatio is { } ratio
            ? ratio.SizeAt(options.CustomFrameAcrossMm)
            : FilmFrameFormats.Dimensions(options.FrameFormat);
    }

    /// <summary>
    /// 자동 검출이 대어 볼 크기입니다. 규격은 하나, 수동 비율은 스캐너 영역에 들어가는 필름
    /// 폭마다 하나입니다. macOS <c>scanFrameSizeCandidates</c>.
    /// </summary>
    internal static IReadOnlyList<FlatbedFrameDimensions> Candidates(
        ScanOptions options,
        ScannerPluginCapabilities? capabilities)
    {
        ArgumentNullException.ThrowIfNull(options);
        if (!options.UsesCustomFrameRatio || options.CustomFrameRatio is not { } ratio)
        {
            return [FilmFrameFormats.Dimensions(options.FrameFormat)];
        }
        FlatbedFrameDimensions[] fitting = [.. ratio.CandidateSizes
            .Where(size => Fits(size, capabilities))];
        return fitting.Length == 0 ? [Current(options)] : fitting;
    }

    /// <summary>
    /// 규격으로 바꿉니다. 목록에 없거나 이미 그 규격이면 <see langword="null"/> 입니다.
    /// macOS <c>selectScanFrameFormat(_:)</c>.
    /// </summary>
    internal static ScanOptions? SelectPreset(
        ScanOptions options,
        FlatbedFrameFormat format,
        IReadOnlyList<FlatbedFrameFormat> available)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(available);
        if (!available.Contains(format) ||
            (!options.UsesCustomFrameRatio && options.FrameFormat == format))
        {
            return null;
        }
        return options with { FrameFormat = format, UsesCustomFrameRatio = false };
    }

    /// <summary>
    /// 수동 비율로 바꿉니다. 처음이면 지금 고른 규격의 비율로 채워 거기서 고치게 합니다.
    /// macOS <c>selectCustomScanFrameSize()</c>.
    /// </summary>
    internal static ScanOptions? SelectCustom(
        ScanOptions options,
        IReadOnlyList<FlatbedFrameFormat> available)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(available);
        if (options.UsesCustomFrameRatio || available.Count == 0)
        {
            return null;
        }
        ScanOptions next = options;
        if (options.CustomFrameRatio is null)
        {
            FlatbedFrameDimensions preset = FilmFrameFormats.Dimensions(options.FrameFormat);
            next = next with
            {
                CustomFrameRatio = FilmFrameRatio.Create(preset.AlongMm, preset.AcrossMm),
                CustomFrameAcrossMm = preset.Is35mm
                    ? FilmFrameRatio.CandidateAcrossMm[0]
                    : FilmFrameRatio.CandidateAcrossMm[1],
            };
        }
        return next with { UsesCustomFrameRatio = true };
    }

    /// <summary>
    /// 수동 비율 값을 바꿉니다. 비율로 쓸 수 없거나 어떤 필름 폭으로도 스캐너 영역에 들어가지
    /// 않으면 받지 않습니다. macOS <c>updateScanCustomFrameRatio(width:height:)</c>.
    /// </summary>
    internal static (CustomFrameRatioUpdate Result, ScanOptions Options) UpdateCustom(
        ScanOptions options,
        double width,
        double height,
        ScannerPluginCapabilities? capabilities)
    {
        ArgumentNullException.ThrowIfNull(options);
        if (FilmFrameRatio.Create(width, height) is not { } ratio ||
            FittingAcrossMm(ratio, options, capabilities) is not { } fittingAcross)
        {
            return (CustomFrameRatioUpdate.Rejected, options);
        }
        if (ratio == options.CustomFrameRatio)
        {
            return (CustomFrameRatioUpdate.Unchanged, options);
        }
        return (CustomFrameRatioUpdate.Changed, options with
        {
            CustomFrameRatio = ratio,
            CustomFrameAcrossMm = fittingAcross,
        });
    }

    /// <summary>
    /// 수동 비율이 새 스캐너 영역에 들어가지 않으면 규격으로 돌아갑니다. macOS
    /// <c>clampScanFrameFormatSelection()</c> 의 수동 비율 갈래입니다 — 규격 목록이 비면
    /// macOS 도 거기서 멈추므로 손대지 않습니다.
    /// </summary>
    internal static ScanOptions ClampCustom(
        ScanOptions options,
        ScannerPluginCapabilities? capabilities,
        IReadOnlyList<FlatbedFrameFormat> available)
    {
        ArgumentNullException.ThrowIfNull(options);
        ArgumentNullException.ThrowIfNull(available);
        return available.Count > 0 && options.UsesCustomFrameRatio &&
            capabilities?.PhysicalScanAreaBounds is not null &&
            !Fits(Current(options), capabilities)
            ? options with { UsesCustomFrameRatio = false }
            : options;
    }

    /// <summary>
    /// 스캐너 최대 영역에 들어가는지입니다. 최대 영역을 모르면 들어가지 않는 것으로 봅니다
    /// (macOS <c>scanFrameFits</c>).
    /// </summary>
    internal static bool Fits(
        FlatbedFrameDimensions frame,
        ScannerPluginCapabilities? capabilities) =>
        capabilities?.PhysicalScanAreaBounds?.Maximum is { } maximum &&
        FilmFrameFormats.Fits(frame, maximum.WidthMm, maximum.HeightMm);

    /// <summary>지금 쓰던 필름 폭이 들어가면 그대로, 아니면 들어가는 첫 필름 폭입니다.</summary>
    private static double? FittingAcrossMm(
        FilmFrameRatio ratio,
        ScanOptions options,
        ScannerPluginCapabilities? capabilities)
    {
        double[] fitting = [.. ratio.CandidateSizes
            .Where(size => Fits(size, capabilities))
            .Select(size => size.AcrossMm)];
        return fitting.Contains(options.CustomFrameAcrossMm)
            ? options.CustomFrameAcrossMm
            : fitting.Length > 0 ? fitting[0] : null;
    }
}
