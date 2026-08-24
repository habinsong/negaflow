using Negaflow.Catalog;

namespace Negaflow.Shell;

public sealed partial class LibraryDocument
{
    internal bool MatchesDefectBakeSource(
        string frameId,
        DefectRecipeSnapshot expectedRecipe,
        string expectedSourcePath) =>
        defectRecipeStore.MatchesBakeSource(frameId, expectedRecipe, expectedSourcePath);

    internal LibraryDefectRecipeWriteResult CompleteDefectBake(
        string frameId,
        DefectRecipeSnapshot expectedRecipe,
        string expectedSourcePath,
        string? bakedSourcePath = null,
        LibrarySourceMetadata? bakedMetadata = null) =>
        CompleteDefectBakeCore(
            frameId,
            expectedRecipe,
            expectedSourcePath,
            bakedSourcePath,
            bakedMetadata);

    private LibraryDefectRecipeWriteResult CompleteDefectBakeCore(
        string frameId,
        DefectRecipeSnapshot expectedRecipe,
        string expectedSourcePath,
        string? bakedSourcePath,
        LibrarySourceMetadata? bakedMetadata)
    {
        LibraryDefectRecipeWriteResult result = defectRecipeStore.CompleteBake(
            frameId, expectedRecipe, expectedSourcePath, bakedSourcePath, bakedMetadata);
        if (result.IsSuccess)
        {
            undo.RemoveDefectFrame(frameId);
        }
        return result;
    }
}
