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
        List<string> skippedSourceMismatch = [];
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
                // 원본이 recipe 가 적어 둔 그 파일이 아니면 **이 사진만 건너뜁니다.**
                // 종료를 막지 않고, recipe 도 지우지 않습니다.
                //
                // 스캐너 TIFF 는 제자리에 굽습니다. 그래서 굽기가 원본을 갈아 끼운 뒤 뒷단계가
                // 실패하면 파일은 이미 구워졌고 recipe 는 남습니다. 그 다음부터는 기대 크기와
                // 실제 크기가 영원히 어긋나고, 여기서 실패를 돌리면 **앱을 다시는 닫을 수
                // 없습니다** - 실기에서 사용자가 종료할 때마다 대화상자를 봤습니다
                // (OpticFilm8100-0002.tif: 기대 109,181,328 실제 109,216,380).
                //
                // macOS 에는 이 관문 자체가 없습니다(`AppModel+DefectBakeOnQuit.swift` 는
                // 원본에서 바로 합성합니다). 그래서 이 상태에 빠지지 않습니다. Windows 는
                // 관문을 지키되 **막다른 골목을 만들지 않습니다** - 편집을 버리지도, 어긋난
                // 원본에 덮어쓰지도 않고, 다음 실행이 다시 다룰 수 있게 그대로 둡니다.
                if (staged.Failure.Error == LibraryDefectTerminationError.NativeBakeFailed &&
                    string.Equals(
                        staged.Failure.NativeFailureName,
                        SourceIdentityMismatch,
                        StringComparison.Ordinal))
                {
                    skippedSourceMismatch.Add(frame.Id);
                    clearLiveStrength(frame.Id);
                    continue;
                }
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
        if (skippedSourceMismatch.Count != 0)
        {
            // 종료는 막지 않지만 조용히 넘어가지도 않습니다. 어느 사진을 못 구웠는지 남깁니다.
            // **늘 켜진 기록에 남깁니다** — 개발자 모드에서만 켜지는 기록에 적으면 실기에서
            // 무슨 일이 있었는지 볼 수 없습니다.
            string skipped = string.Join(',', skippedSourceMismatch);
            Negaflow.Shell.Diagnostics.TerminationLog.Write(
                $"defect bake skipped source mismatch: {skipped}");
            PreviewTrace.Write("defect bake skipped source mismatch " + skipped);
        }
        Negaflow.Shell.Diagnostics.TerminationLog.Write(
            $"defect bake ok frames={frameIds.Length} skipped={skippedSourceMismatch.Count}");
        return LibraryDefectTerminationResult.Success();
    }

    /// <summary>
    /// 엔진이 "원본이 recipe 가 적어 둔 그 파일이 아니다" 라고 답할 때의 이름입니다
    /// (`src/Native/pipeline/export/stages/observe.cpp`).
    /// </summary>
    private const string SourceIdentityMismatch = "defect_source_identity_mismatch";

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
