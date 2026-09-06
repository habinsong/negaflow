using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class InputGammaJsonCodec
{
    private const string Key = "inputGamma";

    internal static bool TryRead(JsonElement parameters, out InputGammaInterpretation gamma)
    {
        gamma = InputGammaInterpretation.Automatic;
        if (!parameters.TryGetProperty(Key, out JsonElement element)) { return true; }
        if (element.ValueKind == JsonValueKind.String && element.GetString() == "auto") { return true; }
        if (element.ValueKind != JsonValueKind.Number || !element.TryGetDouble(out double value) ||
            !InputGammaInterpretation.IsValidPower(value)) { return false; }
        gamma = InputGammaInterpretation.Power(value);
        return true;
    }

    internal static void Write(JsonObject parameters, InputGammaInterpretation? gamma)
    {
        if (gamma is not { } changed) { return; }
        if (changed.Value is { } value) { parameters[Key] = value; }
        else { parameters.Remove(Key); }
    }
}
