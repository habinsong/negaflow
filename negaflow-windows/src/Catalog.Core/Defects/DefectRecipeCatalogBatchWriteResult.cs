namespace Negaflow.Catalog;

/// <summary>
/// 여러 frame의 defect sidecar와 하나의 catalog snapshot을 함께 게시한 결과입니다.
/// </summary>
public readonly record struct DefectRecipeCatalogBatchWriteResult(
    IReadOnlyList<DefectRecipeSnapshot> Snapshots,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => Snapshots is { Count: > 0 } &&
        SidecarError == DefectSidecarError.None &&
        CatalogError == CatalogStoreError.None;

    internal static DefectRecipeCatalogBatchWriteResult Success(
        IReadOnlyList<DefectRecipeSnapshot> snapshots) =>
        new(snapshots, DefectSidecarError.None, CatalogStoreError.None);

    internal static DefectRecipeCatalogBatchWriteResult Failure(
        DefectSidecarError sidecarError = DefectSidecarError.None,
        CatalogStoreError catalogError = CatalogStoreError.None) =>
        new([], sidecarError, catalogError);
}
