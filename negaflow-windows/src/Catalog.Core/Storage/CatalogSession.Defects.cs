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
    /// <see cref="ReadDefectRecipe"/> 를 여러 사진에 한꺼번에 합니다. 파일마다 따로 복호하므로
    /// 켤 때 결함 기록을 모두 읽는 자리가 씁니다. 결과는 넘긴 차례 그대로입니다.
    /// </summary>
    public IReadOnlyList<DefectSidecarReadResult> ReadDefectRecipes(IReadOnlyList<Guid> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        lock (writeGate)
        {
            RequireOpen();
            return DefectSidecarStore.ReadMany(roots, frameIds);
        }
    }

    /// <summary>
    /// 이 사진에 대해 디스크와 이번 프로세스가 이미 본 가장 높은 revision 입니다. 카탈로그
    /// 수동 복구가 사라지거나 어긋난 기록을 floor 에 막히지 않게 다시 쓸 때 씁니다.
    /// </summary>
    public ulong HighestKnownDefectRevision(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return DefectSidecarStore.HighestKnownRevision(roots, frameId);
        }
    }

    /// <summary>
    /// 카탈로그 수동 복구의 다시 쓰기입니다. 평소 쓰기와 같지만, 디스크 기록이 <b>깨져</b>
    /// 읽히지 않으면 지금 카탈로그와 결함 폴더를 원본 그대로 보관(<c>library.corrupt-*</c>)한
    /// 뒤 그 파일만 치우고 씁니다. 평소 쓰기는 읽을 수 없는 기록 위에 쓰지 않습니다. 읽기
    /// 권한 오류나 더 새 버전 기록은 여기서도 건드리지 않습니다.
    /// </summary>
    public DefectSidecarWriteResult RewriteDefectRecipeForRepair(DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (writeGate)
        {
            RequireOpen();
            if (mutationBlocked)
            {
                return DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure);
            }
            lock (DefectSidecarStore.Gate)
            {
                string path = DefectSidecarStore.PathFor(roots, snapshot.FrameId);
                DefectSidecarError existing =
                    DefectSidecarFile.ReadFile(path, snapshot.FrameId).Error;
                if (existing is DefectSidecarError.InvalidContent or
                    DefectSidecarError.InvalidSnapshot or DefectSidecarError.InvalidFrameId)
                {
                    if (!CatalogSidelinedFiles.Preserve(roots))
                    {
                        return DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure);
                    }
                    try
                    {
                        File.Delete(path);
                        DefectSidecarValidationCache.Invalidate(path);
                    }
                    catch (UnauthorizedAccessException)
                    {
                        return DefectSidecarWriteResult.Failure(DefectSidecarError.AccessDenied);
                    }
                    catch (IOException)
                    {
                        return DefectSidecarWriteResult.Failure(DefectSidecarError.IoFailure);
                    }
                }
                return DefectSidecarStore.WriteLocked(roots, snapshot);
            }
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

    /// <summary>
    /// 지금 카탈로그와 결함 폴더를 원본 그대로 옆에 보관합니다(<c>library.corrupt-*</c>). 수동 복구가
    /// 되살릴 수 없는 결함 기록을 비우기 전에 부릅니다(macOS <c>preserveUnsafeState</c>).
    /// </summary>
    public bool PreserveCurrentFiles()
    {
        lock (writeGate)
        {
            RequireOpen();
            return CatalogSidelinedFiles.Preserve(roots);
        }
    }

    /// <summary>
    /// 사라졌거나 깨진 결함 기록을 가장 새 검증된 백업 세대의 같은 사진 기록으로 되살립니다. 열 때와
    /// 수동 복구가 편집을 비우기 전에 부릅니다(macOS <c>DefectRecordRecovery.restoreFromBackup</c>).
    /// </summary>
    public bool RestoreDefectRecipeFromBackup(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return !mutationBlocked && DefectRecordRecovery.RestoreFromBackup(roots, frameId);
        }
    }

    /// <summary>
    /// 앱이 쓴 결함 기록의 읽기 권한이 빠졌거나 읽기 전용이면 소유자 권한을 되돌립니다(macOS
    /// <c>DefectRecordRecovery.restoreOwnerAccessIfNeeded</c>). 열 때와 수동 복구가 읽기 전에 부릅니다.
    /// </summary>
    public bool RestoreDefectRecordAccess(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return !mutationBlocked && DefectRecordRecovery.RestoreOwnerAccessIfNeeded(roots, frameId);
        }
    }

    /// <summary>
    /// 카탈로그가 더는 선언하지 않는 사진의 깨진 결함 기록을 치웁니다. 먼저
    /// <see cref="PreserveCurrentFiles"/> 로 원본을 보관해야 합니다.
    /// </summary>
    public DefectSidecarDeleteResult DiscardUnreadableDefectRecipe(Guid frameId)
    {
        lock (writeGate)
        {
            RequireOpen();
            return mutationBlocked
                ? DefectSidecarDeleteResult.Failure(DefectSidecarError.IoFailure)
                : defectRecipes.DiscardUndeclaredUnreadable(frameId);
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
