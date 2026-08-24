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
        ulong* componentCount = null,
        ulong* previewPointCount = null,
        // macOS `applyingWholeFrameAutomaticRiskFlag` 의 결과입니다. 자동에서만 채워집니다.
        bool* automaticRisk = null,
        double* automaticCandidateFraction = null,
        nint* grainMendReview = null,
        bool clippingOverlay = false,
        bool retainPreviewRaw = true)
    {
        ValidateLayoutAndEnums(request);
        if (!retainPreviewRaw &&
            (detection is not null || softProof is not null || clippingOverlay))
        {
            throw new ArgumentException(
                "Background preview caching only supports the normal developed view.",
                nameof(retainPreviewRaw));
        }
        if (grainMendReview is not null && detection is null)
        {
            throw new ArgumentException(
                "A GrainMend review handle requires a detection result.",
                nameof(grainMendReview));
        }
        if (detection is not null && grainMendReview is null)
        {
            throw new ArgumentException(
                "A GrainMend detection requires v7 review ownership.",
                nameof(grainMendReview));
        }
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
            request.DefectRegions, request.DefectInfrared, request.DefectRecipeSha256);
        NativeDefectClonePayload clones = BuildDefectClonePayload(
            request.DefectClones);
        NativeDefectBrushPayload brushes = BuildDefectBrushPayload(
            request.DefectBrushes);
        NativeDefectRecipeEditRefV1[] defectEditOrder = BuildDefectEditOrder(request);
        byte[] defectSourceSha256 = BuildDefectSourceSha256(request);
        byte[] defectRecipeSha256 = BuildDefectRecipeSha256(request);
        byte[] defectRecipeAppendPrefixSha256 =
            BuildDefectRecipeAppendPrefixSha256(request);

        // 미리보기도 v4 자리를 줍니다. 네이티브는 struct_size 를 보고 채우므로, 작게 주면
        // 필름 베이스 실측과 개발자 디버그 지표가 통째로 빠집니다 - 현상 화면에서 dmin·
        // dmaxNorm 이 비어 있던 이유가 이것이었습니다.
        NativeDevelopExportResultV4 raw = default;
        raw.StructSize = (uint)sizeof(NativeDevelopExportResultV4);
        uint status;

        // A null run state is the pre-v22 behaviour: the call simply runs to the end.
        NativeDevelopRunStateV1* runState = run is null ? null : run.StatePointer;

        NativeSoftProofV1 nativeProof = default;
        if (softProof is not null || clippingOverlay)
        {
            nativeProof.StructSize = (uint)sizeof(NativeSoftProofV1);
            nativeProof.Enabled = softProof is { IsEnabled: true } ? 1U : 0U;
            nativeProof.SimulatePaperAndBlackInk =
                softProof?.Simulation == SoftProofSimulation.PaperAndBlackInk ? 1U : 0U;
            if (softProof is not null)
            {
                nativeProof.PaperWhiteRgb[0] = (float)softProof.PaperWhite.Red;
                nativeProof.PaperWhiteRgb[1] = (float)softProof.PaperWhite.Green;
                nativeProof.PaperWhiteRgb[2] = (float)softProof.PaperWhite.Blue;
                nativeProof.BlackInkRgb[0] = (float)softProof.BlackInk.Red;
                nativeProof.BlackInkRgb[1] = (float)softProof.BlackInk.Green;
                nativeProof.BlackInkRgb[2] = (float)softProof.BlackInk.Blue;
            }
            nativeProof.ClippingOverlay = clippingOverlay ? 1U : 0U;
        }
        NativeSoftProofV1* proofPointer =
            softProof is null && !clippingOverlay ? null : &nativeProof;

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
        fixed (byte* defectRecipeDigest = defectRecipeSha256)
        fixed (byte* defectRecipeAppendPrefixDigest = defectRecipeAppendPrefixSha256)
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
                *grainMendReview = 0;
                status = NativeGrainMendDetect.nf_develop_detect_grain_mend_v7(
                    &v27,
                    &detectionParameters,
                    runState,
                    &detectionV4,
                    (NativeDevelopExportResultV3*)&raw,
                    grainMendReview);
                if (status == NativeDevelopExportLimits.StatusOk)
                {
                    ValidateGrainMendDetectionExtension(detectionV4);
                }
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
                NativeDevelopExportRequestV34 v34 = BuildRequestV34(
                    BuildRequestV33(
                        BuildRequestV32(
                            BuildRequestV31(BuildRequestV30(v29, request), request),
                            request),
                        request,
                        null, null, null, null, null, null, null, null),
                    request);
                if (!retainPreviewRaw)
                {
                    NativeDevelopExportRequestV35 v35 = BuildRequestV35(
                        v34, defectRecipeDigest, checked((uint)defectRecipeSha256.Length));
                    status = NativeDevelopRun.nf_develop_preview_background_v1(
                        &v35, maximumWidth, maximumHeight, pixelBuffer,
                        (uint)Math.Min(pixels.Length, int.MaxValue), runState, (NativeDevelopExportResultV3*)&raw);
                }
                else if (defectRecipeSha256.Length == 0)
                {
                    status = NativeDevelopRun.nf_develop_preview_v34(
                        &v34, proofPointer, maximumWidth, maximumHeight, pixelBuffer,
                        (uint)Math.Min(pixels.Length, int.MaxValue), runState, (NativeDevelopExportResultV3*)&raw);
                }
                else
                {
                    NativeDevelopExportRequestV35 v35 = BuildRequestV35(
                        v34, defectRecipeDigest, checked((uint)defectRecipeSha256.Length));
                    NativeDevelopExportRequestV36 v36 = BuildRequestV36(
                        v35,
                        defectRecipeAppendPrefixDigest,
                        checked((uint)defectRecipeAppendPrefixSha256.Length),
                        checked((uint)request.DefectRecipeAppendPrefixEditCount));
                    status = NativeDevelopRun.nf_develop_preview_v36(
                        &v36, proofPointer, maximumWidth, maximumHeight, pixelBuffer,
                        (uint)Math.Min(pixels.Length, int.MaxValue), runState, (NativeDevelopExportResultV3*)&raw);
                }
            }
        }

        return new RenderOutcome(Translate(
            status,
            raw,
            detection is not null
                ? NativeGrainMendDetect.CurrentEntryPoint
                : !retainPreviewRaw
                    ? "nf_develop_preview_background_v1"
                : defectRecipeSha256.Length == 0
                    ? "nf_develop_preview_v34"
                    : "nf_develop_preview_v36"));
    }

    internal static void ValidateGrainMendDetectionExtension(
        NativeGrainMendDetectionV4 detection)
    {
        if (detection.V3.V2.StructSize != (uint)sizeof(NativeGrainMendDetectionV4) ||
            detection.AutomaticFalsePositiveRisk > 1U || detection.Reserved != 0U ||
            !double.IsFinite(detection.AutomaticCandidatePixelFraction) ||
            detection.AutomaticCandidatePixelFraction is < 0.0 or > 1.0)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The native GrainMend detection extension is inconsistent.");
        }
    }
}
