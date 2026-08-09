using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>셸이 한 번에 바꾸는 값들입니다. 지정하지 않은 것은 그대로 둡니다.</summary>
public sealed record LibraryFrameEdit(
    ToneAdjustment Tone,
    ManualBaseRgb? ManualBase,
    BaseRecipe? Base = null);

/// <summary>
/// 톤, 수동 base, 그리고 지정된 경우 base recipe를 갱신합니다. 입력 record 는 바꾸지 않고 깊은 복사본을 돌려주며, 이 writer 가
/// 모르는 frame/params field 는 전부 보존합니다. develop route 는
/// <see cref="DevelopRouteWriter"/> 가 계속 소유합니다.
/// </summary>
public static class LibraryFrameWriter
{
    public static LibraryFrameWriteResult Apply(JsonObject frameRecord, LibraryFrameEdit edit)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        ArgumentNullException.ThrowIfNull(edit);

        if (!IsFiniteTone(edit.Tone))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidToneValue);
        }
        if (edit.ManualBase is { } manualBase &&
            (!double.IsFinite(manualBase.Red) ||
             !double.IsFinite(manualBase.Green) ||
             !double.IsFinite(manualBase.Blue)))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidManualBase);
        }
        if (edit.Base is { } baseRecipe && !IsValidBaseRecipe(baseRecipe))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidBaseRecipe);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        JsonObject parameters;
        if (!updated.TryGetPropertyValue(
                LibraryFrameReader.ParametersName,
                out JsonNode? parameterNode) ||
            parameterNode is null)
        {
            parameters = [];
            updated[LibraryFrameReader.ParametersName] = parameters;
        }
        else if (parameterNode is JsonObject parameterObject)
        {
            parameters = parameterObject;
        }
        else
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingParameters);
        }

        parameters[LibraryFrameReader.ExposureName] = edit.Tone.Exposure;
        parameters[LibraryFrameReader.ContrastName] = edit.Tone.Contrast;
        parameters[LibraryFrameReader.DensityName] = edit.Tone.Density;
        parameters[LibraryFrameReader.HighlightName] = edit.Tone.Highlight;
        parameters[LibraryFrameReader.ShadowName] = edit.Tone.Shadow;
        parameters[LibraryFrameReader.WhitesName] = edit.Tone.Whites;
        parameters[LibraryFrameReader.BlacksName] = edit.Tone.Blacks;
        parameters[LibraryFrameReader.CurveHighlightsName] = edit.Tone.CurveHighlights;
        parameters[LibraryFrameReader.CurveLightsName] = edit.Tone.CurveLights;
        parameters[LibraryFrameReader.CurveDarksName] = edit.Tone.CurveDarks;
        parameters[LibraryFrameReader.CurveShadowsName] = edit.Tone.CurveShadows;

        if (edit.ManualBase is { } writtenBase)
        {
            parameters[LibraryFrameReader.ManualBaseName] = new JsonArray(
                writtenBase.Red,
                writtenBase.Green,
                writtenBase.Blue);
        }
        else
        {
            // nil 은 macOS 에서 auto base 추정을 뜻합니다. `false` 나 0 을 쓰면 의미가 달라지므로
            // 키를 지웁니다.
            parameters.Remove(LibraryFrameReader.ManualBaseName);
        }

        if (edit.Base is { } baseRecipeToWrite)
        {
            parameters[LibraryFrameReader.BaseEstimationModeName] = ToStorageName(baseRecipeToWrite.Mode);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.FilmStockDminIdName,
                baseRecipeToWrite.FilmStockDminId);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.LightSourceProfileIdName,
                baseRecipeToWrite.LightSourceProfileId);
            WriteOptionalIdentifier(
                parameters,
                LibraryFrameReader.ScannerProfileIdName,
                baseRecipeToWrite.ScannerProfileId);
        }

        return LibraryFrameWriteResult.Success(updated);
    }

    private static bool IsValidBaseRecipe(BaseRecipe recipe) =>
        Enum.IsDefined(recipe.Mode) &&
        IsValidOptionalIdentifier(recipe.FilmStockDminId) &&
        IsValidOptionalIdentifier(recipe.LightSourceProfileId) &&
        IsValidOptionalIdentifier(recipe.ScannerProfileId);

    private static bool IsValidOptionalIdentifier(string? identifier) =>
        identifier is null || !string.IsNullOrWhiteSpace(identifier);

    private static string ToStorageName(BaseEstimationMode mode) => mode switch
    {
        BaseEstimationMode.Auto => "auto",
        BaseEstimationMode.Preset => "preset",
        BaseEstimationMode.Manual => "manual",
        _ => throw new ArgumentOutOfRangeException(nameof(mode)),
    };

    private static void WriteOptionalIdentifier(
        JsonObject parameters,
        string name,
        string? identifier)
    {
        if (identifier is null)
        {
            parameters.Remove(name);
        }
        else
        {
            parameters[name] = identifier;
        }
    }

    private static bool IsFiniteTone(ToneAdjustment tone) =>
        double.IsFinite(tone.Exposure) &&
        double.IsFinite(tone.Contrast) &&
        double.IsFinite(tone.Density) &&
        double.IsFinite(tone.Highlight) &&
        double.IsFinite(tone.Shadow) &&
        double.IsFinite(tone.Whites) &&
        double.IsFinite(tone.Blacks) &&
        double.IsFinite(tone.CurveHighlights) &&
        double.IsFinite(tone.CurveLights) &&
        double.IsFinite(tone.CurveDarks) &&
        double.IsFinite(tone.CurveShadows);
}
