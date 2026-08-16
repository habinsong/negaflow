using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class BaseRecipeJsonReader
{
    internal static bool TryReadManualBase(
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

    internal static bool TryReadBaseRecipe(
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

    internal static bool TryReadOptionalIdentifier(
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

}
