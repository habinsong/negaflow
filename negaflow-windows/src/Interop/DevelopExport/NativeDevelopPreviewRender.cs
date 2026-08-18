namespace Negaflow.Interop;

using static NativeDevelopRequestValidator;
using static NativeDevelopLocalPayload;
using static NativeDevelopDefectRegionPayloadBuilder;
using static NativeDevelopDefectStrokePayload;
using static NativeDevelopRequestV18V34;
using static NativeDevelopResultTranslator;

/// <summary>미리보기·검출이 공유하는 렌더 호출입니다.</summary>
internal static unsafe class NativeDevelopPreviewRender
{
    internal readonly ref struct RenderOutcome
    {
        public RenderOutcome(DevelopExportResult result) => Result = result;

        public DevelopExportResult Result { get; }
    }

    internal static RenderOutcome Render(
        DevelopExportRequest request,
        uint maximumWidth,
        uint maximumHeight,
        Span<byte> pixels,
        DevelopRun? run,
        SoftProofSettings? softProof,
        NativeGrainMendDetectionV2* detection,
        double roiX = 0.0,
        double roiY = 0.0,
        double roiWidth = 1.0,
        double roiHeight = 1.0,
        GrainMendDetectionOptions? detectionOptions = null,
        NativeGrainMendComponentV1* components = null,
        ulong componentCapacity = 0UL,
        ulong* componentCount = null,
        NativeGrainMendPreviewPointV1* previewPoints = null,
        ulong previewPointCapacity = 0UL,
        ulong* previewPointCount = null,
        // macOS `applyingWholeFrameAutomaticRiskFlag` 의 결과입니다. 자동에서만 채워집니다.
        bool* automaticRisk = null,
        double* automaticCandidateFraction = null)
    {
        ValidateLayoutAndEnums(request);
        GrainMendDetectionOptions effectiveDetectionOptions =
            detectionOptions ?? GrainMendDetectionOptions.LegacyDefault;
        if (detection is not null &&
            (!double.IsFinite(effectiveDetectionOptions.DustSensitivity) ||
             effectiveDetectionOptions.DustSensitivity is < 0.0 or > 1.0 ||
             !double.IsFinite(effectiveDetectionOptions.ScratchSensitivity) ||
             effectiveDetectionOptions.ScratchSensitivity is < 0.0 or > 1.0 ||
             !double.IsFinite(effectiveDetectionOptions.ProtectDetail) ||
             effectiveDetectionOptions.ProtectDetail is < 0.0 or > 1.0))
        {
            throw new ArgumentException(
                "GrainMend detection settings must be finite values from zero through one.",
                nameof(detectionOptions));
        }
        NativeLocalDodgeBurnPayload local = BuildLocalDodgeBurnPayload(
            request.LocalDodgeBurn);
        NativeDefectRegionPayload defects = BuildDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared);
        NativeDefectClonePayload clones = BuildDefectClonePayload(
            request.DefectClones);
        NativeDefectBrushPayload brushes = BuildDefectBrushPayload(
            request.DefectBrushes);
        NativeDefectRecipeEditRefV1[] defectEditOrder = BuildDefectEditOrder(request);
        byte[] defectSourceSha256 = BuildDefectSourceSha256(request);

        NativeDevelopExportResultV3 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV3);
        uint status;

        // A null run state is the pre-v22 behaviour: the call simply runs to the end.
        NativeDevelopRunStateV1* runState = run is null ? null : run.StatePointer;

        NativeSoftProofV1 nativeProof = default;
        if (softProof is not null)
        {
            nativeProof.StructSize = (uint)sizeof(NativeSoftProofV1);
            nativeProof.Enabled = softProof.IsEnabled ? 1U : 0U;
            nativeProof.SimulatePaperAndBlackInk =
                softProof.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1U : 0U;
            nativeProof.PaperWhiteRgb[0] = (float)softProof.PaperWhite.Red;
            nativeProof.PaperWhiteRgb[1] = (float)softProof.PaperWhite.Green;
            nativeProof.PaperWhiteRgb[2] = (float)softProof.PaperWhite.Blue;
            nativeProof.BlackInkRgb[0] = (float)softProof.BlackInk.Red;
            nativeProof.BlackInkRgb[1] = (float)softProof.BlackInk.Green;
            nativeProof.BlackInkRgb[2] = (float)softProof.BlackInk.Blue;
        }
        NativeSoftProofV1* proofPointer = softProof is null ? null : &nativeProof;

        fixed (char* sourcePath = request.SourcePath)
        fixed (char* destinationPath = request.DestinationPath)
        fixed (char* filmStockDminId = request.FilmStockDminId)
        fixed (char* lightSourceProfileId = request.LightSourceProfileId)
        fixed (char* scannerProfileId = request.ScannerProfileId)
        fixed (byte* pixelBuffer = pixels)
        fixed (NativeLocalDodgeBurnAdjustmentV1* localAdjustments = local.Adjustments)
        fixed (NativeLocalDodgeBurnStrokeV1* localStrokes = local.Strokes)
        fixed (NativeLocalDodgeBurnPointV1* localPoints = local.Points)
        fixed (NativeDefectRegionEditV1* defectRegionEdits = defects.Edits)
        fixed (byte* defectMaskBytes = defects.MaskBytes)
        fixed (byte* defectSourceDigest = defectSourceSha256)
        fixed (NativeDefectCloneEditV1* defectCloneEdits = clones.Edits)
        fixed (NativeDefectCloneStrokeV1* defectCloneStrokes = clones.Strokes)
        fixed (NativeDefectClonePointV1* defectClonePoints = clones.Points)
        fixed (NativeDefectRecipeEditRefV1* nativeDefectEditOrder = defectEditOrder)
        fixed (NativeDefectBrushEditV1* defectBrushEdits = brushes.Edits)
        fixed (NativeDefectBrushStrokeV1* defectBrushStrokes = brushes.Strokes)
        fixed (NativeDefectBrushPointV1* defectBrushPoints = brushes.Points)
        fixed (NativeDefectInfraredEditV1* defectInfraredEdits =
            defects.InfraredEdits)
        fixed (byte* defectInfraredAttenuationBytes =
            defects.InfraredAttenuationBytes)
        fixed (NativeDefectInfraredItemV1* defectInfraredItems =
            defects.InfraredItems)
        {
            NativeDevelopExportRequestV20 v20 = BuildRequestV20(
                request,
                sourcePath,
                destinationPath,
                filmStockDminId,
                lightSourceProfileId,
                scannerProfileId,
                localAdjustments,
                checked((uint)local.Adjustments.Length),
                localStrokes,
                checked((uint)local.Strokes.Length),
                localPoints,
                checked((uint)local.Points.Length),
                defectRegionEdits,
                checked((uint)defects.Edits.Length),
                defectMaskBytes,
                checked((uint)defects.MaskBytes.Length),
                defectSourceDigest,
                defectCloneEdits,
                checked((uint)clones.Edits.Length),
                defectCloneStrokes,
                checked((uint)clones.Strokes.Length),
                defectClonePoints,
                checked((uint)clones.Points.Length),
                nativeDefectEditOrder,
                checked((uint)defectEditOrder.Length));
            NativeDevelopExportRequestV21 v21 = BuildRequestV21(
                v20,
                defectBrushEdits,
                checked((uint)brushes.Edits.Length),
                defectBrushStrokes,
                checked((uint)brushes.Strokes.Length),
                defectBrushPoints,
                checked((uint)brushes.Points.Length));
            NativeDevelopExportRequestV24 v24 = BuildRequestV24(
                v21,
                defectInfraredEdits,
                checked((uint)defects.InfraredEdits.Length),
                defectInfraredAttenuationBytes,
                checked((uint)defects.InfraredAttenuationBytes.Length));
            NativeDevelopExportRequestV25 v25 = BuildRequestV25(
                v24,
                defectInfraredItems,
                checked((uint)defects.InfraredItems.Length));
            NativeDevelopExportRequestV26 v26 = BuildRequestV26(v25, request);
            NativeDevelopExportRequestV27 v27 = BuildRequestV27(v26, request);
            if (detection is not null)
            {
                NativeGrainMendDetectParametersV3 detectionParameters = new()
                {
                    V2 = new NativeGrainMendDetectParametersV2
                    {
                        V1 = new NativeGrainMendDetectParametersV1
                        {
                            StructSize = (uint)sizeof(NativeGrainMendDetectParametersV3),
                            RoiX = roiX,
                            RoiY = roiY,
                            RoiWidth = roiWidth,
                            RoiHeight = roiHeight,
                        },
                        DustSensitivity = effectiveDetectionOptions.DustSensitivity,
                        ScratchSensitivity = effectiveDetectionOptions.ScratchSensitivity,
                        ProtectDetail = effectiveDetectionOptions.ProtectDetail,
                        RejectStructureLines =
                            effectiveDetectionOptions.RejectStructureLines ? 1U : 0U,
                    },
                    DetectMicroSpecks = effectiveDetectionOptions.DetectMicroSpecks ? 1U : 0U,
                };
                // 중첩 구조라 가장 안쪽 V2 의 StructSize 가 전체 크기를 말합니다.
                NativeGrainMendDetectionV4 detectionV4 = default;
                detectionV4.V3.V2.StructSize = (uint)sizeof(NativeGrainMendDetectionV4);
                status = NativeGrainMendDetect.nf_develop_detect_grain_mend_v6(
                    &v27,
                    &detectionParameters,
                    pixels.IsEmpty ? null : pixelBuffer,
                    (ulong)pixels.Length,
                    components,
                    componentCapacity,
                    previewPoints,
                    previewPointCapacity,
                    runState,
                    &detectionV4,
                    &raw);
                *detection = detectionV4.V3.V2;
                detection->StructSize = (uint)sizeof(NativeGrainMendDetectionV2);
                if (componentCount is not null)
                {
                    *componentCount = detectionV4.V3.ComponentCount;
                }
                if (previewPointCount is not null)
                {
                    *previewPointCount = detectionV4.V3.PreviewPointCount;
                }
                if (automaticRisk is not null)
                {
                    *automaticRisk = detectionV4.AutomaticFalsePositiveRisk != 0U;
                }
                if (automaticCandidateFraction is not null)
                {
                    *automaticCandidateFraction =
                        detectionV4.AutomaticCandidatePixelFraction;
                }
            }
            else
            {
                NativeDevelopExportRequestV28 v28 = BuildRequestV28(v27, request);
                NativeDevelopExportRequestV29 v29 = BuildRequestV29(v28, request);
                NativeDevelopExportRequestV34 native = BuildRequestV34(BuildRequestV33(
                    BuildRequestV32(
                        BuildRequestV31(BuildRequestV30(v29, request), request),
                        request),
                    request,
                    null, null, null, null, null, null, null, null), request);
                status = NativeDevelopRun.nf_develop_preview_v34(
                    &native,
                    proofPointer,
                    maximumWidth,
                    maximumHeight,
                    pixelBuffer,
                    (uint)Math.Min(pixels.Length, int.MaxValue),
                    runState,
                    &raw);
            }
        }

        return new RenderOutcome(Translate(
            status,
            raw,
            detection is not null
                ? "nf_develop_detect_grain_mend_v4"
                : "nf_develop_preview_v34"));
    }
}
