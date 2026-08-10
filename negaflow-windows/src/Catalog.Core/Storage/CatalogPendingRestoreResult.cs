namespace Negaflow.Catalog;

public enum CatalogPendingRestoreError
{
    None,
    InvalidStorageRoots,
    InvalidGeneration,
    InvalidMarker,
    InvalidPendingSnapshot,
    UnsupportedCurrentCatalog,
    DefectSidecarUnavailable,
    SafetyBackupFailed,
    ApplyFailed,
    AccessDenied,
    IoFailure,
}

public enum CatalogPendingRestoreApplicationKind
{
    None,
    Applied,
    CleanupOnly,
    CleanupPending,
}

public readonly record struct CatalogPendingRestoreScheduleResult(
    string? SourceGenerationId,
    DateTimeOffset ScheduledAt,
    CatalogPendingRestoreError Error)
{
    public bool IsSuccess => Error == CatalogPendingRestoreError.None &&
        SourceGenerationId is not null;

    internal static CatalogPendingRestoreScheduleResult Success(
        string sourceGenerationId,
        DateTimeOffset scheduledAt) =>
        new(sourceGenerationId, scheduledAt, CatalogPendingRestoreError.None);

    internal static CatalogPendingRestoreScheduleResult Failure(
        CatalogPendingRestoreError error) =>
        new(null, default, error);
}

public readonly record struct CatalogPendingRestoreOperationResult(
    CatalogPendingRestoreError Error)
{
    public bool IsSuccess => Error == CatalogPendingRestoreError.None;

    internal static CatalogPendingRestoreOperationResult Success() =>
        new(CatalogPendingRestoreError.None);

    internal static CatalogPendingRestoreOperationResult Failure(
        CatalogPendingRestoreError error) => new(error);
}

public readonly record struct CatalogPendingRestoreApplicationResult(
    CatalogPendingRestoreApplicationKind Kind,
    string? SourceGenerationId,
    bool DidApplyRestore,
    CatalogPendingRestoreError Error,
    int ObservedVersion)
{
    public bool IsSuccess => Error == CatalogPendingRestoreError.None;

    internal static CatalogPendingRestoreApplicationResult None() =>
        new(
            CatalogPendingRestoreApplicationKind.None,
            null,
            false,
            CatalogPendingRestoreError.None,
            0);

    internal static CatalogPendingRestoreApplicationResult Success(
        CatalogPendingRestoreApplicationKind kind,
        string sourceGenerationId,
        bool didApplyRestore) =>
        new(
            kind,
            sourceGenerationId,
            didApplyRestore,
            CatalogPendingRestoreError.None,
            0);

    internal static CatalogPendingRestoreApplicationResult Failure(
        CatalogPendingRestoreError error,
        int observedVersion = 0) =>
        new(
            CatalogPendingRestoreApplicationKind.None,
            null,
            false,
            error,
            observedVersion);
}

internal enum CatalogPendingRestorePhase
{
    Scheduled,
    Applied,
}

internal sealed record CatalogPendingRestoreMarker(
    int Version,
    string DirectoryName,
    string SourceGenerationId,
    DateTimeOffset ScheduledAt,
    CatalogPendingRestorePhase Phase)
{
    public const int MinimumSupportedVersion = 1;
    public const int CurrentVersion = 2;
}

internal readonly record struct CatalogPendingRestoreCleanup(
    Action<string> RemoveDirectory,
    Action<string> RemoveMarker);
