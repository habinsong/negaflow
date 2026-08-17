namespace Negaflow.Interop;

using static NativeDevelopExportLimits;

/// <summary>네이티브 결과를 managed 결과로 바꿉니다.</summary>
internal static class NativeDevelopResultTranslator
{
    internal static DevelopExportResult Translate(
        uint status,
        NativeDevelopExportResultV3 raw,
        string functionName)
    {
        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                status switch
                {
                    StatusInvalidArgument =>
                    $"{functionName} rejected the call as malformed.",
                    StatusStructTooSmall =>
                    $"{functionName} rejected the struct sizes.",
                    _ => $"{functionName} failed with status {status}.",
                });
        }

        DevelopExportStage stage = (DevelopExportStage)raw.FailedStage;
        FilmLookRoute route = (FilmLookRoute)raw.FilmLookRoute;
        DevelopBaseSource baseSource = (DevelopBaseSource)raw.BaseSource;
        if (!Enum.IsDefined(stage) || !Enum.IsDefined(route) || !Enum.IsDefined(baseSource))
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native develop result reported an unknown stage or route.");
        }

        return new DevelopExportResult(
            raw.Succeeded != 0,
            stage,
            raw.GetFailureName(),
            raw.NativeErrorCode,
            raw.CleanupErrorCode,
            raw.ImageWidth,
            raw.ImageHeight,
            route,
            raw.FilmLookColorApplied != 0,
            raw.FilmLookAcutanceApplied != 0,
            raw.SourceFileBytes,
            raw.OutputFileBytes,
            raw.FilmLookWorkspaceBytes,
            raw.WallMicroseconds,
            raw.AppliedDminRed,
            raw.AppliedDminGreen,
            raw.AppliedDminBlue,
            baseSource,
            raw.Cancelled != 0);
    }
}
