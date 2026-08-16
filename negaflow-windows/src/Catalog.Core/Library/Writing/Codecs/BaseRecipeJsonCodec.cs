using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class BaseRecipeJsonCodec
{
    internal static bool IsValid(ManualBaseRgb manual) =>
        double.IsFinite(manual.Red) && double.IsFinite(manual.Green) &&
        double.IsFinite(manual.Blue);

    internal static bool IsValid(ManualBaseRgb? manual, BaseRecipe? recipe) =>
        (manual is null || IsValid(manual.Value)) &&
        (recipe is null || IsValid(recipe));

    internal static bool IsValid(BaseRecipe recipe) =>
        Enum.IsDefined(recipe.Mode) &&
        IsValidOptionalIdentifier(recipe.FilmStockDminId) &&
        IsValidOptionalIdentifier(recipe.LightSourceProfileId) &&
        IsValidOptionalIdentifier(recipe.ScannerProfileId);

    internal static void Write(
        JsonObject parameters,
        ManualBaseRgb? manual,
        BaseRecipe? recipe)
    {
        if (manual is { } writtenBase)
        {
            parameters[LibraryFrameReader.ManualBaseName] = new JsonArray(
                writtenBase.Red,
                writtenBase.Green,
                writtenBase.Blue);
        }
        else
        {
            parameters.Remove(LibraryFrameReader.ManualBaseName);
        }

        if (recipe is not { } baseRecipe)
        {
            return;
        }
        parameters[LibraryFrameReader.BaseEstimationModeName] = ToStorageName(baseRecipe.Mode);
        WriteOptionalIdentifier(
            parameters,
            LibraryFrameReader.FilmStockDminIdName,
            baseRecipe.FilmStockDminId);
        WriteOptionalIdentifier(
            parameters,
            LibraryFrameReader.LightSourceProfileIdName,
            baseRecipe.LightSourceProfileId);
        WriteOptionalIdentifier(
            parameters,
            LibraryFrameReader.ScannerProfileIdName,
            baseRecipe.ScannerProfileId);
    }

    private static bool IsValidOptionalIdentifier(string? identifier) =>
        identifier is null || !string.IsNullOrWhiteSpace(identifier);

    private static string ToStorageName(BaseEstimationMode mode) => mode switch
    {
        BaseEstimationMode.Auto => "auto",
        BaseEstimationMode.Manual => "manual",
        BaseEstimationMode.Preset => "preset",
        _ => throw new ArgumentOutOfRangeException(nameof(mode)),
    };

    private static void WriteOptionalIdentifier(
        JsonObject parameters,
        string name,
        string? value)
    {
        if (value is null)
        {
            parameters.Remove(name);
        }
        else
        {
            parameters[name] = value;
        }
    }
}
