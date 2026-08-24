using Negaflow.Catalog;
using Negaflow.Interop;

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

internal sealed class LibraryDefectTerminationService(
    IDefectBakeExporter? exporter,
    Func<string, LibrarySourceMetadata?> sourceMetadataReader,
    Action<string> clearLiveStrength)
{
    internal async Task<LibraryDefectTerminationResult> PrepareAsync(
        LibraryDocument document,
        string scansDirectory)
    {
        ArgumentNullException.ThrowIfNull(document);
        if (string.IsNullOrWhiteSpace(scansDirectory) ||
            !Path.IsPathFullyQualified(scansDirectory))
        {
            return new(LibraryDefectTerminationError.InvalidScansDirectory);
        }

        string[] frameIds = document.Frames
            .Where(frame => !frame.IsPreviewScan && frame.DefectRecipe is not null)
            .Select(frame => frame.Id)
            .ToArray();
        foreach (string frameId in frameIds)
        {
            LibraryFrameSnapshot? frame = document.Frames.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
            if (frame?.DefectRecipe is not { } recipe)
            {
                continue;
            }

            DefectEditItem[] bakeable = recipe.Items
                .Where(item => item.Kind != DefectEditKind.Infrared)
                .ToArray();
            if (!bakeable.Any(item => item.Enabled && item.Strength > 1.0e-3))
            {
                LibraryDefectRecipeWriteResult cleared = document.CompleteDefectBake(
                    frame.Id,
                    recipe,
                    frame.SourcePath);
                if (!cleared.IsSuccess)
                {
                    return CatalogFailure(frame.Id, cleared);
                }
                clearLiveStrength(frame.Id);
                continue;
            }
            if (exporter is null || recipe.SourceIdentity is null)
            {
                return new(
                    exporter is null
                        ? LibraryDefectTerminationError.BakeExporterUnavailable
                        : LibraryDefectTerminationError.InvalidRecipe,
                    frame.Id);
            }

            DefectRecipeSnapshot filtered;
            try
            {
                filtered = DefectRecipeSnapshot.Create(
                    recipe.FrameId,
                    recipe.RecipeRevision,
                    recipe.SourceIdentity,
                    bakeable);
            }
            catch (Exception error) when (error is ArgumentException or OverflowException)
            {
                return new(LibraryDefectTerminationError.InvalidRecipe, frame.Id);
            }

            bool sharesSource = document.Frames.Any(candidate =>
                !string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal) &&
                LibraryDefectBakeFiles.SamePath(candidate.SourcePath, frame.SourcePath));
            bool inPlace = frame.SourceKind == FrameSourceKind.ScannerTiff && !sharesSource;
            string stagingPath;
            try
            {
                stagingPath = LibraryDefectBakeFiles.CreateStagingPath(
                    frame,
                    scansDirectory,
                    inPlace);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                ArgumentException or NotSupportedException or PathTooLongException)
            {
                return new(LibraryDefectTerminationError.FileCommitFailed, frame.Id);
            }

            LibraryDefectBakeStageResult staged = await Task.Run(() => StageBake(
                frame with { DefectRecipe = filtered },
                recipe.SourceIdentity.Value,
                stagingPath));
            if (!staged.IsSuccess)
            {
                LibraryDefectBakeFiles.DeleteStaging(stagingPath);
                return staged.Failure;
            }
            if (!document.MatchesDefectBakeSource(frame.Id, recipe, frame.SourcePath))
            {
                LibraryDefectBakeFiles.DeleteStaging(stagingPath);
                return new(LibraryDefectTerminationError.SourceChanged, frame.Id);
            }

            string destination = inPlace
                ? frame.SourcePath
                : LibraryDefectBakeFiles.CreateOwnedDestination(frame, scansDirectory);
            if (!inPlace && document.Frames.Any(candidate =>
                    !string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal) &&
                    LibraryDefectBakeFiles.SamePath(candidate.SourcePath, destination)))
            {
                LibraryDefectBakeFiles.DeleteStaging(stagingPath);
                return new(LibraryDefectTerminationError.FileCommitFailed, frame.Id);
            }
            if (!LibraryDefectBakeFiles.TryPromote(
                    stagingPath,
                    destination,
                    out LibraryDefectBakeFileCommit? fileCommit) ||
                fileCommit is null)
            {
                LibraryDefectBakeFiles.DeleteStaging(stagingPath);
                return new(LibraryDefectTerminationError.FileCommitFailed, frame.Id);
            }

            LibraryDefectRecipeWriteResult committed = document.CompleteDefectBake(
                frame.Id,
                recipe,
                frame.SourcePath,
                fileCommit.DestinationPath,
                staged.Metadata);
            if (!committed.IsSuccess)
            {
                return fileCommit.Rollback()
                    ? CatalogFailure(frame.Id, committed)
                    : new(
                        LibraryDefectTerminationError.FileRollbackFailed,
                        frame.Id,
                        SidecarError: committed.SidecarError,
                        CatalogError: committed.CatalogError);
            }
            fileCommit.Complete();
            clearLiveStrength(frame.Id);
        }
        DefectSidecarError orphanError = document.PurgeRemovedDefectSidecarsForTermination();
        if (orphanError != DefectSidecarError.None)
        {
            return new(
                LibraryDefectTerminationError.OrphanPurgeFailed,
                SidecarError: orphanError);
        }
        return LibraryDefectTerminationResult.Success();
    }

    private LibraryDefectBakeStageResult StageBake(
        LibraryFrameSnapshot frame,
        DefectSourceIdentity expectedSource,
        string stagingPath)
    {
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            stagingPath,
            DevelopExportFormat.Tiff16,
            uninvertedSource: true,
            forceDefectSourceContentVerification: true);
        if (built.Request is not { } request)
        {
            return LibraryDefectBakeStageResult.Failed(new(
                LibraryDefectTerminationError.RequestRefused,
                frame.Id,
                built.Refusal));
        }

        DevelopExportResult native;
        try
        {
            native = exporter!.BakeDefects(request);
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException or
            DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            return LibraryDefectBakeStageResult.Failed(new(
                LibraryDefectTerminationError.NativeBakeFailed,
                frame.Id,
                NativeFailureName: error.GetType().Name));
        }
        if (!native.Succeeded)
        {
            return LibraryDefectBakeStageResult.Failed(new(
                LibraryDefectTerminationError.NativeBakeFailed,
                frame.Id,
                NativeFailureName: native.FailureName));
        }
        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity current) ||
            current != expectedSource)
        {
            return LibraryDefectBakeStageResult.Failed(new(
                LibraryDefectTerminationError.SourceChanged,
                frame.Id));
        }
        if (!File.Exists(stagingPath) ||
            sourceMetadataReader(stagingPath) is not { IsValid: true } metadata)
        {
            return LibraryDefectBakeStageResult.Failed(new(
                LibraryDefectTerminationError.InvalidBakedFile,
                frame.Id));
        }
        return LibraryDefectBakeStageResult.Success(metadata);
    }

    private static LibraryDefectTerminationResult CatalogFailure(
        string frameId,
        LibraryDefectRecipeWriteResult result) => new(
            LibraryDefectTerminationError.CatalogCommitFailed,
            frameId,
            SidecarError: result.SidecarError,
            CatalogError: result.CatalogError);

    private readonly record struct LibraryDefectBakeStageResult(
        LibrarySourceMetadata? Metadata,
        LibraryDefectTerminationResult Failure)
    {
        internal bool IsSuccess => Metadata is not null && Failure.IsSuccess;

        internal static LibraryDefectBakeStageResult Success(LibrarySourceMetadata metadata) =>
            new(metadata, LibraryDefectTerminationResult.Success());

        internal static LibraryDefectBakeStageResult Failed(
            LibraryDefectTerminationResult failure) => new(null, failure);
    }
}
