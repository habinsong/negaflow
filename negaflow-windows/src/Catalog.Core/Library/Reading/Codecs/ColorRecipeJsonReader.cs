using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryJsonValueReader;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class ColorRecipeJsonReader
{
    internal static bool TryReadPointCurves(
        JsonElement parameters,
        out PointCurveRecipe pointCurves)
    {
        pointCurves = PointCurveRecipe.Identity;
        if (!parameters.TryGetProperty(PointCurvesName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadPointCurveChannel(element, PointCurveRgbName, out IReadOnlyList<PointCurvePoint> rgb) ||
            !TryReadPointCurveChannel(element, PointCurveRedName, out IReadOnlyList<PointCurvePoint> red) ||
            !TryReadPointCurveChannel(element, PointCurveGreenName, out IReadOnlyList<PointCurvePoint> green) ||
            !TryReadPointCurveChannel(element, PointCurveBlueName, out IReadOnlyList<PointCurvePoint> blue))
        {
            return false;
        }

        pointCurves = new PointCurveRecipe(rgb, red, green, blue);
        return true;
    }

    internal static bool TryReadPointCurveChannel(
        JsonElement pointCurves,
        string channelName,
        out IReadOnlyList<PointCurvePoint> points)
    {
        points = [];
        if (!pointCurves.TryGetProperty(channelName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > PointCurveRecipe.MaximumPointsPerChannel)
        {
            return false;
        }

        List<PointCurvePoint> parsed = new(element.GetArrayLength());
        foreach (JsonElement point in element.EnumerateArray())
        {
            if (point.ValueKind != JsonValueKind.Object ||
                !point.TryGetProperty(PointCurveXName, out JsonElement xElement) ||
                !point.TryGetProperty(PointCurveYName, out JsonElement yElement) ||
                xElement.ValueKind != JsonValueKind.Number ||
                yElement.ValueKind != JsonValueKind.Number ||
                !xElement.TryGetDouble(out double x) ||
                !yElement.TryGetDouble(out double y) ||
                !double.IsFinite(x) || !double.IsFinite(y) ||
                x is < 0.0 or > 1.0 || y is < 0.0 or > 1.0)
            {
                return false;
            }
            parsed.Add(new PointCurvePoint(x, y));
        }

        parsed.Sort(static (left, right) => left.X.CompareTo(right.X));
        for (int index = 1; index < parsed.Count; index++)
        {
            if (parsed[index].X - parsed[index - 1].X < 1.0e-9)
            {
                return false;
            }
        }
        points = parsed;
        return true;
    }

    internal static bool TryReadColorMixer(JsonElement parameters, out ColorMixerRecipe colorMixer)
    {
        colorMixer = ColorMixerRecipe.Identity;
        if (!parameters.TryGetProperty(ColorMixerName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadColorMixerChannel(element, ColorMixerHueName, out IReadOnlyList<double> hue) ||
            !TryReadColorMixerChannel(element, ColorMixerSaturationName, out IReadOnlyList<double> saturation) ||
            !TryReadColorMixerChannel(element, ColorMixerLuminanceName, out IReadOnlyList<double> luminance))
        {
            return false;
        }
        colorMixer = new ColorMixerRecipe(hue, saturation, luminance);
        return true;
    }

    internal static bool TryReadColorMixerChannel(
        JsonElement colorMixer,
        string channelName,
        out IReadOnlyList<double> values)
    {
        values = new double[ColorMixerRecipe.BandCount];
        if (!colorMixer.TryGetProperty(channelName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array ||
            element.GetArrayLength() > ColorMixerRecipe.BandCount)
        {
            return false;
        }
        double[] parsed = new double[ColorMixerRecipe.BandCount];
        int index = 0;
        foreach (JsonElement value in element.EnumerateArray())
        {
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out double parsedValue) ||
                !double.IsFinite(parsedValue) || parsedValue is < -1.0 or > 1.0)
            {
                return false;
            }
            parsed[index++] = parsedValue;
        }
        values = parsed;
        return true;
    }

    /// <summary>
    /// 색조 두 값은 키가 없으면 0 이 아니라 <b>그 모드의 기본 색조</b>입니다. macOS 와 같으며,
    /// 0 으로 채우면 sepia 를 골랐을 뿐인데 전혀 다른 색으로 물듭니다.
    /// </summary>

    internal static bool TryReadColorGrading(JsonElement parameters, out ColorGradingRecipe colorGrading)
    {
        colorGrading = ColorGradingRecipe.Identity;
        if (!parameters.TryGetProperty(ColorGradingName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadColorGradeRegion(element, ColorGradingShadowsName, out ColorGradeRegionRecipe shadows) ||
            !TryReadColorGradeRegion(element, ColorGradingMidtonesName, out ColorGradeRegionRecipe midtones) ||
            !TryReadColorGradeRegion(element, ColorGradingHighlightsName, out ColorGradeRegionRecipe highlights) ||
            !TryReadFiniteDouble(element, ColorGradingBlendingName, out double blending) ||
            !TryReadFiniteDouble(element, ColorGradingBalanceName, out double balance) ||
            blending is < 0.0 or > 1.0 || balance is < -1.0 or > 1.0)
        {
            return false;
        }
        colorGrading = new ColorGradingRecipe(shadows, midtones, highlights, blending, balance);
        return true;
    }

    internal static bool TryReadColorGradeRegion(
        JsonElement colorGrading,
        string name,
        out ColorGradeRegionRecipe region)
    {
        region = default;
        if (!colorGrading.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind != JsonValueKind.Object ||
            !TryReadFiniteDouble(element, ColorGradingHueName, out double hue) ||
            !TryReadFiniteDouble(element, ColorGradingSaturationName, out double saturation) ||
            !TryReadFiniteDouble(element, ColorGradingLuminanceName, out double luminance) ||
            hue is < 0.0 or > 360.0 || saturation is < 0.0 or > 1.0 ||
            luminance is < -1.0 or > 1.0)
        {
            return false;
        }
        region = new ColorGradeRegionRecipe(hue, saturation, luminance);
        return true;
    }

    internal static bool TryReadPrimaryCalibration(
        JsonElement parameters,
        out PrimaryCalibrationRecipe calibration)
    {
        calibration = PrimaryCalibrationRecipe.Identity;
        if (!parameters.TryGetProperty(PrimaryCalibrationName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Object ||
            !TryReadFiniteDouble(element, PrimaryCalibrationRedHueName, out double redHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationRedSaturationName, out double redSaturation) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationGreenHueName, out double greenHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationGreenSaturationName, out double greenSaturation) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationBlueHueName, out double blueHue) ||
            !TryReadFiniteDouble(element, PrimaryCalibrationBlueSaturationName, out double blueSaturation) ||
            new[] { redHue, redSaturation, greenHue, greenSaturation, blueHue, blueSaturation }
                .Any(value => value is < -1.0 or > 1.0))
        {
            return false;
        }
        calibration = new PrimaryCalibrationRecipe(
            redHue, redSaturation, greenHue, greenSaturation, blueHue, blueSaturation);
        return true;
    }

    // 키가 없으면 macOS 와 같이 0 입니다. 있는데 수가 아니면 조용히 0 으로 만들지 않고 거부합니다.

    internal static bool TryReadDevelopTarget(
        JsonElement parameters,
        out DevelopTarget developTarget)
    {
        developTarget = DevelopTarget.Main;
        if (!parameters.TryGetProperty(DevelopTargetName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String)
        {
            return false;
        }
        developTarget = element.GetString() switch
        {
            "main" => DevelopTarget.Main,
            "print" => DevelopTarget.Print,
            "noritsu" => DevelopTarget.Noritsu,
            "sp-3000" => DevelopTarget.Sp3000,
            "f135" => DevelopTarget.F135,
            "hr" => DevelopTarget.Hr,
            "rescue" => DevelopTarget.Rescue,
            _ => (DevelopTarget)(-1),
        };
        return Enum.IsDefined(developTarget);
    }

    internal static bool TryReadColorModel(
        JsonElement parameters,
        out ColorModelRecipe colorModel)
    {
        if (!TryReadFiniteDouble(parameters, WarmthName, out double warmth) ||
            !TryReadFiniteDouble(parameters, TintName, out double tint) ||
            !TryReadFiniteDouble(parameters, ColorDepthName, out double colorDepth) ||
            !TryReadFiniteDouble(parameters, VibranceName, out double vibrance) ||
            !TryReadFiniteDouble(parameters, SaturationName, out double saturation) ||
            !TryReadFiniteDouble(parameters, RedPrimaryName, out double redPrimary) ||
            !TryReadFiniteDouble(parameters, GreenPrimaryName, out double greenPrimary) ||
            !TryReadFiniteDouble(parameters, BluePrimaryName, out double bluePrimary))
        {
            colorModel = ColorModelRecipe.Identity;
            return false;
        }
        colorModel = new ColorModelRecipe(
            warmth, tint, colorDepth, vibrance, saturation,
            redPrimary, greenPrimary, bluePrimary);
        return colorModel.IsValid();
    }

}
