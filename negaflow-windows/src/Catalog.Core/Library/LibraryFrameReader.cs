using System.Text.Json;

namespace Negaflow.Catalog;

/// <summary>
/// catalog frame payload 를 셸이 쓸 수 있는 형태로 투영합니다. key 이름은 macOS 와 같습니다 —
/// <c>rawScanPath</c>, <c>customDisplayName</c>, <c>params.manualBaseRGB</c>,
/// <c>params.exposure</c> 계열 — 그래야 recipe payload 수준의 호환이 유지됩니다.
/// develop route 부분은 <see cref="DevelopRouteReader"/> 가 계속 소유합니다.
/// </summary>
public static class LibraryFrameReader
{
    internal const string IdName = "id";
    internal const string SourcePathName = "rawScanPath";
    internal const string DisplayNameName = "customDisplayName";
    internal const string ParametersName = "params";
    internal const string BaseEstimationModeName = "baseEstimationMode";
    internal const string ManualBaseName = "manualBaseRGB";
    internal const string FilmStockDminIdName = "filmStockDminID";
    internal const string LightSourceProfileIdName = "lightSourceProfileID";
    internal const string ScannerProfileIdName = "scannerProfileID";
    internal const string ExposureName = "exposure";
    internal const string ContrastName = "contrast";
    internal const string DensityName = "density";
    internal const string HighlightName = "highlight";
    internal const string ShadowName = "shadow";
    internal const string WhitesName = "whites";
    internal const string BlacksName = "blacks";
    internal const string CurveHighlightsName = "curveHighlights";
    internal const string CurveLightsName = "curveLights";
    internal const string CurveDarksName = "curveDarks";
    internal const string CurveShadowsName = "curveShadows";
    internal const string PointCurvesName = "pointCurves";
    internal const string PointCurveRgbName = "rgb";
    internal const string PointCurveRedName = "red";
    internal const string PointCurveGreenName = "green";
    internal const string PointCurveBlueName = "blue";
    internal const string PointCurveXName = "x";
    internal const string PointCurveYName = "y";
    internal const string ColorMixerName = "colorMixer";
    internal const string ColorMixerHueName = "hue";
    internal const string ColorMixerSaturationName = "saturation";
    internal const string ColorMixerLuminanceName = "luminance";

    public static LibraryFrameReadResult Read(JsonElement frameRecord)
    {
        if (frameRecord.ValueKind != JsonValueKind.Object)
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.FrameNotObject);
        }

        if (!frameRecord.TryGetProperty(IdName, out JsonElement idElement))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingId);
        }
        if (idElement.ValueKind != JsonValueKind.String ||
            idElement.GetString() is not { Length: > 0 } id ||
            string.IsNullOrWhiteSpace(id))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidId);
        }

        if (!frameRecord.TryGetProperty(SourcePathName, out JsonElement sourceElement))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingSourcePath);
        }
        if (sourceElement.ValueKind != JsonValueKind.String ||
            sourceElement.GetString() is not { Length: > 0 } sourcePath ||
            string.IsNullOrWhiteSpace(sourcePath) ||
            !Path.IsPathFullyQualified(sourcePath))
        {
            // 상대 경로는 무엇을 기준으로 푸는지가 catalog 에 없습니다. 추측해서 열면 엉뚱한 파일을
            // 현상할 수 있으므로 거부합니다.
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidSourcePath);
        }

        string? displayName = null;
        if (frameRecord.TryGetProperty(DisplayNameName, out JsonElement displayElement) &&
            displayElement.ValueKind != JsonValueKind.Null)
        {
            if (displayElement.ValueKind != JsonValueKind.String)
            {
                return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidDisplayName);
            }
            displayName = displayElement.GetString();
        }

        if (!frameRecord.TryGetProperty(ParametersName, out JsonElement parameters) ||
            parameters.ValueKind != JsonValueKind.Object)
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.MissingParameters);
        }

        if (!TryReadManualBase(parameters, out ManualBaseRgb? manualBase))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidManualBase);
        }
        if (!TryReadBaseRecipe(parameters, out BaseRecipe baseRecipe))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidBaseRecipe);
        }
        if (!TryReadTone(parameters, out ToneAdjustment tone))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidToneValue);
        }
        if (!TryReadPointCurves(parameters, out PointCurveRecipe pointCurves))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidPointCurves);
        }
        if (!TryReadColorMixer(parameters, out ColorMixerRecipe colorMixer))
        {
            return LibraryFrameReadResult.Failure(LibraryFrameError.InvalidColorMixer);
        }

        DevelopRouteReadResult route = DevelopRouteReader.Read(frameRecord);
        if (route.Route is not { } snapshot)
        {
            return LibraryFrameReadResult.RouteFailure(route.Error);
        }

        return LibraryFrameReadResult.Success(new LibraryFrameSnapshot(
            id,
            sourcePath,
            displayName,
            snapshot,
            manualBase,
            tone)
        {
            Base = baseRecipe,
            PointCurves = pointCurves,
            ColorMixer = colorMixer,
        });
    }

    private static bool TryReadManualBase(
        JsonElement parameters,
        out ManualBaseRgb? manualBase)
    {
        manualBase = null;
        if (!parameters.TryGetProperty(ManualBaseName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array || element.GetArrayLength() != 3)
        {
            return false;
        }

        Span<double> channels = stackalloc double[3];
        int index = 0;
        foreach (JsonElement channel in element.EnumerateArray())
        {
            if (channel.ValueKind != JsonValueKind.Number ||
                !channel.TryGetDouble(out double value) ||
                !double.IsFinite(value))
            {
                return false;
            }
            channels[index++] = value;
        }

        manualBase = new ManualBaseRgb(channels[0], channels[1], channels[2]);
        return true;
    }

    private static bool TryReadBaseRecipe(
        JsonElement parameters,
        out BaseRecipe baseRecipe)
    {
        baseRecipe = BaseRecipe.Auto;
        BaseEstimationMode mode = BaseEstimationMode.Auto;
        if (parameters.TryGetProperty(BaseEstimationModeName, out JsonElement modeElement) &&
            modeElement.ValueKind != JsonValueKind.Null)
        {
            if (modeElement.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            mode = modeElement.GetString() switch
            {
                "auto" => BaseEstimationMode.Auto,
                "preset" => BaseEstimationMode.Preset,
                "manual" => BaseEstimationMode.Manual,
                _ => (BaseEstimationMode)(-1),
            };
            if (!Enum.IsDefined(mode))
            {
                return false;
            }
        }

        if (!TryReadOptionalIdentifier(parameters, FilmStockDminIdName, out string? filmStockDminId) ||
            !TryReadOptionalIdentifier(parameters, LightSourceProfileIdName, out string? lightSourceProfileId) ||
            !TryReadOptionalIdentifier(parameters, ScannerProfileIdName, out string? scannerProfileId))
        {
            return false;
        }

        baseRecipe = new BaseRecipe(mode, filmStockDminId, lightSourceProfileId, scannerProfileId);
        return true;
    }

    private static bool TryReadOptionalIdentifier(
        JsonElement parameters,
        string name,
        out string? identifier)
    {
        identifier = null;
        if (!parameters.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(element.GetString()))
        {
            return false;
        }

        identifier = element.GetString();
        return true;
    }

    private static bool TryReadTone(JsonElement parameters, out ToneAdjustment tone)
    {
        tone = default;
        if (!TryReadFiniteDouble(parameters, ExposureName, out double exposure) ||
            !TryReadFiniteDouble(parameters, ContrastName, out double contrast) ||
            !TryReadFiniteDouble(parameters, DensityName, out double density) ||
            !TryReadFiniteDouble(parameters, HighlightName, out double highlight) ||
            !TryReadFiniteDouble(parameters, ShadowName, out double shadow) ||
            !TryReadFiniteDouble(parameters, WhitesName, out double whites) ||
            !TryReadFiniteDouble(parameters, BlacksName, out double blacks) ||
            !TryReadFiniteDouble(parameters, CurveHighlightsName, out double highlights) ||
            !TryReadFiniteDouble(parameters, CurveLightsName, out double lights) ||
            !TryReadFiniteDouble(parameters, CurveDarksName, out double darks) ||
            !TryReadFiniteDouble(parameters, CurveShadowsName, out double shadows))
        {
            return false;
        }

        tone = new ToneAdjustment(
            exposure,
            contrast,
            highlights,
            lights,
            darks,
            shadows,
            density,
            highlight,
            shadow,
            whites,
            blacks);
        return true;
    }

    private static bool TryReadPointCurves(
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

    private static bool TryReadPointCurveChannel(
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

    private static bool TryReadColorMixer(JsonElement parameters, out ColorMixerRecipe colorMixer)
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

    private static bool TryReadColorMixerChannel(
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

    // 키가 없으면 macOS 와 같이 0 입니다. 있는데 수가 아니면 조용히 0 으로 만들지 않고 거부합니다.
    private static bool TryReadFiniteDouble(
        JsonElement parameters,
        string name,
        out double value)
    {
        value = 0.0;
        if (!parameters.TryGetProperty(name, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Number ||
            !element.TryGetDouble(out double parsed) ||
            !double.IsFinite(parsed))
        {
            return false;
        }
        value = parsed;
        return true;
    }
}
