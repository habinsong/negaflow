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

    private static void ValidateLayoutAndEnums(DevelopExportRequest request)
    {
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
    }

    private static NativeDevelopExportRequestV1 BuildRequest(
        DevelopExportRequest request,
        char* sourcePath,
        char* destinationPath) => new()
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

    public static DevelopExportResult Run(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        ValidateLayoutAndEnums(request);

        NativeDevelopExportResultV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV1);
        uint status;

        // The native side copies both paths before returning, so pinning them for the
        // duration of the call is enough; no unmanaged allocation is needed.
        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        {
            NativeDevelopExportRequestV1 native = BuildRequest(
                request,
                sourcePath,
                destinationPath);
            status = NativeMethods.nf_develop_export_v1(&native, &raw);
        }

        return Translate(status, raw);
    }

    /// <summary>
    /// 같은 파이프라인을 돌리되 파일을 쓰지 않고 <paramref name="pixels"/> 에 BGRA8 표시용
    /// 비트맵을 채웁니다. 실제로 쓰인 크기는 결과의 <c>ImageWidth</c>/<c>ImageHeight</c> 입니다.
    /// </summary>
    /// <remarks>
    /// <see cref="Run"/> 과 마찬가지로 블로킹입니다. UI 스레드에서 부르지 마십시오.
    /// </remarks>
    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels)
    {
        ArgumentNullException.ThrowIfNull(request);
        ArgumentOutOfRangeException.ThrowIfZero(maximumWidth);
        ArgumentOutOfRangeException.ThrowIfZero(maximumHeight);
        if (pixels.IsEmpty)
        {
            throw new ArgumentException("The preview buffer is empty.", nameof(pixels));
        }
        ValidateLayoutAndEnums(request);

        NativeDevelopExportResultV1 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV1);
        uint status;

        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (byte* pixelBuffer = pixels)
        {
            NativeDevelopExportRequestV1 native = BuildRequest(
                request,
                sourcePath,
                destinationPath);
            status = NativeMethods.nf_develop_preview_v1(
                &native,
                maximumWidth,
                maximumHeight,
                pixelBuffer,
                (uint)Math.Min(pixels.Length, int.MaxValue),
                &raw);
        }

        return Translate(status, raw);
    }

    private static DevelopExportResult Translate(
        uint status,
        NativeDevelopExportResultV1 raw)
    {
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
