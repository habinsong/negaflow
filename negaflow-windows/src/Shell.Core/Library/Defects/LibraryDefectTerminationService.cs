using Negaflow.Catalog;

namespace Negaflow.Shell;

public enum LibraryDefectTerminationError
{
    None,
    InvalidScansDirectory,
    BakeExporterUnavailable,
    InvalidRecipe,
    RequestRefused,
    NativeBakeFailed,
    SourceChanged,
    InvalidBakedFile,
    FileCommitFailed,
    CatalogCommitFailed,
    FileRollbackFailed,
    OrphanPurgeFailed,
}

public readonly record struct LibraryDefectTerminationResult(
    LibraryDefectTerminationError Error,
    string? FrameId = null,
    DevelopRequestRefusal RequestRefusal = DevelopRequestRefusal.None,
    string? NativeFailureName = null,
    DefectSidecarError SidecarError = DefectSidecarError.None,
    CatalogStoreError CatalogError = CatalogStoreError.None)
{
    public bool IsSuccess => Error == LibraryDefectTerminationError.None;

    internal static LibraryDefectTerminationResult Success() => new(
        LibraryDefectTerminationError.None);
}

internal sealed class LibraryDefectTerminationService(Action<string> clearLiveStrength)
{
    internal Task<LibraryDefectTerminationResult> PrepareAsync(LibraryDocument document, string scansDirectory)
    {
        ArgumentNullException.ThrowIfNull(document);
        _ = scansDirectory;
        CatalogStoreError saved = document.Save();
        if (saved != CatalogStoreError.None)
        {
            return Task.FromResult(new LibraryDefectTerminationResult(
                LibraryDefectTerminationError.CatalogCommitFailed, CatalogError: saved));
        }
        foreach (LibraryFrameSnapshot frame in document.Frames) { clearLiveStrength(frame.Id); }
        DefectSidecarError orphan = document.PurgeRemovedDefectSidecarsForTermination();
        return Task.FromResult(orphan == DefectSidecarError.None
            ? LibraryDefectTerminationResult.Success()
            : new LibraryDefectTerminationResult(LibraryDefectTerminationError.OrphanPurgeFailed, SidecarError: orphan));
    }
}
