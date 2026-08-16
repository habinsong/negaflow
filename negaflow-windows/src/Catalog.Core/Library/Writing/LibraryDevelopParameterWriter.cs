using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class LibraryDevelopParameterWriter
{
    internal static LibraryFrameError Apply(JsonObject updated, LibraryFrameEdit edit)
    {
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
            return LibraryFrameError.MissingParameters;
        }

        ToneRecipeJsonCodec.Write(parameters, edit.Tone);
        BaseRecipeJsonCodec.Write(parameters, edit.ManualBase, edit.Base);
        ColorRecipeJsonCodec.Write(parameters, edit);
        if (edit.LocalDodgeBurn is { } localDodgeBurn)
        {
            parameters[LibraryFrameReader.LocalDodgeBurnName] =
                LocalDodgeBurnJsonCodec.Write(localDodgeBurn);
        }
        ImageEffectRecipeJsonCodec.Write(parameters, edit);
        return LibraryFrameError.None;
    }
}
