namespace Negaflow.Interop;

/// <summary>톤·색·캘리브레이션 검증입니다. 결함 레시피와 다른 이유입니다.</summary>
internal static class NativeDevelopToneValidator
{
    internal static bool Normalized(float value) =>
        float.IsFinite(value) && value is >= 0.0F and <= 1.0F;

    internal static bool SignedNormalized(float value) =>
        float.IsFinite(value) && value is >= -1.0F and <= 1.0F;

    internal static void ValidatePointCurves(DevelopPointCurves pointCurves)
    {
        ArgumentNullException.ThrowIfNull(pointCurves);
        ValidatePointCurve(pointCurves.Rgb, nameof(pointCurves.Rgb));
        ValidatePointCurve(pointCurves.Red, nameof(pointCurves.Red));
        ValidatePointCurve(pointCurves.Green, nameof(pointCurves.Green));
        ValidatePointCurve(pointCurves.Blue, nameof(pointCurves.Blue));
    }

    internal static void ValidatePointCurve(
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

    internal static void ValidateColorMixer(DevelopColorMixer colorMixer)
    {
        ArgumentNullException.ThrowIfNull(colorMixer);
        ValidateColorMixerChannel(colorMixer.Hue, nameof(colorMixer.Hue));
        ValidateColorMixerChannel(colorMixer.Saturation, nameof(colorMixer.Saturation));
        ValidateColorMixerChannel(colorMixer.Luminance, nameof(colorMixer.Luminance));
    }

    internal static void ValidateColorMixerChannel(IReadOnlyList<float> values, string parameterName)
    {
        ArgumentNullException.ThrowIfNull(values);
        if (values.Count != DevelopColorMixer.BandCount ||
            values.Any(value => !float.IsFinite(value) || value is < -1.0F or > 1.0F))
        {
            throw new ArgumentException("A Color Mixer channel must contain eight finite values from -1 to 1.", parameterName);
        }
    }

    internal static void ValidateColorGrading(DevelopColorGrading colorGrading)
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

    internal static void ValidateColorGradeRegion(DevelopColorGradeRegion region, string parameterName)
    {
        if (!float.IsFinite(region.Hue) || region.Hue is < 0.0F or > 360.0F ||
            !float.IsFinite(region.Saturation) || region.Saturation is < 0.0F or > 1.0F ||
            !float.IsFinite(region.Luminance) || region.Luminance is < -1.0F or > 1.0F)
        {
            throw new ArgumentException("A Color Grading region is invalid.", parameterName);
        }
    }

    internal static void ValidatePrimaryCalibration(DevelopPrimaryCalibration calibration)
    {
        ArgumentNullException.ThrowIfNull(calibration);
        if (!SignedNormalized(calibration.RedHue) ||
            !SignedNormalized(calibration.RedSaturation) ||
            !SignedNormalized(calibration.GreenHue) ||
            !SignedNormalized(calibration.GreenSaturation) ||
            !SignedNormalized(calibration.BlueHue) ||
            !SignedNormalized(calibration.BlueSaturation))
        {
            throw new ArgumentException(
                "Primary Calibration controls are outside the supported finite range.",
                nameof(calibration));
        }
    }
}
