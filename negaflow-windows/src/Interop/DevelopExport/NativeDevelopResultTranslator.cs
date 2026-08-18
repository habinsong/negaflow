namespace Negaflow.Interop;

using static NativeDevelopExportLimits;

/// <summary>네이티브 결과를 managed 결과로 바꿉니다.</summary>
internal static class NativeDevelopResultTranslator
{
    internal static DevelopExportResult Translate(
        uint status,
        NativeDevelopExportResultV4 raw,
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
            raw.Cancelled != 0,
            ReadMeasurement(raw.Measurement),
            FilmBaseMeasurementSnapshot.MethodName(raw.Measurement.Method));
    }

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

    private static FilmBaseMeasurementSnapshot? ReadMeasurement(
        NativeFilmBaseMeasurementV1 packed)
    {
        if (packed.Present == 0)
        {
            return null;
        }
        return new FilmBaseMeasurementSnapshot
        {
            SchemaVersion = (int)packed.SchemaVersion,
            Method = FilmBaseMeasurementSnapshot.MethodName(packed.Method) ?? "unknown",
            SampledPixelCount = packed.SampledPixelCount,
            CandidateCount = packed.CandidateCount,
            SelectedSampleCount = packed.SelectedSampleCount,
            RetainedSampleCount = packed.RetainedSampleCount,
            SampleCoverage = packed.SampleCoverage,
            SpatialCoverage = packed.SpatialCoverage,
            MedianLuma = packed.MedianLuma,
            LumaMad = packed.LumaMad,
            ChannelMad = [packed.ChannelMad0, packed.ChannelMad1, packed.ChannelMad2],
            ChromaticityMad = packed.ChromaticityMad,
            ClippedFraction = packed.ClippedFraction,
            OutlierFraction = packed.OutlierFraction,
            SampleSupport = packed.SampleSupport,
            EvidenceSampleCoverage = packed.EvSampleCoverage,
            EvidenceSpatialCoverage = packed.EvSpatialCoverage,
            LumaUniformity = packed.LumaUniformity,
            ChannelConsistency = packed.ChannelConsistency,
            UnclippedSamples = packed.UnclippedSamples,
            InlierRetention = packed.InlierRetention,
            EvidenceScore = packed.EvidenceScore,
            IsCalibratedProbability = packed.IsCalibratedProbability != 0,
            Anomalies = FilmBaseMeasurementSnapshot.AnomaliesFromBits(packed.AnomalyBits),
        };
    }
}
