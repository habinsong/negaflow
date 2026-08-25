using System.Diagnostics;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>결함 recipe sidecar와 catalog 선언을 일관되게 쓰고 정리합니다.</summary>
internal sealed class LibraryDefectRecipeStore(
    LibraryDocumentState state)
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
        CatalogStoreError prerequisite = FlushDirtyCatalog();
        if (prerequisite != CatalogStoreError.None)
        {
            return new(null, LibraryFrameError.None,
                DefectSidecarError.None, prerequisite);
        }
        if (!state.DefectRevisions.IsNext(frameId, recipe.RecipeRevision))
        {
            return new(null, LibraryFrameError.None,
                DefectSidecarError.InvalidSnapshot, CatalogStoreError.None);
        }
        if (recipe.Items.Count == 0)
        {
            return Delete(frameId, index, recipe);
        }

        bool trace = InfraredPerformanceTrace.Enabled;
        long traceStart = trace ? Stopwatch.GetTimestamp() : 0L;
        double Split()
        {
            long now = Stopwatch.GetTimestamp();
            double elapsed = (now - traceStart) * 1000.0 / Stopwatch.Frequency;
            traceStart = now;
            return elapsed;
        }

        JsonObject updatedPayload = (JsonObject)state.Payloads[index].DeepClone();
        updatedPayload["hasDefectEdits"] = true;
        double cloneMilliseconds = trace ? Split() : 0.0;
        List<CatalogEntityRow> candidateRows = state.FrameRows();
        candidateRows[index] = new CatalogEntityRow(frameId, updatedPayload);
        double rowsMilliseconds = trace ? Split() : 0.0;
        CatalogSnapshot candidateSnapshot = state.CreateSnapshot(candidateRows);
        double snapshotMilliseconds = trace ? Split() : 0.0;
        DefectRecipeCatalogWriteResult committed = state.Session.WriteDefectRecipeAndCatalog(
            recipe,
            candidateSnapshot);
        double commitMilliseconds = trace ? Split() : 0.0;
        if (!committed.IsSuccess || committed.Snapshot is not { } stored)
        {
            return new(null, LibraryFrameError.None,
                committed.Sidecar.Error, committed.CatalogError);
        }

        state.Payloads[index] = updatedPayload;
        state.DefectRecipes[frameId] = stored;
        state.DefectRevisions.Observe(frameId, stored.RecipeRevision);
        state.ProjectFrames();
        if (trace)
        {
            InfraredPerformanceTrace.Write(
                $"recipe-store clone={cloneMilliseconds:F1} rows={rowsMilliseconds:F1} " +
                $"snapshot={snapshotMilliseconds:F1} commit={commitMilliseconds:F1} " +
                $"project={Split():F1} ms");
        }
        state.IsDirty = false;
        return new(stored, LibraryFrameError.None,
            DefectSidecarError.None, CatalogStoreError.None);
    }

    private LibraryDefectRecipeWriteResult Delete(
        string frameId,
        int index,
        DefectRecipeSnapshot deletion)
    {
        if (!state.DefectRecipes.ContainsKey(frameId))
        {
            return new(null, LibraryFrameError.None,
                DefectSidecarError.InvalidSnapshot, CatalogStoreError.None);
        }

        JsonObject updatedPayload = (JsonObject)state.Payloads[index].DeepClone();
        updatedPayload.Remove("hasDefectEdits");
        updatedPayload = DefectReviewTrackingCodec.Apply(
            updatedPayload,
            mark: null).FrameRecord!;
        List<CatalogEntityRow> candidateRows = state.FrameRows();
        candidateRows[index] = new CatalogEntityRow(frameId, updatedPayload);
        DefectRecipeCatalogDeleteResult committed =
            state.Session.DeleteDefectRecipeAndCatalog(
                deletion.FrameId,
                deletion.RecipeRevision,
                state.CreateSnapshot(candidateRows));
        if (!committed.IsSuccess)
        {
            return new(null, LibraryFrameError.None,
                committed.SidecarError, committed.CatalogError);
        }

        state.Payloads[index] = updatedPayload;
        state.DefectRecipes.Remove(frameId);
        state.DefectRevisions.Observe(frameId, deletion.RecipeRevision);
        state.ProjectFrames();
        state.IsDirty = false;
        return new(null, LibraryFrameError.None,
            DefectSidecarError.None, CatalogStoreError.None)
        {
            IsDeleted = true,
        };
    }

    private CatalogStoreError FlushDirtyCatalog()
    {
        if (!state.IsDirty)
        {
            return CatalogStoreError.None;
        }

        CatalogStoreError error = state.Session.Write(
            state.CreateSnapshot(state.FrameRows())).Error;
        if (error == CatalogStoreError.None)
        {
            state.IsDirty = false;
        }
        return error;
    }

    internal bool MatchesBakeSource(
        string frameId,
        DefectRecipeSnapshot expectedRecipe,
        string expectedSourcePath) =>
        state.IndexById.ContainsKey(frameId) &&
        state.Frames.FirstOrDefault(frame =>
            string.Equals(frame.Id, frameId, StringComparison.Ordinal)) is { } currentFrame &&
        string.Equals(
            currentFrame.SourcePath,
            expectedSourcePath,
            StringComparison.OrdinalIgnoreCase) &&
        state.DefectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? currentRecipe) &&
        currentRecipe.FrameId == expectedRecipe.FrameId &&
        currentRecipe.FingerprintVersion == expectedRecipe.FingerprintVersion &&
        currentRecipe.RecipeRevision == expectedRecipe.RecipeRevision &&
        string.Equals(
            currentRecipe.RecipeSha256,
            expectedRecipe.RecipeSha256,
            StringComparison.Ordinal) &&
        currentRecipe.SourceIdentity == expectedRecipe.SourceIdentity;

    internal LibraryDefectRecipeWriteResult CompleteBake(
        string frameId,
        DefectRecipeSnapshot expectedRecipe,
        string expectedSourcePath,
        string? bakedSourcePath = null,
        LibrarySourceMetadata? bakedMetadata = null)
    {
        if ((bakedSourcePath is null) != (bakedMetadata is null) ||
            (bakedSourcePath is not null &&
             (!Path.IsPathFullyQualified(bakedSourcePath) || !bakedMetadata!.Value.IsValid)) ||
            !MatchesBakeSource(frameId, expectedRecipe, expectedSourcePath) ||
            !Guid.TryParseExact(frameId, "D", out Guid parsedFrameId) ||
            parsedFrameId != expectedRecipe.FrameId ||
            expectedRecipe.RecipeRevision == ulong.MaxValue)
        {
            return new(null, LibraryFrameError.MissingId,
                DefectSidecarError.InvalidSnapshot, CatalogStoreError.None);
        }
        CatalogStoreError prerequisite = FlushDirtyCatalog();
        if (prerequisite != CatalogStoreError.None)
        {
            return new(null, LibraryFrameError.None,
                DefectSidecarError.None, prerequisite);
        }

        int index = state.IndexById[frameId];
        JsonObject updatedPayload = (JsonObject)state.Payloads[index].DeepClone();
        updatedPayload.Remove("hasDefectEdits");
        updatedPayload = DefectReviewTrackingCodec.Apply(updatedPayload, mark: null).FrameRecord!;
        if (bakedSourcePath is not null)
        {
            updatedPayload[LibraryFrameReader.SourcePathName] = bakedSourcePath;
            updatedPayload[LibraryFrameReader.SourceMetadataName] =
                LibrarySourceMetadataJson.Write(bakedMetadata!.Value);
        }

        List<CatalogEntityRow> candidateRows = state.FrameRows();
        candidateRows[index] = new CatalogEntityRow(frameId, updatedPayload);
        ulong deletionRevision = expectedRecipe.RecipeRevision + 1UL;
        DefectRecipeCatalogDeleteResult committed =
            state.Session.DeleteDefectRecipeAndCatalogForBake(
                expectedRecipe.FrameId,
                deletionRevision,
                state.CreateSnapshot(candidateRows));
        if (!committed.IsSuccess)
        {
            return new(null, LibraryFrameError.None,
                committed.SidecarError, committed.CatalogError);
        }

        state.Payloads[index] = updatedPayload;
        state.DefectRecipes.Remove(frameId);
        state.DefectRevisions.Observe(frameId, deletionRevision);
        state.ProjectFrames();
        state.IsDirty = false;
        return new(null, LibraryFrameError.None,
            DefectSidecarError.None, CatalogStoreError.None)
        {
            IsDeleted = true,
        };
    }

    public void Purge(LibraryFrameRemoval removal)
    {
        ArgumentNullException.ThrowIfNull(removal);
        foreach ((Guid frameId, ulong revision) in removal.DefectSidecars)
        {
            _ = Purge(frameId, revision);
        }
    }

    internal DefectSidecarError Purge(Guid frameId, ulong revision) =>
        revision == ulong.MaxValue
            ? DefectSidecarError.InvalidSnapshot
            : state.Session.RemoveDefectRecipe(frameId, revision + 1).Error;
}
