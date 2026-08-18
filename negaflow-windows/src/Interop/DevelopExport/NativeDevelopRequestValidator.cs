namespace Negaflow.Interop;

using static NativeDevelopAbiSizes;
using static NativeDevelopToneValidator;
using static NativeDevelopLocalValidator;
using static NativeDevelopDefectValidator;

/// <summary>요청 검증 순서입니다. 개별 검증기와 다른 이유입니다.</summary>
internal static unsafe class NativeDevelopRequestValidator
{
    internal static void ValidateLayoutAndEnums(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request.ImageTransform);
        if (sizeof(NativePointCurveV1) != PointCurveV1Size ||
            sizeof(NativeDevelopExportRequestV7) != RequestV7Size ||
            sizeof(NativeDevelopExportRequestV8) != RequestV8Size ||
            sizeof(NativeDevelopExportRequestV9) != RequestV9Size ||
            sizeof(NativeDevelopExportRequestV10) != RequestV10Size ||
            sizeof(NativeDevelopExportRequestV11) != RequestV11Size ||
            sizeof(NativeLocalDodgeBurnPointV1) != LocalDodgeBurnPointV1Size ||
            sizeof(NativeLocalDodgeBurnStrokeV1) != LocalDodgeBurnStrokeV1Size ||
            sizeof(NativeLocalDodgeBurnAdjustmentV1) != LocalDodgeBurnAdjustmentV1Size ||
            sizeof(NativeDevelopExportRequestV12) != RequestV12Size ||
            sizeof(NativeDevelopExportRequestV13) != RequestV13Size ||
            sizeof(NativeDevelopExportRequestV14) != RequestV14Size ||
            sizeof(NativeDevelopExportRequestV15) != RequestV15Size ||
            sizeof(NativeDevelopExportRequestV16) != RequestV16Size ||
            sizeof(NativeDevelopExportRequestV17) != RequestV17Size ||
            sizeof(NativeDefectRegionEditV1) != DefectRegionEditV1Size ||
            sizeof(NativeDevelopExportRequestV18) != RequestV18Size ||
            sizeof(NativeDevelopExportRequestV19) != RequestV19Size ||
            sizeof(NativeDefectClonePointV1) != DefectClonePointV1Size ||
            sizeof(NativeDefectCloneStrokeV1) != DefectCloneStrokeV1Size ||
            sizeof(NativeDefectCloneEditV1) != DefectCloneEditV1Size ||
            sizeof(NativeDefectRecipeEditRefV1) != DefectRecipeEditRefV1Size ||
            sizeof(NativeDevelopExportRequestV20) != RequestV20Size ||
            sizeof(NativeDefectBrushPointV1) != DefectBrushPointV1Size ||
            sizeof(NativeDefectBrushStrokeV1) != DefectBrushStrokeV1Size ||
            sizeof(NativeDefectBrushEditV1) != DefectBrushEditV1Size ||
            sizeof(NativeDevelopExportRequestV21) != RequestV21Size ||
            sizeof(NativeDefectInfraredEditV1) != DefectInfraredEditV1Size ||
            sizeof(NativeDevelopExportRequestV24) != RequestV24Size ||
            sizeof(NativeDefectInfraredItemV1) != DefectInfraredItemV1Size ||
            sizeof(NativeDevelopExportRequestV25) != RequestV25Size ||
            sizeof(NativeDevelopExportRequestV26) != RequestV26Size ||
            sizeof(NativeDevelopExportRequestV27) != RequestV27Size ||
            sizeof(NativeDevelopExportRequestV28) != RequestV28Size ||
            sizeof(NativeDevelopExportRequestV29) != RequestV29Size ||
            sizeof(NativeDevelopExportRequestV30) != RequestV30Size ||
            sizeof(NativeDevelopExportRequestV31) != RequestV31Size ||
            sizeof(NativeDevelopExportRequestV32) != RequestV32Size ||
            sizeof(NativeDevelopExportRequestV33) != RequestV33Size ||
            sizeof(NativeDevelopExportResultV2) != ResultV2Size ||
            sizeof(NativeDevelopExportResultV3) != ResultV3Size ||
            sizeof(NativeFilmBaseMeasurementV1) != FilmBaseMeasurementV1Size ||
            sizeof(NativeDevelopExportResultV4) != ResultV4Size ||
            sizeof(NativeDevelopRunStateV1) != RunStateV1Size ||
            sizeof(NativeAutoAdjustResultV1) != AutoAdjustResultV1Size ||
            sizeof(NativeSoftProofMediaV1) != SoftProofMediaV1Size ||
            sizeof(NativeSoftProofV1) != SoftProofV1Size ||
            sizeof(NativeGrainMendDetectParametersV1) != GrainMendDetectParametersV1Size ||
            sizeof(NativeGrainMendDetectParametersV2) != GrainMendDetectParametersV2Size ||
            sizeof(NativeGrainMendDetectParametersV3) != GrainMendDetectParametersV3Size ||
            sizeof(NativeGrainMendDetectionV2) != GrainMendDetectionV2Size)
        {
            throw new NativeBootstrapException(
                NativeBootstrapFailure.ContractViolation,
                "The managed develop-export layout does not match the C ABI.");
        }
        if (!Enum.IsDefined(request.Format) ||
            !Enum.IsDefined(request.FilmType) ||
            !Enum.IsDefined(request.FilmPolarity) ||
            !Enum.IsDefined(request.BaseEstimationMode) ||
            !Enum.IsDefined(request.FilmLookSourceKind) ||
            !Enum.IsDefined(request.FilmEmulation) ||
            !Enum.IsDefined(request.DevelopTarget) ||
            !Enum.IsDefined(request.NoiseReductionFilmProfile) ||
            !Enum.IsDefined(request.BwToningMode) ||
            !Enum.IsDefined(request.ImageTransform.Rotation) ||
            !Enum.IsDefined(request.OutputSharpeningMedium) ||
            !Enum.IsDefined(request.TiffCompression))
        {
            throw new ArgumentException(
                "The develop request carries a value outside its enumeration.",
                nameof(request));
        }
        ValidatePointCurves(request.PointCurves);
        ValidateColorMixer(request.ColorMixer);
        ValidateColorGrading(request.ColorGrading);
        ValidatePrimaryCalibration(request.PrimaryCalibration);
        ValidateLocalDodgeBurn(request.LocalDodgeBurn);
        ValidateDefectRegions(request.DefectRegions);
        ValidateDefectInfrared(request.DefectInfrared);
        ValidateCombinedDefectRegionPayload(
            request.DefectRegions, request.DefectInfrared);
        ValidateDefectClones(request.DefectClones);
        ValidateDefectBrushes(request.DefectBrushes);
        ValidateDefectEditOrder(request);
        ValidateDefectSourceIdentity(
            request.DefectRegions.Count + request.DefectInfrared.Count +
                request.DefectClones.Count +
                request.DefectBrushes.Count,
            request.DefectSourceIdentity);
        if (!SignedNormalized(request.Warmth) ||
            !SignedNormalized(request.Tint) ||
            !SignedNormalized(request.ColorDepth) ||
            !SignedNormalized(request.Vibrance) ||
            !SignedNormalized(request.Saturation) ||
            !SignedNormalized(request.RedPrimary) ||
            !SignedNormalized(request.GreenPrimary) ||
            !SignedNormalized(request.BluePrimary))
        {
            throw new ArgumentException(
                "ColorModel controls are outside the supported finite range.",
                nameof(request));
        }
        if (!double.IsFinite(request.DefectRemovalStrength) ||
            request.DefectRemovalStrength is < 0.0 or > 1.0)
        {
            throw new ArgumentException(
                "GrainMend strength must be a finite value from zero through one.",
                nameof(request));
        }
        if (!Normalized(request.NoiseReductionStrength) ||
            !Normalized(request.NoiseReductionLuma) ||
            !Normalized(request.NoiseReductionChroma) ||
            !Normalized(request.NoiseReductionDarkTone) ||
            !Normalized(request.NoiseReductionDetail) ||
            !Normalized(request.NoiseReductionGrainProtect))
        {
            throw new ArgumentException(
                "FilmScanDenoise controls must be finite values from zero through one.",
                nameof(request));
        }
        if (!Normalized(request.Grain) ||
            !Normalized(request.Sharpness) ||
            !Normalized(request.Halation) ||
            !SignedNormalized(request.Clarity) ||
            !SignedNormalized(request.Vignette))
        {
            throw new ArgumentException(
                "Texture controls are outside the supported finite range.",
                nameof(request));
        }
        if (!Normalized(request.OutputSharpening) || request.OutputSharpeningDpi < 0 ||
            !Normalized(request.JpegQuality))
        {
            throw new ArgumentException(
                "Output controls are outside the supported range.",
                nameof(request));
        }
        if (request.BwToningShadowHue is { } shadowHue &&
                !double.IsFinite(shadowHue) ||
            request.BwToningHighlightHue is { } highlightHue &&
                !double.IsFinite(highlightHue) ||
            !double.IsFinite(request.BwToningStrength) ||
            request.BwToningStrength is < 0.0 or > 1.0 ||
            !double.IsFinite(request.ImageTransform.StraightenAngle) ||
            request.ImageTransform.StraightenAngle is < -45.0 or > 45.0)
        {
            throw new ArgumentException(
                "B&W toning or straighten controls are outside the supported finite range.",
                nameof(request));
        }
        if (request.ImageTransform.Crop is { } crop &&
            (!double.IsFinite(crop.X) || !double.IsFinite(crop.Y) ||
             !double.IsFinite(crop.Width) || !double.IsFinite(crop.Height) ||
             crop.X < 0.0 || crop.Y < 0.0 || crop.Width <= 0.0 || crop.Height <= 0.0 ||
             crop.X + crop.Width > 1.0 || crop.Y + crop.Height > 1.0))
        {
            throw new ArgumentException(
                "The normalized image crop is invalid.",
                nameof(request));
        }
    }
}
