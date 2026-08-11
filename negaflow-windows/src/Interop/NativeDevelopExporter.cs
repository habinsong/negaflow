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
    internal const int RequestV8Size = 4408;
    internal const int RequestV9Size = 4440;
    internal const int RequestV10Size = 4464;
    internal const int RequestV11Size = 4552;
    internal const int LocalDodgeBurnPointV1Size = 8;
    internal const int LocalDodgeBurnStrokeV1Size = 16;
    internal const int LocalDodgeBurnAdjustmentV1Size = 64;
    internal const int RequestV12Size = 4600;
    internal const int RequestV13Size = 4632;
    internal const int RequestV14Size = 4640;
    internal const int RequestV15Size = 4648;
    internal const int RequestV16Size = 4656;
    internal const int RequestV17Size = 4664;
    internal const int DefectRegionEditV1Size = 56;
    internal const int RequestV18Size = 4696;
    internal const int RequestV19Size = 4720;
    internal const int DefectClonePointV1Size = 16;
    internal const int DefectCloneStrokeV1Size = 40;
    internal const int DefectCloneEditV1Size = 24;
    internal const int DefectRecipeEditRefV1Size = 8;
    internal const int RequestV20Size = 4784;
    internal const int DefectBrushPointV1Size = 16;
    internal const int DefectBrushStrokeV1Size = 16;
    internal const int DefectBrushEditV1Size = 24;
    internal const int RequestV21Size = 4832;
    internal const int DefectInfraredEditV1Size = 24;
    internal const int RequestV24Size = 4864;
    internal const int DefectInfraredItemV1Size = 16;
    internal const int RequestV25Size = 4880;
    internal const int ResultV2Size = 152;
    internal const int ResultV3Size = 160;
    internal const int RunStateV1Size = 16;
    internal const int AutoAdjustResultV1Size = 88;
    internal const int SoftProofMediaV1Size = 40;
    internal const int SoftProofV1Size = 40;

    private const int MaximumLocalAdjustments = 64;
    private const int MaximumLocalStrokes = 8192;
    private const int MaximumLocalStrokesPerMask = 128;
    private const int MaximumLocalPoints = 4096;
    private const int MaximumDefectRegionEdits = 4096;
    private const int MaximumDefectMaskBytes = 512 * 1024 * 1024;
    private const int MaximumDefectCloneEdits = 4096;
    private const int MaximumDefectCloneStrokes = 100_000;
    private const int MaximumDefectClonePoints = 5_000_000;
    private const int MaximumDefectBrushEdits = 4096;
    private const int MaximumDefectBrushStrokes = 100_000;
    private const int MaximumDefectBrushPoints = 5_000_000;
    private const int MaximumDefectInfraredEdits = 4096;
    private const int MaximumDefectInfraredAttenuationBytes = 512 * 1024 * 1024;
    private const int MaximumDefectOrderedEdits = 8192;

    private const uint StatusOk = 0;
    private const uint StatusInvalidArgument = 1;
    private const uint StatusStructTooSmall = 2;

    private static void ValidateLayoutAndEnums(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request.ImageTransform);
        if (sizeof(NativePointCurveV1) != PointCurveV1Size ||
            sizeof(NativeDevelopExportRequestV7) != RequestV7Size ||
            sizeof(NativeDevelopExportRequestV8) != RequestV8Size ||
            sizeof(NativeDevelopExportRequestV9) != RequestV9Size ||
            sizeof(NativeDevelopExportRequestV10) != RequestV10Size ||
            sizeof(NativeDevelopExportRequestV11) != RequestV11Size ||
            sizeof(NativeLocalDodgeBurnPointV1) != LocalDodgeBurnPointV1Size ||
            sizeof(NativeLocalDodgeBurnStrokeV1) != LocalDodgeBurnStrokeV1Size ||
            sizeof(NativeLocalDodgeBurnAdjustmentV1) != LocalDodgeBurnAdjustmentV1Size ||
            sizeof(NativeDevelopExportRequestV12) != RequestV12Size ||
            sizeof(NativeDevelopExportRequestV13) != RequestV13Size ||
            sizeof(NativeDevelopExportRequestV14) != RequestV14Size ||
            sizeof(NativeDevelopExportRequestV15) != RequestV15Size ||
            sizeof(NativeDevelopExportRequestV16) != RequestV16Size ||
            sizeof(NativeDevelopExportRequestV17) != RequestV17Size ||
            sizeof(NativeDefectRegionEditV1) != DefectRegionEditV1Size ||
            sizeof(NativeDevelopExportRequestV18) != RequestV18Size ||
            sizeof(NativeDevelopExportRequestV19) != RequestV19Size ||
            sizeof(NativeDefectClonePointV1) != DefectClonePointV1Size ||
            sizeof(NativeDefectCloneStrokeV1) != DefectCloneStrokeV1Size ||
            sizeof(NativeDefectCloneEditV1) != DefectCloneEditV1Size ||
            sizeof(NativeDefectRecipeEditRefV1) != DefectRecipeEditRefV1Size ||
            sizeof(NativeDevelopExportRequestV20) != RequestV20Size ||
            sizeof(NativeDefectBrushPointV1) != DefectBrushPointV1Size ||
            sizeof(NativeDefectBrushStrokeV1) != DefectBrushStrokeV1Size ||
            sizeof(NativeDefectBrushEditV1) != DefectBrushEditV1Size ||
            sizeof(NativeDevelopExportRequestV21) != RequestV21Size ||
            sizeof(NativeDefectInfraredEditV1) != DefectInfraredEditV1Size ||
            sizeof(NativeDevelopExportRequestV24) != RequestV24Size ||
            sizeof(NativeDefectInfraredItemV1) != DefectInfraredItemV1Size ||
            sizeof(NativeDevelopExportRequestV25) != RequestV25Size ||
            sizeof(NativeDevelopExportResultV2) != ResultV2Size ||
            sizeof(NativeDevelopExportResultV3) != ResultV3Size ||
            sizeof(NativeDevelopRunStateV1) != RunStateV1Size ||
            sizeof(NativeAutoAdjustResultV1) != AutoAdjustResultV1Size ||
            sizeof(NativeSoftProofMediaV1) != SoftProofMediaV1Size ||
            sizeof(NativeSoftProofV1) != SoftProofV1Size)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The managed develop-export layout does not match the C ABI.");
        }
        if (!Enum.IsDefined(request.Format) ||
            !Enum.IsDefined(request.FilmType) ||
            !Enum.IsDefined(request.FilmPolarity) ||
            !Enum.IsDefined(request.BaseEstimationMode) ||
            !Enum.IsDefined(request.FilmLookSourceKind) ||
            !Enum.IsDefined(request.FilmEmulation) ||
            !Enum.IsDefined(request.DevelopTarget) ||
            !Enum.IsDefined(request.NoiseReductionFilmProfile) ||
            !Enum.IsDefined(request.BwToningMode) ||
            !Enum.IsDefined(request.ImageTransform.Rotation))
        {
            throw new ArgumentException(
                "The develop request carries a value outside its enumeration.",
                nameof(request));
        }
        ValidatePointCurves(request.PointCurves);
        ValidateColorMixer(request.ColorMixer);
        ValidateColorGrading(request.ColorGrading);
        ValidateLocalDodgeBurn(request.LocalDodgeBurn);
        ValidateDefectRegions(request.DefectRegions);
        ValidateDefectInfrared(request.DefectInfrared);
        ValidateCombinedDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared);
        ValidateDefectClones(request.DefectClones);
        ValidateDefectBrushes(request.DefectBrushes);
        ValidateDefectEditOrder(request);
        ValidateDefectSourceIdentity(
            request.DefectRegions.Count + request.DefectInfrared.Count +
                request.DefectClones.Count +
                request.DefectBrushes.Count,
            request.DefectSourceIdentity);
        if (!SignedNormalized(request.Warmth) ||
            !SignedNormalized(request.Tint) ||
            !SignedNormalized(request.ColorDepth) ||
            !SignedNormalized(request.Vibrance) ||
            !SignedNormalized(request.Saturation) ||
            !SignedNormalized(request.RedPrimary) ||
            !SignedNormalized(request.GreenPrimary) ||
            !SignedNormalized(request.BluePrimary))
        {
            throw new ArgumentException(
                "ColorModel controls are outside the supported finite range.",
                nameof(request));
        }
        if (!double.IsFinite(request.DefectRemovalStrength) ||
            request.DefectRemovalStrength is < 0.0 or > 1.0)
        {
            throw new ArgumentException(
                "GrainMend strength must be a finite value from zero through one.",
                nameof(request));
        }
        if (!Normalized(request.NoiseReductionStrength) ||
            !Normalized(request.NoiseReductionLuma) ||
            !Normalized(request.NoiseReductionChroma) ||
            !Normalized(request.NoiseReductionDarkTone) ||
            !Normalized(request.NoiseReductionDetail) ||
            !Normalized(request.NoiseReductionGrainProtect))
        {
            throw new ArgumentException(
                "FilmScanDenoise controls must be finite values from zero through one.",
                nameof(request));
        }
        if (!Normalized(request.Grain) ||
            !Normalized(request.Sharpness) ||
            !Normalized(request.Halation) ||
            !SignedNormalized(request.Clarity) ||
            !SignedNormalized(request.Vignette))
        {
            throw new ArgumentException(
                "Texture controls are outside the supported finite range.",
                nameof(request));
        }
        if (request.BwToningShadowHue is { } shadowHue &&
                !double.IsFinite(shadowHue) ||
            request.BwToningHighlightHue is { } highlightHue &&
                !double.IsFinite(highlightHue) ||
            !double.IsFinite(request.BwToningStrength) ||
            request.BwToningStrength is < 0.0 or > 1.0 ||
            !double.IsFinite(request.ImageTransform.StraightenAngle) ||
            request.ImageTransform.StraightenAngle is < -45.0 or > 45.0)
        {
            throw new ArgumentException(
                "B&W toning or straighten controls are outside the supported finite range.",
                nameof(request));
        }
        if (request.ImageTransform.Crop is { } crop &&
            (!double.IsFinite(crop.X) || !double.IsFinite(crop.Y) ||
             !double.IsFinite(crop.Width) || !double.IsFinite(crop.Height) ||
             crop.X < 0.0 || crop.Y < 0.0 || crop.Width <= 0.0 || crop.Height <= 0.0 ||
             crop.X + crop.Width > 1.0 || crop.Y + crop.Height > 1.0))
        {
            throw new ArgumentException(
                "The normalized image crop is invalid.",
                nameof(request));
        }
    }

    private static bool Normalized(float value) =>
        float.IsFinite(value) && value is >= 0.0F and <= 1.0F;

    private static bool SignedNormalized(float value) =>
        float.IsFinite(value) && value is >= -1.0F and <= 1.0F;

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

    private static void ValidateLocalDodgeBurn(
        IReadOnlyList<DevelopLocalDodgeBurnAdjustment> adjustments)
    {
        ArgumentNullException.ThrowIfNull(adjustments);
        if (adjustments.Count > MaximumLocalAdjustments)
        {
            throw new ArgumentException(
                "Local Dodge/Burn has too many adjustments.",
                nameof(adjustments));
        }

        int totalStrokes = 0;
        int totalPoints = 0;
        foreach (DevelopLocalDodgeBurnAdjustment adjustment in adjustments)
        {
            ArgumentNullException.ThrowIfNull(adjustment);
            ArgumentNullException.ThrowIfNull(adjustment.Mask);
            if (!Enum.IsDefined(adjustment.Mode) ||
                !Enum.IsDefined(adjustment.Mask.Kind) ||
                !double.IsFinite(adjustment.Amount) ||
                adjustment.Amount is < 0.0 or > 1.0 ||
                !FinitePoint(adjustment.Mask.Center) ||
                !FinitePoint(adjustment.Mask.Start) ||
                !FinitePoint(adjustment.Mask.End) ||
                !double.IsFinite(adjustment.Mask.Radius) ||
                adjustment.Mask.Radius is < 0.0 or > 2.0 ||
                !double.IsFinite(adjustment.Mask.Feather) ||
                adjustment.Mask.Feather is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A Local Dodge/Burn adjustment is invalid.",
                    nameof(adjustments));
            }

            ArgumentNullException.ThrowIfNull(adjustment.Mask.Strokes);
            ArgumentNullException.ThrowIfNull(adjustment.Mask.Points);
            switch (adjustment.Mask.Kind)
            {
                case DevelopLocalDodgeBurnMaskKind.Brush:
                    if (adjustment.Mask.Points.Count != 0 ||
                        adjustment.Mask.Strokes.Count > MaximumLocalStrokesPerMask)
                    {
                        throw new ArgumentException(
                            "A Local Dodge/Burn brush payload is invalid.",
                            nameof(adjustments));
                    }
                    totalStrokes = checked(totalStrokes + adjustment.Mask.Strokes.Count);
                    foreach (DevelopLocalDodgeBurnStroke stroke in adjustment.Mask.Strokes)
                    {
                        ArgumentNullException.ThrowIfNull(stroke);
                        ArgumentNullException.ThrowIfNull(stroke.Points);
                        if (!double.IsFinite(stroke.Thickness) ||
                            stroke.Thickness is < 0.001 or > 0.25 ||
                            !double.IsFinite(stroke.Feather) ||
                            stroke.Feather is < 0.0 or > 0.25 ||
                            stroke.Points.Any(point => !FinitePoint(point)))
                        {
                            throw new ArgumentException(
                                "A Local Dodge/Burn brush stroke is invalid.",
                                nameof(adjustments));
                        }
                        totalPoints = checked(totalPoints + stroke.Points.Count);
                    }
                    break;
                case DevelopLocalDodgeBurnMaskKind.Polygon:
                    if (adjustment.Mask.Strokes.Count != 0 ||
                        adjustment.Mask.Points.Any(point => !FinitePoint(point)))
                    {
                        throw new ArgumentException(
                            "A Local Dodge/Burn polygon payload is invalid.",
                            nameof(adjustments));
                    }
                    totalPoints = checked(totalPoints + adjustment.Mask.Points.Count);
                    break;
                case DevelopLocalDodgeBurnMaskKind.Radial:
                case DevelopLocalDodgeBurnMaskKind.Linear:
                    if (adjustment.Mask.Strokes.Count != 0 ||
                        adjustment.Mask.Points.Count != 0)
                    {
                        throw new ArgumentException(
                            "A geometric Local Dodge/Burn mask contains unused arrays.",
                            nameof(adjustments));
                    }
                    break;
                default:
                    throw new ArgumentException(
                        "The Local Dodge/Burn mask kind is unknown.",
                        nameof(adjustments));
            }
            if (totalStrokes > MaximumLocalStrokes || totalPoints > MaximumLocalPoints)
            {
                throw new ArgumentException(
                    "Local Dodge/Burn exceeds the bounded stroke or point capacity.",
                    nameof(adjustments));
            }
        }
    }

    private static bool FinitePoint(DevelopLocalDodgeBurnPoint point) =>
        double.IsFinite(point.X) && double.IsFinite(point.Y);

    private static void ValidateDefectRegions(
        IReadOnlyList<DevelopDefectRegionEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectRegionEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many region edits.",
                nameof(edits));
        }
        long totalBytes = 0;
        foreach (DevelopDefectRegionEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            uint stride = edit.MaskStrideBytes == 0U
                ? edit.Width
                : edit.MaskStrideBytes;
            ulong required = edit.Height == 0U
                ? 0U
                : ((ulong)edit.Height - 1U) * stride + edit.Width;
            if (edit.Width <= 2U || edit.Height <= 2U ||
                stride < edit.Width || required > (ulong)edit.Mask.Length ||
                !double.IsFinite(edit.Strength) ||
                edit.Strength is < 0.0 or > 1.0 ||
                edit.PreferredAngleDegrees is { } angle &&
                    (!double.IsFinite(angle) || angle is < 0.0 or > 180.0))
            {
                throw new ArgumentException(
                    "A defect region edit has an invalid mask, strength, or angle.",
                    nameof(edits));
            }
            totalBytes = checked(totalBytes + edit.Mask.Length);
            if (totalBytes > MaximumDefectMaskBytes)
            {
                throw new ArgumentException(
                    "The defect recipe exceeds the bounded mask capacity.",
                    nameof(edits));
            }
        }
    }

    private static void ValidateDefectInfrared(
        IReadOnlyList<DevelopDefectInfraredEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectInfraredEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many infrared edits.",
                nameof(edits));
        }
        int totalClusters = 0;
        long totalAttenuationBytes = 0;
        foreach (DevelopDefectInfraredEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Clusters);
            if (edit.Clusters.Count == 0 ||
                !double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "An infrared edit has no clusters or an invalid strength.",
                    nameof(edits));
            }
            totalClusters = checked(totalClusters + edit.Clusters.Count);
            if (totalClusters > MaximumDefectInfraredEdits)
            {
                throw new ArgumentException(
                    "The defect recipe contains too many infrared clusters.",
                    nameof(edits));
            }
            foreach (DevelopDefectInfraredCluster cluster in edit.Clusters)
            {
                ArgumentNullException.ThrowIfNull(cluster);
                uint coreStride = cluster.CoreMaskStrideBytes == 0U
                    ? cluster.Width
                    : cluster.CoreMaskStrideBytes;
                ulong requiredCore = cluster.Height == 0U
                    ? 0U
                    : ((ulong)cluster.Height - 1U) * coreStride + cluster.Width;
                if (cluster.Width == 0U || cluster.Height == 0U ||
                    coreStride < cluster.Width ||
                    requiredCore != (ulong)cluster.CoreMask.Length)
                {
                    throw new ArgumentException(
                        "An infrared cluster has an invalid core mask.",
                        nameof(edits));
                }

                if (cluster.AttenuationR16 is not { } attenuation)
                {
                    if (cluster.AttenuationStrideBytes != 0U)
                    {
                        throw new ArgumentException(
                            "An infrared cluster without attenuation has a non-zero stride.",
                            nameof(edits));
                    }
                    continue;
                }

                ulong rowBytes = (ulong)cluster.Width * sizeof(ushort);
                uint attenuationStride = cluster.AttenuationStrideBytes == 0U
                    ? checked((uint)rowBytes)
                    : cluster.AttenuationStrideBytes;
                ulong requiredAttenuation = ((ulong)cluster.Height - 1U) *
                    attenuationStride + rowBytes;
                if (attenuationStride < rowBytes ||
                    requiredAttenuation != (ulong)attenuation.Length)
                {
                    throw new ArgumentException(
                        "An infrared cluster has an invalid attenuation layout.",
                        nameof(edits));
                }
                totalAttenuationBytes = checked(
                    totalAttenuationBytes + attenuation.Length);
                if (totalAttenuationBytes > MaximumDefectInfraredAttenuationBytes)
                {
                    throw new ArgumentException(
                        "The infrared recipe exceeds the bounded attenuation capacity.",
                        nameof(edits));
                }
            }
        }
    }

    private static void ValidateCombinedDefectRegionPayload(
        IReadOnlyList<DevelopDefectRegionEdit> regions,
        IReadOnlyList<DevelopDefectInfraredEdit> infrared)
    {
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            infraredClusterCount = checked(infraredClusterCount + item.Clusters.Count);
        }
        if (regions.Count > MaximumDefectRegionEdits - infraredClusterCount)
        {
            throw new ArgumentException(
                "The combined region and infrared recipe exceeds native capacity.");
        }
        long totalMaskBytes = 0;
        foreach (DevelopDefectRegionEdit edit in regions)
        {
            totalMaskBytes += edit.Mask.Length;
        }
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                totalMaskBytes += cluster.CoreMask.Length;
            }
        }
        if (totalMaskBytes > MaximumDefectMaskBytes)
        {
            throw new ArgumentException(
                "The combined region and infrared masks exceed native capacity.");
        }
    }

    private static void ValidateDefectClones(
        IReadOnlyList<DevelopDefectCloneEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectCloneEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many clone edits.",
                nameof(edits));
        }
        long totalStrokes = 0;
        long totalPoints = 0;
        foreach (DevelopDefectCloneEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Strokes);
            if (!double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A clone edit has an invalid strength.", nameof(edits));
            }
            totalStrokes = checked(totalStrokes + edit.Strokes.Count);
            foreach (DevelopDefectCloneStroke stroke in edit.Strokes)
            {
                ArgumentNullException.ThrowIfNull(stroke);
                ArgumentNullException.ThrowIfNull(stroke.Points);
                if (!double.IsFinite(stroke.OffsetX) ||
                    !double.IsFinite(stroke.OffsetY) ||
                    !double.IsFinite(stroke.DiameterPixels) ||
                    stroke.DiameterPixels <= 0.0 ||
                    !double.IsFinite(stroke.Hardness) ||
                    stroke.Hardness is < 0.0 or > 1.0)
                {
                    throw new ArgumentException(
                        "A clone stroke has invalid geometry.", nameof(edits));
                }
                totalPoints = checked(totalPoints + stroke.Points.Count);
                foreach (DevelopDefectClonePoint point in stroke.Points)
                {
                    if (!double.IsFinite(point.X) || !double.IsFinite(point.Y))
                    {
                        throw new ArgumentException(
                            "A clone stroke contains a non-finite point.", nameof(edits));
                    }
                }
            }
            if (totalStrokes > MaximumDefectCloneStrokes ||
                totalPoints > MaximumDefectClonePoints)
            {
                throw new ArgumentException(
                    "The clone recipe exceeds the bounded stroke or point capacity.",
                    nameof(edits));
            }
        }
    }

    private static void ValidateDefectBrushes(
        IReadOnlyList<DevelopDefectBrushEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectBrushEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many brush edits.",
                nameof(edits));
        }
        long totalStrokes = 0;
        long totalPoints = 0;
        foreach (DevelopDefectBrushEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Strokes);
            if (!double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A brush edit has an invalid strength.", nameof(edits));
            }
            totalStrokes = checked(totalStrokes + edit.Strokes.Count);
            foreach (DevelopDefectBrushStroke stroke in edit.Strokes)
            {
                ArgumentNullException.ThrowIfNull(stroke);
                ArgumentNullException.ThrowIfNull(stroke.Points);
                if (!double.IsFinite(stroke.Thickness) ||
                    stroke.Thickness is < 0.0 or > 1.0)
                {
                    throw new ArgumentException(
                        "A brush stroke has invalid geometry.", nameof(edits));
                }
                totalPoints = checked(totalPoints + stroke.Points.Count);
                foreach (DevelopDefectBrushPoint point in stroke.Points)
                {
                    if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                        point.X is < 0.0 or > 1.0 ||
                        point.Y is < 0.0 or > 1.0)
                    {
                        throw new ArgumentException(
                            "A brush stroke contains a non-finite point.",
                            nameof(edits));
                    }
                }
            }
            if (totalStrokes > MaximumDefectBrushStrokes ||
                totalPoints > MaximumDefectBrushPoints)
            {
                throw new ArgumentException(
                    "The brush recipe exceeds the bounded stroke or point capacity.",
                    nameof(edits));
            }
        }
    }

    private static void ValidateDefectEditOrder(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request.DefectEditOrder);
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in request.DefectInfrared)
        {
            infraredClusterCount = checked(
                infraredClusterCount + item.Clusters.Count);
        }
        int expectedCount = checked(
            request.DefectRegions.Count + request.DefectInfrared.Count +
            request.DefectClones.Count + request.DefectBrushes.Count);
        int nativeExpectedCount = checked(
            request.DefectRegions.Count + infraredClusterCount +
            request.DefectClones.Count + request.DefectBrushes.Count);
        if (request.DefectEditOrder.Count == 0 && request.DefectClones.Count == 0 &&
            request.DefectBrushes.Count == 0 && request.DefectInfrared.Count == 0)
        {
            return;
        }
        if (expectedCount > MaximumDefectOrderedEdits ||
            nativeExpectedCount > MaximumDefectOrderedEdits ||
            request.DefectEditOrder.Count != expectedCount)
        {
            throw new ArgumentException(
                "The defect edit order does not cover the complete recipe.",
                nameof(request));
        }
        bool[] regions = new bool[request.DefectRegions.Count];
        bool[] infrared = new bool[request.DefectInfrared.Count];
        bool[] clones = new bool[request.DefectClones.Count];
        bool[] brushes = new bool[request.DefectBrushes.Count];
        foreach (DevelopDefectRecipeEditRef reference in request.DefectEditOrder)
        {
            bool valid = reference.Kind switch
            {
                DevelopDefectEditKind.Region when reference.Index < regions.Length &&
                    !regions[reference.Index] => regions[reference.Index] = true,
                DevelopDefectEditKind.Clone when reference.Index < clones.Length &&
                    !clones[reference.Index] => clones[reference.Index] = true,
                DevelopDefectEditKind.Brush when reference.Index < brushes.Length &&
                    !brushes[reference.Index] => brushes[reference.Index] = true,
                DevelopDefectEditKind.Infrared when reference.Index < infrared.Length &&
                    !infrared[reference.Index] => infrared[reference.Index] = true,
                _ => false,
            };
            if (!valid)
            {
                throw new ArgumentException(
                    "The defect edit order contains an invalid or duplicate reference.",
                    nameof(request));
            }
        }
    }

    private static void ValidateDefectSourceIdentity(
        int editCount,
        DevelopDefectSourceIdentity? identity)
    {
        if (editCount == 0)
        {
            if (identity is not null)
            {
                throw new ArgumentException(
                    "A defect source identity requires at least one defect edit.",
                    nameof(identity));
            }
            return;
        }
        if (identity is null || identity.ByteCount == 0 ||
            identity.Sha256 is not { Length: 64 } sha256 ||
            sha256.Any(character => character is not
                (>= '0' and <= '9') and not (>= 'a' and <= 'f')))
        {
            throw new ArgumentException(
                "A defect recipe requires a lowercase SHA-256 source identity.",
                nameof(identity));
        }
    }

    private sealed record NativeLocalDodgeBurnPayload(
        NativeLocalDodgeBurnAdjustmentV1[] Adjustments,
        NativeLocalDodgeBurnStrokeV1[] Strokes,
        NativeLocalDodgeBurnPointV1[] Points);

    private static NativeLocalDodgeBurnPayload BuildLocalDodgeBurnPayload(
        IReadOnlyList<DevelopLocalDodgeBurnAdjustment> source)
    {
        List<NativeLocalDodgeBurnAdjustmentV1> adjustments = new(source.Count);
        List<NativeLocalDodgeBurnStrokeV1> strokes = [];
        List<NativeLocalDodgeBurnPointV1> points = [];
        foreach (DevelopLocalDodgeBurnAdjustment adjustment in source)
        {
            uint strokeOffset = 0U;
            uint strokeCount = 0U;
            uint pointOffset = 0U;
            uint pointCount = 0U;
            if (adjustment.Mask.Kind == DevelopLocalDodgeBurnMaskKind.Brush)
            {
                strokeOffset = checked((uint)strokes.Count);
                strokeCount = checked((uint)adjustment.Mask.Strokes.Count);
                foreach (DevelopLocalDodgeBurnStroke stroke in adjustment.Mask.Strokes)
                {
                    uint strokePointOffset = checked((uint)points.Count);
                    foreach (DevelopLocalDodgeBurnPoint point in stroke.Points)
                    {
                        points.Add(new NativeLocalDodgeBurnPointV1
                        {
                            X = (float)point.X,
                            Y = (float)point.Y,
                        });
                    }
                    strokes.Add(new NativeLocalDodgeBurnStrokeV1
                    {
                        PointOffset = strokePointOffset,
                        PointCount = checked((uint)stroke.Points.Count),
                        Thickness = (float)stroke.Thickness,
                        Feather = (float)stroke.Feather,
                    });
                }
            }
            else if (adjustment.Mask.Kind == DevelopLocalDodgeBurnMaskKind.Polygon)
            {
                pointOffset = checked((uint)points.Count);
                pointCount = checked((uint)adjustment.Mask.Points.Count);
                foreach (DevelopLocalDodgeBurnPoint point in adjustment.Mask.Points)
                {
                    points.Add(new NativeLocalDodgeBurnPointV1
                    {
                        X = (float)point.X,
                        Y = (float)point.Y,
                    });
                }
            }
            adjustments.Add(new NativeLocalDodgeBurnAdjustmentV1
            {
                Mode = (uint)adjustment.Mode,
                Enabled = adjustment.IsEnabled ? 1U : 0U,
                MaskKind = (uint)adjustment.Mask.Kind,
                StrokeOffset = strokeOffset,
                StrokeCount = strokeCount,
                PointOffset = pointOffset,
                PointCount = pointCount,
                Amount = (float)adjustment.Amount,
                CenterX = (float)adjustment.Mask.Center.X,
                CenterY = (float)adjustment.Mask.Center.Y,
                Radius = (float)adjustment.Mask.Radius,
                Feather = (float)adjustment.Mask.Feather,
                StartX = (float)adjustment.Mask.Start.X,
                StartY = (float)adjustment.Mask.Start.Y,
                EndX = (float)adjustment.Mask.End.X,
                EndY = (float)adjustment.Mask.End.Y,
            });
        }
        return new NativeLocalDodgeBurnPayload(
            [.. adjustments],
            [.. strokes],
            [.. points]);
    }

    private sealed record NativeDefectRegionPayload(
        NativeDefectRegionEditV1[] Edits,
        byte[] MaskBytes,
        NativeDefectInfraredEditV1[] InfraredEdits,
        byte[] InfraredAttenuationBytes,
        NativeDefectInfraredItemV1[] InfraredItems);

    private static NativeDefectRegionPayload BuildDefectRegionPayload(
        IReadOnlyList<DevelopDefectRegionEdit> source,
        IReadOnlyList<DevelopDefectInfraredEdit> infrared)
    {
        int totalBytes = 0;
        foreach (DevelopDefectRegionEdit edit in source)
        {
            totalBytes = checked(totalBytes + edit.Mask.Length);
        }
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            infraredClusterCount = checked(infraredClusterCount + item.Clusters.Count);
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                totalBytes = checked(totalBytes + cluster.CoreMask.Length);
            }
        }
        byte[] masks = new byte[totalBytes];
        NativeDefectRegionEditV1[] edits =
            new NativeDefectRegionEditV1[source.Count + infraredClusterCount];
        int offset = 0;
        for (int index = 0; index < source.Count; ++index)
        {
            DevelopDefectRegionEdit edit = source[index];
            edit.Mask.Span.CopyTo(masks.AsSpan(offset));
            double angle = edit.PreferredAngleDegrees ?? 0.0;
            edits[index] = new NativeDefectRegionEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                RoiX = edit.RoiX,
                RoiY = edit.RoiY,
                Width = edit.Width,
                Height = edit.Height,
                MaskStrideBytes = edit.MaskStrideBytes == 0U
                    ? edit.Width
                    : edit.MaskStrideBytes,
                MaskOffset = checked((uint)offset),
                MaskByteCount = checked((uint)edit.Mask.Length),
                Strength = edit.Strength,
                HasPreferredAngle = edit.PreferredAngleDegrees.HasValue ? 1U : 0U,
                PreferredAngleDegrees = angle,
            };
            offset = checked(offset + edit.Mask.Length);
        }

        int attenuationByteCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                if (cluster.AttenuationR16 is { } attenuation)
                {
                    attenuationByteCount = checked(
                        attenuationByteCount + attenuation.Length);
                }
            }
        }
        byte[] attenuationBytes = new byte[attenuationByteCount];
        NativeDefectInfraredEditV1[] infraredEdits =
            new NativeDefectInfraredEditV1[infraredClusterCount];
        NativeDefectInfraredItemV1[] infraredItems =
            new NativeDefectInfraredItemV1[infrared.Count];
        int attenuationOffset = 0;
        int clusterIndex = 0;
        for (int itemIndex = 0; itemIndex < infrared.Count; ++itemIndex)
        {
            DevelopDefectInfraredEdit item = infrared[itemIndex];
            infraredItems[itemIndex] = new NativeDefectInfraredItemV1
            {
                ClusterOffset = checked((uint)clusterIndex),
                ClusterCount = checked((uint)item.Clusters.Count),
            };
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                cluster.CoreMask.Span.CopyTo(masks.AsSpan(offset));
                int regionIndex = checked(source.Count + clusterIndex);
                edits[regionIndex] = new NativeDefectRegionEditV1
                {
                    Enabled = item.IsEnabled ? 1U : 0U,
                    RoiX = cluster.RoiX,
                    RoiY = cluster.RoiY,
                    Width = cluster.Width,
                    Height = cluster.Height,
                    MaskStrideBytes = cluster.CoreMaskStrideBytes == 0U
                        ? cluster.Width
                        : cluster.CoreMaskStrideBytes,
                    MaskOffset = checked((uint)offset),
                    MaskByteCount = checked((uint)cluster.CoreMask.Length),
                    Strength = item.Strength,
                };
                offset = checked(offset + cluster.CoreMask.Length);

                if (cluster.AttenuationR16 is { } attenuation)
                {
                    attenuation.Span.CopyTo(
                        attenuationBytes.AsSpan(attenuationOffset));
                    infraredEdits[clusterIndex] = new NativeDefectInfraredEditV1
                    {
                        RegionEditIndex = checked((uint)regionIndex),
                        HasAttenuation = 1U,
                        AttenuationStrideBytes = cluster.AttenuationStrideBytes == 0U
                            ? checked(cluster.Width * sizeof(ushort))
                            : cluster.AttenuationStrideBytes,
                        AttenuationOffset = checked((uint)attenuationOffset),
                        AttenuationByteCount = checked((uint)attenuation.Length),
                    };
                    attenuationOffset = checked(
                        attenuationOffset + attenuation.Length);
                }
                else
                {
                    infraredEdits[clusterIndex] = new NativeDefectInfraredEditV1
                    {
                        RegionEditIndex = checked((uint)regionIndex),
                    };
                }
                ++clusterIndex;
            }
        }
        return new NativeDefectRegionPayload(
            edits, masks, infraredEdits, attenuationBytes, infraredItems);
    }

    private sealed record NativeDefectClonePayload(
        NativeDefectCloneEditV1[] Edits,
        NativeDefectCloneStrokeV1[] Strokes,
        NativeDefectClonePointV1[] Points);

    private static NativeDefectClonePayload BuildDefectClonePayload(
        IReadOnlyList<DevelopDefectCloneEdit> source)
    {
        List<NativeDefectCloneEditV1> edits = new(source.Count);
        List<NativeDefectCloneStrokeV1> strokes = [];
        List<NativeDefectClonePointV1> points = [];
        foreach (DevelopDefectCloneEdit edit in source)
        {
            uint strokeOffset = checked((uint)strokes.Count);
            foreach (DevelopDefectCloneStroke stroke in edit.Strokes)
            {
                uint pointOffset = checked((uint)points.Count);
                foreach (DevelopDefectClonePoint point in stroke.Points)
                {
                    points.Add(new NativeDefectClonePointV1
                    {
                        X = point.X,
                        Y = point.Y,
                    });
                }
                strokes.Add(new NativeDefectCloneStrokeV1
                {
                    PointOffset = pointOffset,
                    PointCount = checked((uint)stroke.Points.Count),
                    OffsetX = stroke.OffsetX,
                    OffsetY = stroke.OffsetY,
                    DiameterPixels = stroke.DiameterPixels,
                    Hardness = stroke.Hardness,
                });
            }
            edits.Add(new NativeDefectCloneEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                StrokeOffset = strokeOffset,
                StrokeCount = checked((uint)edit.Strokes.Count),
                Strength = edit.Strength,
            });
        }
        return new NativeDefectClonePayload([.. edits], [.. strokes], [.. points]);
    }

    private sealed record NativeDefectBrushPayload(
        NativeDefectBrushEditV1[] Edits,
        NativeDefectBrushStrokeV1[] Strokes,
        NativeDefectBrushPointV1[] Points);

    private static NativeDefectBrushPayload BuildDefectBrushPayload(
        IReadOnlyList<DevelopDefectBrushEdit> source)
    {
        List<NativeDefectBrushEditV1> edits = new(source.Count);
        List<NativeDefectBrushStrokeV1> strokes = [];
        List<NativeDefectBrushPointV1> points = [];
        foreach (DevelopDefectBrushEdit edit in source)
        {
            uint strokeOffset = checked((uint)strokes.Count);
            foreach (DevelopDefectBrushStroke stroke in edit.Strokes)
            {
                uint pointOffset = checked((uint)points.Count);
                foreach (DevelopDefectBrushPoint point in stroke.Points)
                {
                    points.Add(new NativeDefectBrushPointV1
                    {
                        X = point.X,
                        Y = point.Y,
                    });
                }
                strokes.Add(new NativeDefectBrushStrokeV1
                {
                    PointOffset = pointOffset,
                    PointCount = checked((uint)stroke.Points.Count),
                    Thickness = stroke.Thickness,
                });
            }
            edits.Add(new NativeDefectBrushEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                StrokeOffset = strokeOffset,
                StrokeCount = checked((uint)edit.Strokes.Count),
                Strength = edit.Strength,
            });
        }
        return new NativeDefectBrushPayload([.. edits], [.. strokes], [.. points]);
    }

    private static NativeDefectRecipeEditRefV1[] BuildDefectEditOrder(
        DevelopExportRequest request)
    {
        if (request.DefectEditOrder.Count == 0)
        {
            NativeDefectRecipeEditRefV1[] regions =
                new NativeDefectRecipeEditRefV1[request.DefectRegions.Count];
            for (int index = 0; index < regions.Length; ++index)
            {
                regions[index] = new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)DevelopDefectEditKind.Region,
                    Index = checked((uint)index),
                };
            }
            return regions;
        }
        int[] infraredClusterOffsets = new int[request.DefectInfrared.Count];
        int infraredClusterCount = 0;
        for (int index = 0; index < request.DefectInfrared.Count; ++index)
        {
            infraredClusterOffsets[index] = infraredClusterCount;
            infraredClusterCount = checked(
                infraredClusterCount + request.DefectInfrared[index].Clusters.Count);
        }
        List<NativeDefectRecipeEditRefV1> order = new(
            checked(request.DefectEditOrder.Count - request.DefectInfrared.Count +
                infraredClusterCount));
        foreach (DevelopDefectRecipeEditRef reference in request.DefectEditOrder)
        {
            if (reference.Kind != DevelopDefectEditKind.Infrared)
            {
                order.Add(new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)reference.Kind,
                    Index = reference.Index,
                });
                continue;
            }
            int itemIndex = checked((int)reference.Index);
            int firstCluster = infraredClusterOffsets[itemIndex];
            for (int ordinal = 0;
                 ordinal < request.DefectInfrared[itemIndex].Clusters.Count;
                 ++ordinal)
            {
                order.Add(new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)DevelopDefectEditKind.Region,
                    Index = checked((uint)(request.DefectRegions.Count +
                        firstCluster + ordinal)),
                });
            }
        }
        return [.. order];
    }

    private static NativeDevelopExportRequestV7 BuildRequestV7(
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

    private static NativeDevelopExportRequestV11 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId)
    {
        NativeDevelopExportRequestV7 prefix = BuildRequestV7(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId);
        prefix.StructSize = (uint)sizeof(NativeDevelopExportRequestV11);
        NativeDevelopExportRequestV8 v8 = new()
        {
            V7 = prefix,
            DefectRemovalStrength = request.DefectRemovalStrength,
        };
        NativeDevelopExportRequestV9 v9 = new()
        {
            V8 = v8,
            NoiseReductionStrength = request.NoiseReductionStrength,
            NoiseReductionLuma = request.NoiseReductionLuma,
            NoiseReductionChroma = request.NoiseReductionChroma,
            NoiseReductionDarkTone = request.NoiseReductionDarkTone,
            NoiseReductionDetail = request.NoiseReductionDetail,
            NoiseReductionGrainProtect = request.NoiseReductionGrainProtect,
            NoiseReductionFilmProfile = (uint)request.NoiseReductionFilmProfile,
        };
        NativeDevelopExportRequestV10 v10 = new()
        {
            V9 = v9,
            TextureGrain = request.Grain,
            TextureSharpness = request.Sharpness,
            TextureHalation = request.Halation,
            TextureClarity = request.Clarity,
            TextureVignette = request.Vignette,
        };
        DevelopCropRect crop = request.ImageTransform.Crop ??
            new DevelopCropRect(0.0, 0.0, 1.0, 1.0);
        double defaultShadowHue = request.BwToningMode == BwToningMode.Sepia
            ? 32.0
            : 285.0;
        double defaultHighlightHue = request.BwToningMode == BwToningMode.Sepia
            ? 48.0
            : 34.0;
        return new NativeDevelopExportRequestV11
        {
            V10 = v10,
            BwToningMode = (uint)request.BwToningMode,
            BwToningShadowHue = request.BwToningShadowHue ?? defaultShadowHue,
            BwToningHighlightHue = request.BwToningHighlightHue ?? defaultHighlightHue,
            BwToningStrength = request.BwToningStrength,
            ImageRotation = (uint)request.ImageTransform.Rotation,
            FlipHorizontal = request.ImageTransform.FlipHorizontal ? 1U : 0U,
            FlipVertical = request.ImageTransform.FlipVertical ? 1U : 0U,
            HasCrop = request.ImageTransform.Crop.HasValue ? 1U : 0U,
            CropX = crop.X,
            CropY = crop.Y,
            CropWidth = crop.Width,
            CropHeight = crop.Height,
            StraightenAngle = request.ImageTransform.StraightenAngle,
        };
    }

    private static NativeDevelopExportRequestV12 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV11 v11 = BuildRequest(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId);
        v11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV12);
        return new NativeDevelopExportRequestV12
        {
            V11 = v11,
            LocalAdjustments = localAdjustments,
            LocalAdjustmentCount = localAdjustmentCount,
            LocalStrokes = localStrokes,
            LocalStrokeCount = localStrokeCount,
            LocalPoints = localPoints,
            LocalPointCount = localPointCount,
        };
    }

    private static NativeDevelopExportRequestV13 BuildRequestV13(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV12 v12 = BuildRequest(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV13);
        return new NativeDevelopExportRequestV13
        {
            V12 = v12,
            Warmth = request.Warmth,
            Tint = request.Tint,
            ColorDepth = request.ColorDepth,
            Vibrance = request.Vibrance,
            Saturation = request.Saturation,
            RedPrimary = request.RedPrimary,
            GreenPrimary = request.GreenPrimary,
            BluePrimary = request.BluePrimary,
        };
    }

    private static NativeDevelopExportRequestV14 BuildRequestV14(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV13 v13 = BuildRequestV13(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v13.V12.V11.V10.V9.V8.V7.StructSize = (uint)sizeof(NativeDevelopExportRequestV14);
        return new NativeDevelopExportRequestV14
        {
            V13 = v13,
            AutoLevels = request.AutoLevels ? 1U : 0U,
            AutoNeutralBalance = request.AutoNeutralBalance ? 1U : 0U,
        };
    }

    private static NativeDevelopExportRequestV15 BuildRequestV15(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV14 v14 = BuildRequestV14(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV15);
        return new NativeDevelopExportRequestV15
        {
            V14 = v14,
            DevelopTarget = (uint)request.DevelopTarget,
        };
    }

    private static NativeDevelopExportRequestV16 BuildRequestV16(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV15 v15 = BuildRequestV15(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV16);
        return new NativeDevelopExportRequestV16
        {
            V15 = v15,
            ScannerProfileId = scannerProfileId,
        };
    }

    private static NativeDevelopExportRequestV17 BuildRequestV17(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount)
    {
        NativeDevelopExportRequestV16 v16 = BuildRequestV16(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV17);
        return new NativeDevelopExportRequestV17
        {
            V16 = v16,
            // Rendered-digital was already a positive-only route before v17.
            // Preserve that managed-call contract while the new field makes
            // positive film scans explicit.
            FilmPolarity = (uint)(
                request.FilmLookSourceKind == DevelopSourceKind.RenderedDigital
                    ? FilmPolarity.Positive
                    : request.FilmPolarity),
        };
    }

    private static NativeDevelopExportRequestV18 BuildRequestV18(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount)
    {
        NativeDevelopExportRequestV17 v17 = BuildRequestV17(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount);
        v17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV18);
        return new NativeDevelopExportRequestV18
        {
            V17 = v17,
            DefectRegionEdits = defectRegionEdits,
            DefectRegionEditCount = defectRegionEditCount,
            DefectMaskBytes = defectMaskBytes,
            DefectMaskByteCount = defectMaskByteCount,
        };
    }

    private static NativeDevelopExportRequestV19 BuildRequestV19(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount,
        byte* defectSourceSha256)
    {
        NativeDevelopExportRequestV18 v18 = BuildRequestV18(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount,
            defectRegionEdits,
            defectRegionEditCount,
            defectMaskBytes,
            defectMaskByteCount);
        v18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV19);
        return new NativeDevelopExportRequestV19
        {
            V18 = v18,
            DefectSourceFileBytes = request.DefectSourceIdentity?.ByteCount ?? 0,
            DefectSourceSha256 = defectSourceSha256,
            HasDefectSourceIdentity = request.DefectSourceIdentity is null ? 0U : 1U,
        };
    }

    private static NativeDevelopExportRequestV20 BuildRequestV20(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath,
        char* filmStockDminId,
        char* lightSourceProfileId,
        char* scannerProfileId,
        NativeLocalDodgeBurnAdjustmentV1* localAdjustments,
        uint localAdjustmentCount,
        NativeLocalDodgeBurnStrokeV1* localStrokes,
        uint localStrokeCount,
        NativeLocalDodgeBurnPointV1* localPoints,
        uint localPointCount,
        NativeDefectRegionEditV1* defectRegionEdits,
        uint defectRegionEditCount,
        byte* defectMaskBytes,
        uint defectMaskByteCount,
        byte* defectSourceSha256,
        NativeDefectCloneEditV1* defectCloneEdits,
        uint defectCloneEditCount,
        NativeDefectCloneStrokeV1* defectCloneStrokes,
        uint defectCloneStrokeCount,
        NativeDefectClonePointV1* defectClonePoints,
        uint defectClonePointCount,
        NativeDefectRecipeEditRefV1* defectEditOrder,
        uint defectEditOrderCount)
    {
        NativeDevelopExportRequestV19 v19 = BuildRequestV19(
            request,
            sourcePath,
            destinationPath,
            filmStockDminId,
            lightSourceProfileId,
            scannerProfileId,
            localAdjustments,
            localAdjustmentCount,
            localStrokes,
            localStrokeCount,
            localPoints,
            localPointCount,
            defectRegionEdits,
            defectRegionEditCount,
            defectMaskBytes,
            defectMaskByteCount,
            defectSourceSha256);
        v19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV20);
        return new NativeDevelopExportRequestV20
        {
            V19 = v19,
            DefectCloneEdits = defectCloneEdits,
            DefectCloneEditCount = defectCloneEditCount,
            DefectCloneStrokes = defectCloneStrokes,
            DefectCloneStrokeCount = defectCloneStrokeCount,
            DefectClonePoints = defectClonePoints,
            DefectClonePointCount = defectClonePointCount,
            DefectEditOrder = defectEditOrder,
            DefectEditOrderCount = defectEditOrderCount,
        };
    }

    private static NativeDevelopExportRequestV21 BuildRequestV21(
        NativeDevelopExportRequestV20 v20,
        NativeDefectBrushEditV1* defectBrushEdits,
        uint defectBrushEditCount,
        NativeDefectBrushStrokeV1* defectBrushStrokes,
        uint defectBrushStrokeCount,
        NativeDefectBrushPointV1* defectBrushPoints,
        uint defectBrushPointCount)
    {
        v20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV21);
        return new NativeDevelopExportRequestV21
        {
            V20 = v20,
            DefectBrushEdits = defectBrushEdits,
            DefectBrushEditCount = defectBrushEditCount,
            DefectBrushStrokes = defectBrushStrokes,
            DefectBrushStrokeCount = defectBrushStrokeCount,
            DefectBrushPoints = defectBrushPoints,
            DefectBrushPointCount = defectBrushPointCount,
        };
    }

    private static NativeDevelopExportRequestV24 BuildRequestV24(
        NativeDevelopExportRequestV21 v21,
        NativeDefectInfraredEditV1* defectInfraredEdits,
        uint defectInfraredEditCount,
        byte* defectInfraredAttenuationBytes,
        uint defectInfraredAttenuationByteCount)
    {
        v21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV24);
        return new NativeDevelopExportRequestV24
        {
            V21 = v21,
            DefectInfraredEdits = defectInfraredEdits,
            DefectInfraredEditCount = defectInfraredEditCount,
            DefectInfraredAttenuationBytes = defectInfraredAttenuationBytes,
            DefectInfraredAttenuationByteCount = defectInfraredAttenuationByteCount,
        };
    }

    private static NativeDevelopExportRequestV25 BuildRequestV25(
        NativeDevelopExportRequestV24 v24,
        NativeDefectInfraredItemV1* defectInfraredItems,
        uint defectInfraredItemCount)
    {
        v24.V21.V20.V19.V18.V17.V16.V15.V14.V13.V12.V11.V10.V9.V8.V7.StructSize =
            (uint)sizeof(NativeDevelopExportRequestV25);
        return new NativeDevelopExportRequestV25
        {
            V24 = v24,
            DefectInfraredItems = defectInfraredItems,
            DefectInfraredItemCount = defectInfraredItemCount,
        };
    }

    private static byte[] BuildDefectSourceSha256(DevelopExportRequest request) =>
        request.DefectSourceIdentity is { } identity
            ? Convert.FromHexString(identity.Sha256)
            : [];

    /// <param name="run">
    /// 실행 중 취소하고 진행도를 읽는 손잡이입니다. null 이면 예전처럼 끝까지 블로킹합니다.
    /// </param>
    public static DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ValidateLayoutAndEnums(request);
        NativeLocalDodgeBurnPayload local = BuildLocalDodgeBurnPayload(
            request.LocalDodgeBurn);
        NativeDefectRegionPayload defects = BuildDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared);
        NativeDefectClonePayload clones = BuildDefectClonePayload(
            request.DefectClones);
        NativeDefectBrushPayload brushes = BuildDefectBrushPayload(
            request.DefectBrushes);
        NativeDefectRecipeEditRefV1[] defectEditOrder = BuildDefectEditOrder(request);
        byte[] defectSourceSha256 = BuildDefectSourceSha256(request);

        NativeDevelopExportResultV3 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV3);
        uint status;

        // A null run state is the pre-v22 behaviour: the call simply runs to the end.
        NativeDevelopRunStateV1* runState = run is null ? null : run.StatePointer;

        // The native side copies both paths before returning, so pinning them for the
        // duration of the call is enough; no unmanaged allocation is needed.
        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        fixed (char* scannerProfileId = request.ScannerProfileId)
        fixed (NativeLocalDodgeBurnAdjustmentV1* localAdjustments = local.Adjustments)
        fixed (NativeLocalDodgeBurnStrokeV1* localStrokes = local.Strokes)
        fixed (NativeLocalDodgeBurnPointV1* localPoints = local.Points)
        fixed (NativeDefectRegionEditV1* defectRegionEdits = defects.Edits)
        fixed (byte* defectMaskBytes = defects.MaskBytes)
        fixed (byte* defectSourceDigest = defectSourceSha256)
        fixed (NativeDefectCloneEditV1* defectCloneEdits = clones.Edits)
        fixed (NativeDefectCloneStrokeV1* defectCloneStrokes = clones.Strokes)
        fixed (NativeDefectClonePointV1* defectClonePoints = clones.Points)
        fixed (NativeDefectRecipeEditRefV1* nativeDefectEditOrder = defectEditOrder)
        fixed (NativeDefectBrushEditV1* defectBrushEdits = brushes.Edits)
        fixed (NativeDefectBrushStrokeV1* defectBrushStrokes = brushes.Strokes)
        fixed (NativeDefectBrushPointV1* defectBrushPoints = brushes.Points)
        fixed (NativeDefectInfraredEditV1* defectInfraredEdits =
            defects.InfraredEdits)
        fixed (byte* defectInfraredAttenuationBytes =
            defects.InfraredAttenuationBytes)
        fixed (NativeDefectInfraredItemV1* defectInfraredItems =
            defects.InfraredItems)
        {
            NativeDevelopExportRequestV20 v20 = BuildRequestV20(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId,
                scannerProfileId,
                localAdjustments,
                checked((uint)local.Adjustments.Length),
                localStrokes,
                checked((uint)local.Strokes.Length),
                localPoints,
                checked((uint)local.Points.Length),
                defectRegionEdits,
                checked((uint)defects.Edits.Length),
                defectMaskBytes,
                checked((uint)defects.MaskBytes.Length),
                defectSourceDigest,
                defectCloneEdits,
                checked((uint)clones.Edits.Length),
                defectCloneStrokes,
                checked((uint)clones.Strokes.Length),
                defectClonePoints,
                checked((uint)clones.Points.Length),
                nativeDefectEditOrder,
                checked((uint)defectEditOrder.Length));
            NativeDevelopExportRequestV21 v21 = BuildRequestV21(
                v20,
                defectBrushEdits,
                checked((uint)brushes.Edits.Length),
                defectBrushStrokes,
                checked((uint)brushes.Strokes.Length),
                defectBrushPoints,
                checked((uint)brushes.Points.Length));
            NativeDevelopExportRequestV24 v24 = BuildRequestV24(
                v21,
                defectInfraredEdits,
                checked((uint)defects.InfraredEdits.Length),
                defectInfraredAttenuationBytes,
                checked((uint)defects.InfraredAttenuationBytes.Length));
            NativeDevelopExportRequestV25 native = BuildRequestV25(
                v24,
                defectInfraredItems,
                checked((uint)defects.InfraredItems.Length));
            status = NativeMethods.nf_develop_export_v25(
                &native,
                runState,
                &raw);
        }

        return Translate(status, raw, "nf_develop_export_v25");
    }

    /// <summary>
    /// 같은 파이프라인을 돌리되 파일을 쓰지 않고 <paramref name="pixels"/> 에 BGRA8 표시용
    /// 비트맵을 채웁니다. 실제로 쓰인 크기는 결과의 <c>ImageWidth</c>/<c>ImageHeight</c> 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Run"/> 과 마찬가지로 블로킹입니다. UI 스레드에서 부르지 마십시오.
    /// </remarks>
    /// <param name="softProof">
    /// 보기용 시뮬레이션입니다. null 이면 프루프 없는 미리보기이고, 그 결과는 프루프 인자를
    /// 도입하기 전과 바이트 단위로 같습니다. <see cref="Run"/> 에는 대응하는 인자가 없습니다 —
    /// 인화물은 시뮬레이션을 담지 않습니다.
    /// </param>
    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);
        if (pixels.IsEmpty)
        {
            throw new ArgumentException("The preview buffer is empty.", nameof(pixels));
        }
        ValidateLayoutAndEnums(request);
        NativeLocalDodgeBurnPayload local = BuildLocalDodgeBurnPayload(
            request.LocalDodgeBurn);
        NativeDefectRegionPayload defects = BuildDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared);
        NativeDefectClonePayload clones = BuildDefectClonePayload(
            request.DefectClones);
        NativeDefectBrushPayload brushes = BuildDefectBrushPayload(
            request.DefectBrushes);
        NativeDefectRecipeEditRefV1[] defectEditOrder = BuildDefectEditOrder(request);
        byte[] defectSourceSha256 = BuildDefectSourceSha256(request);

        NativeDevelopExportResultV3 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV3);
        uint status;

        // A null run state is the pre-v22 behaviour: the call simply runs to the end.
        NativeDevelopRunStateV1* runState = run is null ? null : run.StatePointer;

        NativeSoftProofV1 nativeProof = default;
        if (softProof is not null)
        {
            nativeProof.StructSize = (uint)sizeof(NativeSoftProofV1);
            nativeProof.Enabled = softProof.IsEnabled ? 1U : 0U;
            nativeProof.SimulatePaperAndBlackInk =
                softProof.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1U : 0U;
            nativeProof.PaperWhiteRgb[0] = (float)softProof.PaperWhite.Red;
            nativeProof.PaperWhiteRgb[1] = (float)softProof.PaperWhite.Green;
            nativeProof.PaperWhiteRgb[2] = (float)softProof.PaperWhite.Blue;
            nativeProof.BlackInkRgb[0] = (float)softProof.BlackInk.Red;
            nativeProof.BlackInkRgb[1] = (float)softProof.BlackInk.Green;
            nativeProof.BlackInkRgb[2] = (float)softProof.BlackInk.Blue;
        }
        NativeSoftProofV1* proofPointer = softProof is null ? null : &nativeProof;

        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        fixed (char* scannerProfileId = request.ScannerProfileId)
        fixed (byte* pixelBuffer = pixels)
        fixed (NativeLocalDodgeBurnAdjustmentV1* localAdjustments = local.Adjustments)
        fixed (NativeLocalDodgeBurnStrokeV1* localStrokes = local.Strokes)
        fixed (NativeLocalDodgeBurnPointV1* localPoints = local.Points)
        fixed (NativeDefectRegionEditV1* defectRegionEdits = defects.Edits)
        fixed (byte* defectMaskBytes = defects.MaskBytes)
        fixed (byte* defectSourceDigest = defectSourceSha256)
        fixed (NativeDefectCloneEditV1* defectCloneEdits = clones.Edits)
        fixed (NativeDefectCloneStrokeV1* defectCloneStrokes = clones.Strokes)
        fixed (NativeDefectClonePointV1* defectClonePoints = clones.Points)
        fixed (NativeDefectRecipeEditRefV1* nativeDefectEditOrder = defectEditOrder)
        fixed (NativeDefectBrushEditV1* defectBrushEdits = brushes.Edits)
        fixed (NativeDefectBrushStrokeV1* defectBrushStrokes = brushes.Strokes)
        fixed (NativeDefectBrushPointV1* defectBrushPoints = brushes.Points)
        fixed (NativeDefectInfraredEditV1* defectInfraredEdits =
            defects.InfraredEdits)
        fixed (byte* defectInfraredAttenuationBytes =
            defects.InfraredAttenuationBytes)
        fixed (NativeDefectInfraredItemV1* defectInfraredItems =
            defects.InfraredItems)
        {
            NativeDevelopExportRequestV20 v20 = BuildRequestV20(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId,
                scannerProfileId,
                localAdjustments,
                checked((uint)local.Adjustments.Length),
                localStrokes,
                checked((uint)local.Strokes.Length),
                localPoints,
                checked((uint)local.Points.Length),
                defectRegionEdits,
                checked((uint)defects.Edits.Length),
                defectMaskBytes,
                checked((uint)defects.MaskBytes.Length),
                defectSourceDigest,
                defectCloneEdits,
                checked((uint)clones.Edits.Length),
                defectCloneStrokes,
                checked((uint)clones.Strokes.Length),
                defectClonePoints,
                checked((uint)clones.Points.Length),
                nativeDefectEditOrder,
                checked((uint)defectEditOrder.Length));
            NativeDevelopExportRequestV21 v21 = BuildRequestV21(
                v20,
                defectBrushEdits,
                checked((uint)brushes.Edits.Length),
                defectBrushStrokes,
                checked((uint)brushes.Strokes.Length),
                defectBrushPoints,
                checked((uint)brushes.Points.Length));
            NativeDevelopExportRequestV24 v24 = BuildRequestV24(
                v21,
                defectInfraredEdits,
                checked((uint)defects.InfraredEdits.Length),
                defectInfraredAttenuationBytes,
                checked((uint)defects.InfraredAttenuationBytes.Length));
            NativeDevelopExportRequestV25 native = BuildRequestV25(
                v24,
                defectInfraredItems,
                checked((uint)defects.InfraredItems.Length));
            status = NativeMethods.nf_develop_preview_v25(
                &native,
                proofPointer,
                maximumWidth,
                maximumHeight,
                pixelBuffer,
                (uint)Math.Min(pixels.Length, int.MaxValue),
                runState,
                &raw);
        }

        return Translate(status, raw, "nf_develop_preview_v25");
    }

    private static DevelopExportResult Translate(
        uint status,
        NativeDevelopExportResultV3 raw,
        string functionName)
    {
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                status switch
                {
                    StatusInvalidArgument =>
                    $"{functionName} rejected the call as malformed.",
                    StatusStructTooSmall =>
                    $"{functionName} rejected the struct sizes.",
                    _ => $"{functionName} failed with status {status}.",
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
            baseSource,
            raw.Cancelled != 0);
    }
}
