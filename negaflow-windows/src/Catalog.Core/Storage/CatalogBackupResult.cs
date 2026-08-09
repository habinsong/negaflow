namespace Negaflow.Catalog;

public enum CatalogBackupError
{
    None,
    InvalidRetention,
    InvalidStorageRoots,
    InvalidCatalog,
    DefectSidecarUnavailable,
    SequenceExhausted,
    ValidationFailed,
    PromotionFailed,
    RecoveryRequired,
    AccessDenied,
    IoFailure,
}

public readonly record struct CatalogBackupCreateResult(
    string? GenerationPath,
    ulong Sequence,
    CatalogBackupError Error,
    bool RetentionPruneFailed)
{
    public bool IsSuccess => Error == CatalogBackupError.None &&
        GenerationPath is not null;

    internal static CatalogBackupCreateResult Success(
        string generationPath,
        ulong sequence,
        bool retentionPruneFailed) =>
        new(generationPath, sequence, CatalogBackupError.None, retentionPruneFailed);

    internal static CatalogBackupCreateResult Failure(CatalogBackupError error) =>
        new(null, 0, error, false);
}

internal sealed record CatalogBackupFileRecord(
    string RelativePath,
    long ByteCount,
    string Sha256);

internal sealed record CatalogBackupManifest(
    int Version,
    ulong Sequence,
    DateTimeOffset CreatedAt,
    int FrameCount,
    IReadOnlyList<string> DefectFrameIds,
    int CatalogVersion,
    IReadOnlyList<CatalogBackupFileRecord> Files)
{
    public const int CurrentVersion = 3;
}

internal readonly record struct CatalogBackupValidationResult(
    CatalogSnapshot? Snapshot,
    CatalogBackupManifest? Manifest)
{
    public bool IsValid => Snapshot is not null && Manifest is not null;
}
