using System.Globalization;
using System.Text.Json;
using static Negaflow.Catalog.LibraryFrameReader;

namespace Negaflow.Catalog;

internal static class LibraryJsonValueReader
{
    internal static bool TryReadOptionalFiniteDouble(
        JsonElement owner,
        string name,
        double defaultValue,
        out double value)
    {
        value = defaultValue;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        return element.ValueKind == JsonValueKind.Number &&
               element.TryGetDouble(out value) && double.IsFinite(value);
    }

    internal static bool TryReadOptionalBoolean(
        JsonElement owner,
        string name,
        bool defaultValue,
        out bool value)
    {
        value = defaultValue;
        if (!owner.TryGetProperty(name, out JsonElement element) || element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            return false;
        }
        value = element.GetBoolean();
        return true;
    }


    internal static bool TryReadFiniteDouble(
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
