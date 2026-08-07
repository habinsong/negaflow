namespace Negaflow.Interop;

/// <summary>
/// Drives the native develop-and-export pipeline across the C ABI.
/// </summary>
/// <remarks>
/// The call blocks for the whole develop, which on a full frame is far longer than a
/// UI frame. Callers on the WinUI thread must run it on a worker and marshal the
/// result back through a captured <c>DispatcherQueue</c>; this type deliberately
/// offers no async wrapper so that decision stays visible at the call site.
/// </remarks>
public static unsafe class NativeDevelopExporter
{
    internal const int RequestV1Size = 96;
    internal const int ResultV1Size = 136;

    private const uint StatusOk = 0;
    private const uint StatusInvalidArgument = 1;
    private const uint StatusStructTooSmall = 2;

    public static DevelopExportResult Run(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (sizeof(NativeDevelopExportRequestV1) != RequestV1Size ||
            sizeof(NativeDevelopExportResultV1) != ResultV1Size)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The managed develop-export layout does not match the C ABI.");
        }
        if (!Enum.IsDefined(request.Format) ||
            !Enum.IsDefined(request.FilmType) ||
            !Enum.IsDefined(request.FilmLookSourceKind) ||
            !Enum.IsDefined(request.FilmEmulation))
        {
            throw new ArgumentException(
                "The develop request carries a value outside its enumeration.",
                nameof(request));
        }

        NativeDevelopExportResultV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV1);
        uint status;

        // The native side copies both paths before returning, so pinning them for the
        // duration of the call is enough; no unmanaged allocation is needed.
        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        {
            NativeDevelopExportRequestV1 native = new()
            {
                StructSize = (uint)sizeof(NativeDevelopExportRequestV1),
                SourcePath = sourcePath,
                DestinationPath = destinationPath,
                OutputFormat = (uint)request.Format,
                FilmType = (uint)request.FilmType,
                DminRed = request.DminRed,
                DminGreen = request.DminGreen,
                DminBlue = request.DminBlue,
                ExposureStops = request.ExposureStops,
                Contrast = request.Contrast,
                Highlights = request.Highlights,
                Lights = request.Lights,
                Darks = request.Darks,
                Shadows = request.Shadows,
                FilmLookSourceKind = (uint)request.FilmLookSourceKind,
                FilmEmulation = (uint)request.FilmEmulation,
                FilmEmulationIntensity = request.FilmEmulationIntensity,
                RowsPerCopy = request.RowsPerCopy,
            };
            status = NativeMethods.nf_develop_export_v1(&native, &raw);
        }

        if (status != StatusOk)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.NativeCallFailed,
                status switch
                {
                    StatusInvalidArgument =>
                        "nf_develop_export_v1 rejected the call as malformed.",
                    StatusStructTooSmall =>
                        "nf_develop_export_v1 rejected the struct sizes.",
                    _ => $"nf_develop_export_v1 failed with status {status}.",
                });
        }

        DevelopExportStage stage = (DevelopExportStage)raw.FailedStage;
        FilmLookRoute route = (FilmLookRoute)raw.FilmLookRoute;
        if (!Enum.IsDefined(stage) || !Enum.IsDefined(route))
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
            raw.WallMicroseconds);
    }
}
