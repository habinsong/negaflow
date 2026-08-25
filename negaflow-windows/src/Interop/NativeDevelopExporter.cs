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
    internal const int GrainMendDetectionV4Size = NativeDevelopAbiSizes.GrainMendDetectionV4Size;
    internal const int GrainMendReviewHitV1Size = NativeDevelopAbiSizes.GrainMendReviewHitV1Size;
    internal const int GrainMendAcceptedRegionV1Size = NativeDevelopAbiSizes.GrainMendAcceptedRegionV1Size;

    // 아래 다섯은 모두 WIC 디코더·인코더를 탑니다. STA 스레드에서 부르면 COM 이
    // `RPC_E_CHANGED_MODE` 를 돌려주어 한 줄도 읽지 못합니다 — `NativeApartment` 주석 참고.
    // 이미 MTA 면 아무 일도 하지 않으므로 값이 들지 않습니다.

    public static DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) =>
        NativeApartment.Run(() => NativeDevelopExportCommand.Run(request, run));

    public static DevelopExportResult BakeDefects(
        DevelopExportRequest request,
        DevelopRun? run = null) =>
        NativeApartment.Run(() => NativeDevelopExportCommand.BakeDefects(request, run));

    /// <remarks>
    /// <paramref name="pixels"/> 는 <c>Span</c> 이라 람다에 담을 수 없습니다. STA 일 때만
    /// 고정(pin)해 두고 주소와 길이로 건네며, 고정은 기다리는 동안 그대로 유지됩니다.
    /// </remarks>
    public static DevelopExportResult Preview(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null,
        SoftProofSettings? softProof = null,
        bool clippingOverlay = false)
    {
        if (!NativeApartment.IsSingleThreaded)
        {
            return NativeDevelopExportCommand.Preview(
                request, maximumWidth, maximumHeight, pixels, run, softProof, clippingOverlay);
        }
        fixed (byte* pinned = pixels)
        {
            byte* buffer = pinned;
            int length = pixels.Length;
            return NativeApartment.Run(() => NativeDevelopExportCommand.Preview(
                request,
                maximumWidth,
                maximumHeight,
                length == 0 ? default : new Span<byte>(buffer, length),
                run,
                softProof,
                clippingOverlay));
        }
    }

    public static DevelopExportResult PreviewBackground(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run = null)
    {
        if (!NativeApartment.IsSingleThreaded)
        {
            return NativeDevelopExportCommand.PreviewBackground(
                request, maximumWidth, maximumHeight, pixels, run);
        }
        fixed (byte* pinned = pixels)
        {
            byte* buffer = pinned;
            int length = pixels.Length;
            return NativeApartment.Run(() => NativeDevelopExportCommand.PreviewBackground(
                request,
                maximumWidth,
                maximumHeight,
                length == 0 ? default : new Span<byte>(buffer, length),
                run));
        }
    }

    public static GrainMendDetectionResult DetectGrainMend(
        DevelopExportRequest request,
        double roiX = 0.0,
        double roiY = 0.0,
        double roiWidth = 1.0,
        double roiHeight = 1.0,
        DevelopRun? run = null,
        GrainMendDetectionOptions? detectionOptions = null) =>
        NativeApartment.Run(() => NativeDevelopGrainMendDetect.DetectGrainMend(
            request, roiX, roiY, roiWidth, roiHeight, run, detectionOptions));
}
