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
    internal const int RequestV1Size = NativeDevelopAbiSizes.RequestV1Size;
    internal const int ResultV1Size = NativeDevelopAbiSizes.ResultV1Size;
    internal const int RequestV2Size = NativeDevelopAbiSizes.RequestV2Size;
    internal const int RequestV3Size = NativeDevelopAbiSizes.RequestV3Size;
    internal const int RequestV4Size = NativeDevelopAbiSizes.RequestV4Size;
    internal const int PointCurveV1Size = NativeDevelopAbiSizes.PointCurveV1Size;
    internal const int RequestV5Size = NativeDevelopAbiSizes.RequestV5Size;
    internal const int RequestV6Size = NativeDevelopAbiSizes.RequestV6Size;
    internal const int RequestV7Size = NativeDevelopAbiSizes.RequestV7Size;
    internal const int RequestV8Size = NativeDevelopAbiSizes.RequestV8Size;
    internal const int RequestV9Size = NativeDevelopAbiSizes.RequestV9Size;
    internal const int RequestV10Size = NativeDevelopAbiSizes.RequestV10Size;
    internal const int RequestV11Size = NativeDevelopAbiSizes.RequestV11Size;
    internal const int LocalDodgeBurnPointV1Size = NativeDevelopAbiSizes.LocalDodgeBurnPointV1Size;
    internal const int LocalDodgeBurnStrokeV1Size = NativeDevelopAbiSizes.LocalDodgeBurnStrokeV1Size;
    internal const int LocalDodgeBurnAdjustmentV1Size = NativeDevelopAbiSizes.LocalDodgeBurnAdjustmentV1Size;
    internal const int RequestV12Size = NativeDevelopAbiSizes.RequestV12Size;
    internal const int RequestV13Size = NativeDevelopAbiSizes.RequestV13Size;
    internal const int RequestV14Size = NativeDevelopAbiSizes.RequestV14Size;
    internal const int RequestV15Size = NativeDevelopAbiSizes.RequestV15Size;
    internal const int RequestV16Size = NativeDevelopAbiSizes.RequestV16Size;
    internal const int RequestV17Size = NativeDevelopAbiSizes.RequestV17Size;
    internal const int DefectRegionEditV1Size = NativeDevelopAbiSizes.DefectRegionEditV1Size;
    internal const int RequestV18Size = NativeDevelopAbiSizes.RequestV18Size;
    internal const int RequestV19Size = NativeDevelopAbiSizes.RequestV19Size;
    internal const int DefectClonePointV1Size = NativeDevelopAbiSizes.DefectClonePointV1Size;
    internal const int DefectCloneStrokeV1Size = NativeDevelopAbiSizes.DefectCloneStrokeV1Size;
    internal const int DefectCloneEditV1Size = NativeDevelopAbiSizes.DefectCloneEditV1Size;
    internal const int DefectRecipeEditRefV1Size = NativeDevelopAbiSizes.DefectRecipeEditRefV1Size;
    internal const int RequestV20Size = NativeDevelopAbiSizes.RequestV20Size;
    internal const int DefectBrushPointV1Size = NativeDevelopAbiSizes.DefectBrushPointV1Size;
    internal const int DefectBrushStrokeV1Size = NativeDevelopAbiSizes.DefectBrushStrokeV1Size;
    internal const int DefectBrushEditV1Size = NativeDevelopAbiSizes.DefectBrushEditV1Size;
    internal const int RequestV21Size = NativeDevelopAbiSizes.RequestV21Size;
    internal const int DefectInfraredEditV1Size = NativeDevelopAbiSizes.DefectInfraredEditV1Size;
    internal const int RequestV24Size = NativeDevelopAbiSizes.RequestV24Size;
    internal const int DefectInfraredItemV1Size = NativeDevelopAbiSizes.DefectInfraredItemV1Size;
    internal const int RequestV25Size = NativeDevelopAbiSizes.RequestV25Size;
    internal const int RequestV26Size = NativeDevelopAbiSizes.RequestV26Size;
    internal const int RequestV27Size = NativeDevelopAbiSizes.RequestV27Size;
    internal const int RequestV28Size = NativeDevelopAbiSizes.RequestV28Size;
    internal const int RequestV29Size = NativeDevelopAbiSizes.RequestV29Size;
    internal const int RequestV30Size = NativeDevelopAbiSizes.RequestV30Size;
    internal const int RequestV31Size = NativeDevelopAbiSizes.RequestV31Size;
    internal const int RequestV32Size = NativeDevelopAbiSizes.RequestV32Size;
    internal const int RequestV33Size = NativeDevelopAbiSizes.RequestV33Size;
    internal const int ResultV2Size = NativeDevelopAbiSizes.ResultV2Size;
    internal const int ResultV3Size = NativeDevelopAbiSizes.ResultV3Size;
    internal const int RunStateV1Size = NativeDevelopAbiSizes.RunStateV1Size;
    internal const int AutoAdjustResultV1Size = NativeDevelopAbiSizes.AutoAdjustResultV1Size;
    internal const int SoftProofMediaV1Size = NativeDevelopAbiSizes.SoftProofMediaV1Size;
    internal const int SoftProofV1Size = NativeDevelopAbiSizes.SoftProofV1Size;
    internal const int GrainMendDetectParametersV1Size = NativeDevelopAbiSizes.GrainMendDetectParametersV1Size;
    internal const int GrainMendDetectParametersV2Size = NativeDevelopAbiSizes.GrainMendDetectParametersV2Size;
    internal const int GrainMendDetectParametersV3Size = NativeDevelopAbiSizes.GrainMendDetectParametersV3Size;
    internal const int GrainMendDetectionV2Size = NativeDevelopAbiSizes.GrainMendDetectionV2Size;

    public static DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) =>
        NativeDevelopExportCommand.Run(request, run);

    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false) =>
        NativeDevelopExportCommand.Preview(
            request, maximumWidth, maximumHeight, pixels, run, softProof, clippingOverlay);

    public static DevelopExportResult PreviewBackground(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null) =>
        NativeDevelopExportCommand.PreviewBackground(
            request, maximumWidth, maximumHeight, pixels, run);

    public static GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        Span<byte> mask,
        double roiX = 0.0,
        double roiY = 0.0,
        double roiWidth = 1.0,
        double roiHeight = 1.0,
        DevelopRun? run = null,
        GrainMendDetectionOptions? detectionOptions = null) =>
        NativeDevelopGrainMendDetect.DetectGrainMend(
            request, mask, roiX, roiY, roiWidth, roiHeight, run, detectionOptions);
}
