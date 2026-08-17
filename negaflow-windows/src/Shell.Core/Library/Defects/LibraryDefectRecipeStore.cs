using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>결함 recipe sidecar와 catalog 선언을 일관되게 쓰고 정리합니다.</summary>
internal sealed class LibraryDefectRecipeStore(
    LibraryDocumentState state,
    LibraryCatalogPersistence persistence)
{
    public LibraryDefectRecipeWriteResult Write(
        string frameId,
        DefectRecipeSnapshot recipe)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(recipe);
        if (!state.IndexById.TryGetValue(frameId, out int index) ||
            !Guid.TryParseExact(frameId, "D", out Guid parsedFrameId) ||
            parsedFrameId != recipe.FrameId)
        {
            return new(null, LibraryFrameError.MissingId,
                DefectSidecarError.None, CatalogStoreError.None);
        }

        DefectSidecarWriteResult sidecar = state.Session.WriteDefectRecipe(recipe);
        if (!sidecar.IsSuccess)
        {
            return new(null, LibraryFrameError.None, sidecar.Error, CatalogStoreError.None);
        }
        DefectSidecarReadResult read = state.Session.ReadDefectRecipe(parsedFrameId);
        if (read.Snapshot is not { } stored)
        {
            return new(null, LibraryFrameError.None, read.Error, CatalogStoreError.None);
        }

        JsonObject previousPayload = state.Payloads[index];
        DefectRecipeSnapshot? previousRecipe = state.DefectRecipes.GetValueOrDefault(frameId);
        JsonObject updatedPayload = (JsonObject)previousPayload.DeepClone();
        updatedPayload["hasDefectEdits"] = true;
        state.Payloads[index] = updatedPayload;
        state.DefectRecipes[frameId] = stored;
        CatalogStoreError catalogError = persistence.Save();
        if (catalogError != CatalogStoreError.None)
        {
            state.Payloads[index] = previousPayload;
            if (previousRecipe is null)
            {
                state.DefectRecipes.Remove(frameId);
            }
            else
            {
                state.DefectRecipes[frameId] = previousRecipe;
            }
            state.ProjectFrames();
            return new(null, LibraryFrameError.None,
                DefectSidecarError.None, catalogError);
        }

        state.ProjectFrames();
        return new(stored, LibraryFrameError.None,
            DefectSidecarError.None, CatalogStoreError.None);
    }

    public void Purge(LibraryFrameRemoval removal)
    {
        ArgumentNullException.ThrowIfNull(removal);
        foreach ((Guid frameId, ulong revision) in removal.DefectSidecars)
        {
            _ = state.Session.RemoveDefectRecipe(frameId, revision + 1);
        }
    }
}
