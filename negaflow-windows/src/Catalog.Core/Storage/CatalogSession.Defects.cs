namespace Negaflow.Catalog;

/// <summary>Defect sidecar와 catalog를 같은 session write gate에서 다루는 책임입니다.</summary>
public sealed partial class CatalogSession
{
    public DefectSidecarReadResult ReadDefectRecipe(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return DefectSidecarStore.Read(roots, frameId);
        }
    }

    /// <summary>
    /// sidecar를 먼저 durable하게 기록합니다. 호출자는 이 성공 뒤 catalog의
    /// hasDefectEdits를 true로 commit해야 하며, 반대 순서는 Write가 거부합니다.
    /// </summary>
    public DefectSidecarWriteResult WriteDefectRecipe(DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure);
            }
            return DefectSidecarStore.Write(roots, snapshot);
        }
    }

    public DefectRecipeCatalogWriteResult WriteDefectRecipeAndCatalog(
        DefectRecipeSnapshot recipe,
        CatalogSnapshot catalog)
    {
        ArgumentNullException.ThrowIfNull(recipe);
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogWriteResult.Failure(
                    DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure),
                    CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectWrite(defectRecipes.Write(
                recipe,
                catalog,
                () => CatalogCommitVerifier.Commit(catalog, roots),
                forceSidecarRollbackFailure: false));
        }
    }

    internal DefectRecipeCatalogWriteResult WriteDefectRecipeAndCatalogForTesting(
        DefectRecipeSnapshot recipe,
        CatalogSnapshot catalog,
        Func<CatalogSnapshot, string, CatalogWriteResult>? writer = null,
        Func<string, CatalogReadResult>? readback = null,
        Func<CatalogPrimarySnapshot, StorageRootSet, bool>? restoreCatalog = null,
        bool forceSidecarRollbackFailure = false)
    {
        ArgumentNullException.ThrowIfNull(recipe);
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogWriteResult.Failure(
                    DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure),
                    CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectWrite(defectRecipes.Write(
                recipe,
                catalog,
                () => CatalogCommitVerifier.CommitForTesting(
                    catalog,
                    roots,
                    writer,
                    readback,
                    restoreCatalog),
                forceSidecarRollbackFailure));
        }
    }

    public DefectRecipeCatalogBatchWriteResult WriteDefectRecipesAndCatalog(
        IReadOnlyList<DefectRecipeSnapshot> recipes,
        CatalogSnapshot catalog)
    {
        ArgumentNullException.ThrowIfNull(recipes);
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogBatchWriteResult.Failure(
                    DefectSidecarError.IoFailure,
                    CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectBatchWrite(
                new DefectRecipeCatalogBatchTransaction(roots).Write(
                    recipes,
                    catalog,
                    () => CatalogCommitVerifier.Commit(catalog, roots),
                    forceSidecarRollbackFailure: false));
        }
    }

    internal DefectRecipeCatalogBatchWriteResult WriteDefectRecipesAndCatalogForTesting(
        IReadOnlyList<DefectRecipeSnapshot> recipes,
        CatalogSnapshot catalog,
        Func<CatalogSnapshot, string, CatalogWriteResult>? writer = null,
        Func<string, CatalogReadResult>? readback = null,
        Func<CatalogPrimarySnapshot, StorageRootSet, bool>? restoreCatalog = null,
        bool forceSidecarRollbackFailure = false)
    {
        ArgumentNullException.ThrowIfNull(recipes);
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogBatchWriteResult.Failure(
                    DefectSidecarError.IoFailure,
                    CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectBatchWrite(
                new DefectRecipeCatalogBatchTransaction(roots).Write(
                    recipes,
                    catalog,
                    () => CatalogCommitVerifier.CommitForTesting(
                        catalog,
                        roots,
                        writer,
                        readback,
                        restoreCatalog),
                    forceSidecarRollbackFailure));
        }
    }

    public DefectRecipeCatalogDeleteResult DeleteDefectRecipeAndCatalog(
        Guid frameId,
        ulong deletionRevision,
        CatalogSnapshot catalog)
    {
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogDeleteResult.Failure(
                    catalogError: CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectDelete(
                defectRecipes.Delete(frameId, deletionRevision, catalog));
        }
    }

    public DefectRecipeCatalogDeleteResult DeleteDefectRecipeAndCatalogForBake(
        Guid frameId,
        ulong deletionRevision,
        CatalogSnapshot catalog)
    {
        ArgumentNullException.ThrowIfNull(catalog);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectRecipeCatalogDeleteResult.Failure(
                    catalogError: CatalogStoreError.RollbackFailed);
            }
            return ObserveDefectDelete(
                defectRecipes.DeleteForBake(frameId, deletionRevision, catalog));
        }
    }

    /// <summary>
    /// catalog가 더는 해당 frame의 edit을 선언하지 않을 때만 sidecar를 지웁니다.
    /// catalog false commit → sidecar remove 순서라 crash 시 orphan만 남고 recipe 유실은 없습니다.
    /// </summary>
    public DefectSidecarDeleteResult RemoveDefectRecipe(Guid frameId, ulong minimumRevision)
    {
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectSidecarDeleteResult.Failure(DefectSidecarError.IoFailure);
            }
            return defectRecipes.RemoveUndeclared(frameId, minimumRevision);
        }
    }

    private DefectRecipeCatalogWriteResult ObserveDefectWrite(
        DefectRecipeCatalogWriteResult result)
    {
        if (result.CatalogError == CatalogStoreError.RollbackFailed)
        {
            mutationBlocked = true;
        }
        return result;
    }

    private DefectRecipeCatalogBatchWriteResult ObserveDefectBatchWrite(
        DefectRecipeCatalogBatchWriteResult result)
    {
        if (result.CatalogError == CatalogStoreError.RollbackFailed)
        {
            mutationBlocked = true;
        }
        return result;
    }

    private DefectRecipeCatalogDeleteResult ObserveDefectDelete(
        DefectRecipeCatalogDeleteResult result)
    {
        if (result.CatalogError == CatalogStoreError.RollbackFailed)
        {
            mutationBlocked = true;
        }
        return result;
    }
}
