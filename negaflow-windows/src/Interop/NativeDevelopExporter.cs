namespace Negaflow.Interop;

/// <summary>
/// Drives the native develop-and-export pipeline across the C ABI.
/// </summary>
/// <remarks>
/// The call blocks for the whole develop, which on a full frame is far longer than a
/// UI frame. Callers on the WinUI thread must run it on a worker and marshal the
/// result back through a captured <c>DispatcherQueue</c>; this type deliberately
/// offers no async wrapper so that decision stays visible at the call site.
/// </remarks>
public static unsafe class NativeDevelopExporter
{
    internal const int RequestV1Size = 96;
    internal const int ResultV1Size = 136;
    internal const int RequestV2Size = 96;
    internal const int RequestV3Size = 112;
    internal const int RequestV4Size = 128;
    internal const int PointCurveV1Size = 1032;
    internal const int RequestV5Size = 4256;
    internal const int RequestV6Size = 4352;
    internal const int RequestV7Size = 4400;
    internal const int ResultV2Size = 152;

    private const uint StatusOk = 0;
    private const uint StatusInvalidArgument = 1;
    private const uint StatusStructTooSmall = 2;

    private static void ValidateLayoutAndEnums(DevelopExportRequest request)
    {
        if (sizeof(NativePointCurveV1) != PointCurveV1Size ||
            sizeof(NativeDevelopExportRequestV7) != RequestV7Size ||
            sizeof(NativeDevelopExportResultV2) != ResultV2Size)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The managed develop-export layout does not match the C ABI.");
        }
        if (!Enum.IsDefined(request.Format) ||
            !Enum.IsDefined(request.FilmType) ||
            !Enum.IsDefined(request.BaseEstimationMode) ||
            !Enum.IsDefined(request.FilmLookSourceKind) ||
            !Enum.IsDefined(request.FilmEmulation))
        {
            throw new ArgumentException(
                "The develop request carries a value outside its enumeration.",
                nameof(request));
        }
        ValidatePointCurves(request.PointCurves);
        ValidateColorMixer(request.ColorMixer);
        ValidateColorGrading(request.ColorGrading);
    }

    private static void ValidatePointCurves(DevelopPointCurves pointCurves)
    {
        ArgumentNullException.ThrowIfNull(pointCurves);
        ValidatePointCurve(pointCurves.Rgb, nameof(pointCurves.Rgb));
        ValidatePointCurve(pointCurves.Red, nameof(pointCurves.Red));
        ValidatePointCurve(pointCurves.Green, nameof(pointCurves.Green));
        ValidatePointCurve(pointCurves.Blue, nameof(pointCurves.Blue));
    }

    private static void ValidatePointCurve(
        IReadOnlyList<DevelopPointCurvePoint> points,
        string parameterName)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (points.Count > NativePointCurveV1.MaximumPoints)
        {
            throw new ArgumentException("A Point Curve channel has too many points.", parameterName);
        }

        double? previousX = null;
        foreach (DevelopPointCurvePoint point in points.OrderBy(point => point.X))
        {
            if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                point.X is < 0.0 or > 1.0 || point.Y is < 0.0 or > 1.0 ||
                previousX is { } x && point.X - x < 1.0e-9)
            {
                throw new ArgumentException("A Point Curve coordinate is invalid.", parameterName);
            }
            previousX = point.X;
        }
    }

    private static void CopyPointCurve(
        IReadOnlyList<DevelopPointCurvePoint> source,
        ref NativePointCurveV1 destination)
    {
        destination.PointCount = checked((uint)source.Count);
        destination.Reserved = 0;
        fixed (double* coordinates = destination.Coordinates)
        {
            int index = 0;
            foreach (DevelopPointCurvePoint point in source.OrderBy(point => point.X))
            {
                coordinates[index * 2] = point.X;
                coordinates[(index * 2) + 1] = point.Y;
                index++;
            }
        }
    }

    private static void ValidateColorMixer(DevelopColorMixer colorMixer)
    {
        ArgumentNullException.ThrowIfNull(colorMixer);
        ValidateColorMixerChannel(colorMixer.Hue, nameof(colorMixer.Hue));
        ValidateColorMixerChannel(colorMixer.Saturation, nameof(colorMixer.Saturation));
        ValidateColorMixerChannel(colorMixer.Luminance, nameof(colorMixer.Luminance));
    }

    private static void ValidateColorMixerChannel(IReadOnlyList<float> values, string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values);
        if (values.Count != DevelopColorMixer.BandCount ||
            values.Any(value => !float.IsFinite(value) || value is < -1.0F or > 1.0F))
        {
            throw new ArgumentException("A Color Mixer channel must contain eight finite values from -1 to 1.", parameterName);
        }
    }

    private static void CopyColorMixer(IReadOnlyList<float> source, ref NativeDevelopExportRequestV7 destination, int channel)
    {
        fixed (float* hue = destination.ColorMixerHue)
        fixed (float* saturation = destination.ColorMixerSaturation)
        fixed (float* luminance = destination.ColorMixerLuminance)
        {
            float* target = channel switch { 0 => hue, 1 => saturation, _ => luminance };
            for (int index = 0; index < DevelopColorMixer.BandCount; index++)
            {
                target[index] = source[index];
            }
        }
    }

    private static void ValidateColorGrading(DevelopColorGrading colorGrading)
    {
        ArgumentNullException.ThrowIfNull(colorGrading);
        ValidateColorGradeRegion(colorGrading.Shadows, nameof(colorGrading.Shadows));
        ValidateColorGradeRegion(colorGrading.Midtones, nameof(colorGrading.Midtones));
        ValidateColorGradeRegion(colorGrading.Highlights, nameof(colorGrading.Highlights));
        if (!float.IsFinite(colorGrading.Blending) || colorGrading.Blending is < 0.0F or > 1.0F ||
            !float.IsFinite(colorGrading.Balance) || colorGrading.Balance is < -1.0F or > 1.0F)
        {
            throw new ArgumentException("Color Grading blending or balance is invalid.", nameof(colorGrading));
        }
    }

    private static void ValidateColorGradeRegion(DevelopColorGradeRegion region, string parameterName)
    {
        if (!float.IsFinite(region.Hue) || region.Hue is < 0.0F or > 360.0F ||
            !float.IsFinite(region.Saturation) || region.Saturation is < 0.0F or > 1.0F ||
            !float.IsFinite(region.Luminance) || region.Luminance is < -1.0F or > 1.0F)
        {
            throw new ArgumentException("A Color Grading region is invalid.", parameterName);
        }
    }

    private static NativeDevelopExportRequestV7 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId)
    {
        NativeDevelopExportRequestV7 native = new()
        {
            StructSize = (uint)sizeof(NativeDevelopExportRequestV7),
            SourcePath = sourcePath,
            DestinationPath = destinationPath,
            OutputFormat = (uint)request.Format,
            FilmType = (uint)request.FilmType,
            BaseEstimationMode = (uint)request.BaseEstimationMode,
            DminRed = request.DminRed,
            DminGreen = request.DminGreen,
            DminBlue = request.DminBlue,
            ExposureStops = request.ExposureStops,
            Contrast = request.Contrast,
            Highlights = request.Highlights,
            Lights = request.Lights,
            Darks = request.Darks,
            Shadows = request.Shadows,
            FilmLookSourceKind = (uint)request.FilmLookSourceKind,
            FilmEmulation = (uint)request.FilmEmulation,
            FilmEmulationIntensity = request.FilmEmulationIntensity,
            RowsPerCopy = request.RowsPerCopy,
            Density = request.Density,
            Highlight = request.Highlight,
            Shadow = request.Shadow,
            Whites = request.Whites,
            Blacks = request.Blacks,
            FilmStockDminId = filmStockDminId,
            LightSourceProfileId = lightSourceProfileId,
            ColorGradingShadowsHue = request.ColorGrading.Shadows.Hue,
            ColorGradingShadowsSaturation = request.ColorGrading.Shadows.Saturation,
            ColorGradingShadowsLuminance = request.ColorGrading.Shadows.Luminance,
            ColorGradingMidtonesHue = request.ColorGrading.Midtones.Hue,
            ColorGradingMidtonesSaturation = request.ColorGrading.Midtones.Saturation,
            ColorGradingMidtonesLuminance = request.ColorGrading.Midtones.Luminance,
            ColorGradingHighlightsHue = request.ColorGrading.Highlights.Hue,
            ColorGradingHighlightsSaturation = request.ColorGrading.Highlights.Saturation,
            ColorGradingHighlightsLuminance = request.ColorGrading.Highlights.Luminance,
            ColorGradingBlending = request.ColorGrading.Blending,
            ColorGradingBalance = request.ColorGrading.Balance,
        };
        CopyPointCurve(request.PointCurves.Rgb, ref native.PointCurveRgb);
        CopyPointCurve(request.PointCurves.Red, ref native.PointCurveRed);
        CopyPointCurve(request.PointCurves.Green, ref native.PointCurveGreen);
        CopyPointCurve(request.PointCurves.Blue, ref native.PointCurveBlue);
        CopyColorMixer(request.ColorMixer.Hue, ref native, 0);
        CopyColorMixer(request.ColorMixer.Saturation, ref native, 1);
        CopyColorMixer(request.ColorMixer.Luminance, ref native, 2);
        return native;
    }

    public static DevelopExportResult Run(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        ValidateLayoutAndEnums(request);

        NativeDevelopExportResultV2 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV2);
        uint status;

        // The native side copies both paths before returning, so pinning them for the
        // duration of the call is enough; no unmanaged allocation is needed.
        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        {
            NativeDevelopExportRequestV7 native = BuildRequest(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId);
            status = NativeMethods.nf_develop_export_v7(&native, &raw);
        }

        return Translate(status, raw);
    }

    /// <summary>
    /// 같은 파이프라인을 돌리되 파일을 쓰지 않고 <paramref name="pixels"/> 에 BGRA8 표시용
    /// 비트맵을 채웁니다. 실제로 쓰인 크기는 결과의 <c>ImageWidth</c>/<c>ImageHeight</c> 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Run"/> 과 마찬가지로 블로킹입니다. UI 스레드에서 부르지 마십시오.
    /// </remarks>
    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);
        if (pixels.IsEmpty)
        {
            throw new ArgumentException("The preview buffer is empty.", nameof(pixels));
        }
        ValidateLayoutAndEnums(request);

        NativeDevelopExportResultV2 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV2);
        uint status;

        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        fixed (byte* pixelBuffer = pixels)
        {
            NativeDevelopExportRequestV7 native = BuildRequest(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId);
            status = NativeMethods.nf_develop_preview_v7(
                &native,
                maximumWidth,
                maximumHeight,
                pixelBuffer,
                (uint)Math.Min(pixels.Length, int.MaxValue),
                &raw);
        }

        return Translate(status, raw);
    }

    private static DevelopExportResult Translate(
        uint status,
        NativeDevelopExportResultV2 raw)
    {
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                status switch
                {
                    StatusInvalidArgument =>
                    "nf_develop_export_v7 rejected the call as malformed.",
                    StatusStructTooSmall =>
                    "nf_develop_export_v7 rejected the struct sizes.",
                    _ => $"nf_develop_export_v7 failed with status {status}.",
                });
        }

        DevelopExportStage stage = (DevelopExportStage)raw.FailedStage;
        FilmLookRoute route = (FilmLookRoute)raw.FilmLookRoute;
        DevelopBaseSource baseSource = (DevelopBaseSource)raw.BaseSource;
        if (!Enum.IsDefined(stage) || !Enum.IsDefined(route) || !Enum.IsDefined(baseSource))
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native develop result reported an unknown stage or route.");
        }

        return new DevelopExportResult(
            raw.Succeeded != 0,
            stage,
            raw.GetFailureName(),
            raw.NativeErrorCode,
            raw.CleanupErrorCode,
            raw.ImageWidth,
            raw.ImageHeight,
            route,
            raw.FilmLookColorApplied != 0,
            raw.FilmLookAcutanceApplied != 0,
            raw.SourceFileBytes,
            raw.OutputFileBytes,
            raw.FilmLookWorkspaceBytes,
            raw.WallMicroseconds,
            raw.AppliedDminRed,
            raw.AppliedDminGreen,
            raw.AppliedDminBlue,
            baseSource);
    }
}
