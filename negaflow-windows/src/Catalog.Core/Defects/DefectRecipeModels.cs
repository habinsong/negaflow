namespace Negaflow.Catalog;

public enum DefectEditKind
{
    Brush,
    Region,
    Infrared,
    Clone,
}

public enum DefectClassification
{
    Dust,
    Pinhole,
    ScratchHorizontal,
    ScratchVertical,
    ScratchDiagonal,
    EmulsionDamage,
    MicroSpeck,
}

public enum DefectEditLabelKind
{
    Automatic,
    Guided,
    Brush,
    Clone,
    Infrared,
}

public enum DefectEditSummaryKind
{
    ClassBreakdown,
    Brush,
    Clone,
}

public readonly record struct DefectPoint(double X, double Y);

public readonly record struct DefectRect(
    double X,
    double Y,
    double Width,
    double Height);

public readonly record struct DefectSize(double Width, double Height);

public sealed record DefectMask(bool IsZlib, byte[] Data);

public sealed record DefectStroke(
    IReadOnlyList<DefectPoint> Points,
    double Thickness);

public sealed record DefectCloneStroke(
    IReadOnlyList<DefectPoint> Points,
    double OffsetX,
    double OffsetY,
    double Diameter,
    double Hardness);

public sealed record DefectPreviewComponent(
    DefectClassification Classification,
    double Confidence,
    IReadOnlyList<DefectPoint> Points);

public sealed record DefectCluster(
    DefectRect Roi,
    DefectMask Mask,
    int Width,
    int Height,
    DefectMask? AttenuationR16 = null);

/// <summary>
/// 표시 문자열 자체가 아니라 현재 앱 언어로 문자열을 만들 수 있는 값만 보존합니다.
/// Value는 자동/가이드/IR의 결함 수, 브러시 stroke 수, clone 지름(px)입니다.
/// </summary>
public readonly record struct DefectEditLabel(
    DefectEditLabelKind Kind,
    int Value);

public readonly record struct DefectClassCount(
    DefectClassification Classification,
    int Count);

public sealed record DefectClassBreakdown(
    IReadOnlyList<DefectClassCount> Counts,
    double MeanConfidence);

public sealed record DefectEditSummary(
    DefectEditSummaryKind Kind,
    DefectClassBreakdown? ClassBreakdown = null);

/// <summary>
/// macOS DefectEditItemRecord와 같은 ordered edit 한 항목입니다. kind에 맞지 않는 nullable
/// payload가 섞이면 sidecar 경계에서 거부됩니다.
/// </summary>
public sealed record DefectEditItem(
    Guid Id,
    DefectEditKind Kind,
    bool Enabled,
    double Strength,
    DefectEditLabel Label,
    DefectEditSummary Summary,
    DefectSize? BaseSize,
    IReadOnlyList<DefectPreviewComponent> Preview)
{
    public IReadOnlyList<DefectStroke>? Strokes { get; init; }

    public IReadOnlyList<DefectCloneStroke>? CloneStrokes { get; init; }

    public DefectMask? RegionMask { get; init; }

    public DefectRect? RegionRoi { get; init; }

    public int? RegionWidth { get; init; }

    public int? RegionHeight { get; init; }

    public IReadOnlyList<DefectCluster>? Clusters { get; init; }
}

/// <summary>경로와 무관한 원본 파일 identity입니다.</summary>
public readonly record struct DefectSourceIdentity(ulong ByteCount, string Sha256);

/// <summary>
/// 한 frame의 불변 Defects recipe snapshot입니다. Create는 전체 payload를 복사·검증하고
/// render-affecting ordered state의 fingerprint를 계산합니다.
/// </summary>
public sealed class DefectRecipeSnapshot
{
    internal DefectRecipeSnapshot(
        Guid frameId,
        int fingerprintVersion,
        ulong recipeRevision,
        string recipeSha256,
        DefectSourceIdentity? sourceIdentity,
        IReadOnlyList<DefectEditItem> items)
    {
        FrameId = frameId;
        FingerprintVersion = fingerprintVersion;
        RecipeRevision = recipeRevision;
        RecipeSha256 = recipeSha256;
        SourceIdentity = sourceIdentity;
        Items = items;
        AppendPrefixEditCount = Math.Max(0, items.Count - 1);
        AppendPrefixSha256 = AppendPrefixEditCount == 0
            ? null
            : DefectRecipeFingerprint.Compute(items.Take(AppendPrefixEditCount).ToArray());
    }

    public Guid FrameId { get; }

    public int FingerprintVersion { get; }

    public ulong RecipeRevision { get; }

    public string RecipeSha256 { get; }

    public DefectSourceIdentity? SourceIdentity { get; }

    public IReadOnlyList<DefectEditItem> Items { get; }

    /// <summary>
    /// 마지막 item을 제외한 ordered recipe의 지문입니다. 새 item append를 full-resolution
    /// cleaned raw에 증분 적용할 때만 쓰며, 전체 <see cref="RecipeSha256"/>는 그대로 권위가 있습니다.
    /// </summary>
    public string? AppendPrefixSha256 { get; }

    public int AppendPrefixEditCount { get; }

    public static DefectRecipeSnapshot Create(
        Guid frameId,
        ulong recipeRevision,
        DefectSourceIdentity? sourceIdentity,
        IReadOnlyList<DefectEditItem> items) =>
        DefectRecipeValidator.CreateSnapshot(
            frameId,
            recipeRevision,
            sourceIdentity,
            items);
}

public enum DefectSidecarError
{
    None,
    NotFound,
    InvalidStorageRoots,
    InvalidFrameId,
    ReparsePointNotAllowed,
    UnsupportedVersion,
    InvalidContent,
    InvalidSnapshot,
    ConflictingSameRevision,
    AccessDenied,
    IoFailure,
}

public readonly record struct DefectSidecarReadResult(
    DefectRecipeSnapshot? Snapshot,
    DefectSidecarError Error,
    int ObservedVersion)
{
    public bool IsSuccess => Error == DefectSidecarError.None && Snapshot is not null;

    internal static DefectSidecarReadResult Success(DefectRecipeSnapshot snapshot) =>
        new(snapshot, DefectSidecarError.None, DefectSidecarCodec.CurrentVersion);

    internal static DefectSidecarReadResult Failure(
        DefectSidecarError error,
        int observedVersion = 0) =>
        new(null, error, observedVersion);
}

public enum DefectSidecarWriteKind
{
    None,
    Written,
    AlreadyCurrent,
    SkippedNewer,
}

public readonly record struct DefectSidecarWriteResult(
    DefectSidecarWriteKind Kind,
    DefectSidecarError Error,
    ulong ExistingRevision)
{
    public bool IsSuccess => Error == DefectSidecarError.None &&
        Kind != DefectSidecarWriteKind.None;

    internal static DefectSidecarWriteResult Success(
        DefectSidecarWriteKind kind,
        ulong existingRevision = 0) =>
        new(kind, DefectSidecarError.None, existingRevision);

    internal static DefectSidecarWriteResult Failure(
        DefectSidecarError error,
        ulong existingRevision = 0) =>
        new(DefectSidecarWriteKind.None, error, existingRevision);
}

public readonly record struct DefectSidecarDeleteResult(DefectSidecarError Error)
{
    public bool IsSuccess => Error == DefectSidecarError.None;

    internal static DefectSidecarDeleteResult Success() =>
        new(DefectSidecarError.None);

    internal static DefectSidecarDeleteResult Failure(DefectSidecarError error) =>
        new(error);
}

public readonly record struct DefectRecipeCatalogWriteResult(
    DefectRecipeSnapshot? Snapshot,
    DefectSidecarWriteResult Sidecar,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => Snapshot is not null && Sidecar.IsSuccess &&
        CatalogError == CatalogStoreError.None;

    internal static DefectRecipeCatalogWriteResult Success(
        DefectRecipeSnapshot snapshot,
        DefectSidecarWriteResult sidecar) =>
        new(snapshot, sidecar, CatalogStoreError.None);

    internal static DefectRecipeCatalogWriteResult Failure(
        DefectSidecarWriteResult sidecar,
        CatalogStoreError catalogError = CatalogStoreError.None) =>
        new(null, sidecar, catalogError);
}

public readonly record struct DefectRecipeCatalogDeleteResult(
    bool Deleted,
    DefectSidecarError SidecarError,
    CatalogStoreError CatalogError)
{
    public bool IsSuccess => Deleted &&
        SidecarError == DefectSidecarError.None &&
        CatalogError == CatalogStoreError.None;

    internal static DefectRecipeCatalogDeleteResult Success() =>
        new(true, DefectSidecarError.None, CatalogStoreError.None);

    internal static DefectRecipeCatalogDeleteResult Failure(
        DefectSidecarError sidecarError = DefectSidecarError.None,
        CatalogStoreError catalogError = CatalogStoreError.None) =>
        new(false, sidecarError, catalogError);
}
