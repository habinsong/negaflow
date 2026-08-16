using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopRequestFactoryTests
{
    public static void Run()
    {
        VerifyDevelopRequestFactory();
    }

    private static void VerifyDevelopRequestFactory()
    {
        const string destination = @"C:\exports\IMG_0001.png";

        DevelopRequestResult result = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)),
            destination);
        Check(result.IsSuccess, "develop_request_success");
        if (result.Request is not { } request)
        {
            return;
        }

        Check(request.SourcePath == @"C:\scans\IMG_0001.tif", "develop_request_source");
        Check(request.DestinationPath == destination, "develop_request_destination");
        Check(request.Format == DevelopExportFormat.Png16, "develop_request_default_format");
        Check(request.FilmType == NegativeFilmType.Color, "develop_request_film_type");
        Check(request.DminRed == 0.21f, "develop_request_dmin_red");
        Check(request.DminGreen == 0.22f, "develop_request_dmin_green");
        Check(request.DminBlue == 0.23f, "develop_request_dmin_blue");
        Check(request.ExposureStops == 1.5f, "develop_request_exposure");
        Check(request.Contrast == -0.25f, "develop_request_contrast");
        Check(request.Density == 0.5f, "develop_request_density");
        Check(request.Highlight == -0.6f, "develop_request_highlight");
        Check(request.Shadow == 0.7f, "develop_request_shadow");
        Check(request.Whites == -0.8f, "develop_request_whites");
        Check(request.Blacks == 0.9f, "develop_request_blacks");
        Check(request.Highlights == 0.1f, "develop_request_highlights");
        Check(request.Lights == 0.2f, "develop_request_lights");
        Check(request.Darks == 0.3f, "develop_request_darks");
        Check(request.Shadows == 0.4f, "develop_request_shadows");
        Check(
            request.FilmEmulation == FilmEmulationProfile.Portra400,
            "develop_request_emulation");
        Check(
            request.FilmEmulationIntensity == 0.75,
            "develop_request_emulation_intensity");
        Check(
            request.FilmLookSourceKind == DevelopSourceKind.FilmScan,
            "develop_request_source_kind");
        Check(
            request.BaseEstimationMode == DevelopBaseEstimationMode.Manual,
            "develop_request_manual_base_mode");

        ImageTransformRecipe imageTransform = new(
            ImageRotation.Degrees180,
            true,
            false,
            new ImageCropRect(0.2, 0.15, 0.6, 0.7),
            -1.25,
            3.0 / 2.0);
        DevelopRequestResult transformRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                ImageTransform = imageTransform,
            },
            destination);
        Check(
            transformRequest.IsSuccess &&
                transformRequest.Request?.ImageTransform.Rotation == DevelopImageRotation.Degrees180 &&
                transformRequest.Request.ImageTransform.FlipHorizontal &&
                !transformRequest.Request.ImageTransform.FlipVertical &&
                transformRequest.Request.ImageTransform.Crop == new DevelopCropRect(0.2, 0.15, 0.6, 0.7) &&
                transformRequest.Request.ImageTransform.StraightenAngle == -1.25,
            "develop_request_carries_image_transform");

        TextureRecipe texture = new(0.4, 0.5, 0.3, -0.2, 0.25);
        NoiseReductionRecipe noiseReduction = new(0.6, 0.7, 0.4, 0.5, 0.8, 0.3);
        DevelopRequestResult postProcessingRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                Texture = texture,
                NoiseReduction = noiseReduction,
            },
            destination);
        Check(
            postProcessingRequest.IsSuccess &&
                postProcessingRequest.Request?.Grain == 0.4f &&
                postProcessingRequest.Request.Sharpness == 0.5f &&
                postProcessingRequest.Request.Halation == 0.3f &&
                postProcessingRequest.Request.Clarity == -0.2f &&
                postProcessingRequest.Request.Vignette == 0.25f &&
                postProcessingRequest.Request.NoiseReductionStrength == 0.6f &&
                postProcessingRequest.Request.NoiseReductionLuma == 0.7f &&
                postProcessingRequest.Request.NoiseReductionChroma == 0.4f &&
                postProcessingRequest.Request.NoiseReductionDarkTone == 0.5f &&
                postProcessingRequest.Request.NoiseReductionDetail == 0.8f &&
                postProcessingRequest.Request.NoiseReductionGrainProtect == 0.3f &&
                postProcessingRequest.Request.NoiseReductionFilmProfile ==
                    FilmScanDenoiseFilmProfile.ColorNegative,
            "develop_request_carries_texture_and_noise_reduction");
        Check(
            DevelopRequestFactory.Create(
                Frame(
                    null,
                    signal: SourceSignalKind.FilmPositiveScan,
                    filmType: FilmType.BlackAndWhitePositive) with
                {
                    NoiseReduction = noiseReduction,
                },
                destination).Request?.NoiseReductionFilmProfile ==
                    FilmScanDenoiseFilmProfile.BlackAndWhitePositive,
            "develop_request_derives_noise_profile_from_film_type");

        PrimaryCalibrationRecipe calibration = new(0.25, -0.15, 0.10, 0.20, -0.30, 0.35);
        DevelopRequestResult calibrationRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                PrimaryCalibration = calibration,
            },
            destination);
        Check(
            calibrationRequest.IsSuccess &&
                calibrationRequest.Request?.PrimaryCalibration.RedHue == 0.25f &&
                calibrationRequest.Request.PrimaryCalibration.RedSaturation == -0.15f &&
                calibrationRequest.Request.PrimaryCalibration.GreenHue == 0.10f &&
                calibrationRequest.Request.PrimaryCalibration.GreenSaturation == 0.20f &&
                calibrationRequest.Request.PrimaryCalibration.BlueHue == -0.30f &&
                calibrationRequest.Request.PrimaryCalibration.BlueSaturation == 0.35f,
            "develop_request_carries_primary_calibration");

        PointCurveRecipe pointCurves = new(
            [new PointCurvePoint(0.0, 0.0), new PointCurvePoint(0.5, 0.6), new PointCurvePoint(1.0, 1.0)],
            [new PointCurvePoint(0.25, 0.3)],
            [],
            []);
        DevelopRequestResult curveRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23), pointCurves: pointCurves),
            destination);
        Check(
            curveRequest.IsSuccess &&
                curveRequest.Request?.PointCurves.Rgb[1] == new DevelopPointCurvePoint(0.5, 0.6) &&
                curveRequest.Request?.PointCurves.Red[0] == new DevelopPointCurvePoint(0.25, 0.3),
            "develop_request_carries_point_curves");

        ColorMixerRecipe colorMixer = new(
            [0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, -0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.75, 0.0, 0.0, 0.0, 0.0, 0.0]);
        DevelopRequestResult mixerRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with { ColorMixer = colorMixer },
            destination);
        Check(
            mixerRequest.IsSuccess && mixerRequest.Request?.ColorMixer.Hue[0] == 0.25f &&
                mixerRequest.Request.ColorMixer.Saturation[1] == -0.5f &&
                mixerRequest.Request.ColorMixer.Luminance[2] == 0.75f,
            "develop_request_carries_color_mixer");

        ColorGradingRecipe colorGrading = new(
            new ColorGradeRegionRecipe(30.0, 0.25, -0.1),
            new ColorGradeRegionRecipe(120.0, 0.50, 0.2),
            new ColorGradeRegionRecipe(240.0, 0.75, 0.1),
            0.4,
            -0.2);
        DevelopRequestResult gradingRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with { ColorGrading = colorGrading },
            destination);
        Check(
            gradingRequest.IsSuccess && gradingRequest.Request?.ColorGrading.Midtones.Hue == 120.0f &&
                gradingRequest.Request.ColorGrading.Highlights.Saturation == 0.75f &&
                gradingRequest.Request.ColorGrading.Balance == -0.2f,
            "develop_request_carries_color_grading");

        LocalDodgeBurnAdjustment localAdjustment = new(
            Guid.Parse("00000000-0000-0000-0000-000000000201"),
            LocalDodgeBurnMode.Burn,
            0.65,
            false,
            LocalDodgeBurnMask.Polygon(
                [new(-0.1, 0.2), new(0.8, 0.1), new(0.5, 1.1)],
                0.15));
        DevelopRequestResult localRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                LocalDodgeBurn = [localAdjustment],
            },
            destination);
        Check(
            localRequest.IsSuccess && localRequest.Request?.LocalDodgeBurn.Count == 1 &&
                localRequest.Request.LocalDodgeBurn[0].Mode == DevelopLocalDodgeBurnMode.Burn &&
                !localRequest.Request.LocalDodgeBurn[0].IsEnabled &&
                localRequest.Request.LocalDodgeBurn[0].Mask.Kind == DevelopLocalDodgeBurnMaskKind.Polygon &&
                localRequest.Request.LocalDodgeBurn[0].Mask.Points[2] ==
                    new DevelopLocalDodgeBurnPoint(0.5, 1.1),
            "develop_request_carries_local_dodge_burn");

        ColorModelRecipe colorModel = new(
            0.25, -0.2, 0.3, 0.4, -0.1, 0.1, -0.15, 0.2);
        DevelopRequestResult colorModelRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                ColorModel = colorModel,
                AutoLevels = true,
                AutoNeutralBalance = true,
                DevelopTarget = DevelopTarget.Rescue,
            },
            destination);
        Check(
            colorModelRequest.IsSuccess && colorModelRequest.Request?.Warmth == 0.25F &&
                colorModelRequest.Request.Tint == -0.2F &&
                colorModelRequest.Request.Vibrance == 0.4F &&
                colorModelRequest.Request.GreenPrimary == -0.15F &&
                colorModelRequest.Request.AutoLevels &&
                colorModelRequest.Request.AutoNeutralBalance &&
                colorModelRequest.Request.DevelopTarget == DevelopTargetMode.Rescue,
            "develop_request_carries_color_model_scene_correction_and_target");

        Guid defectFrameId = Guid.Parse("92e43a49-e80a-4d33-af27-1d5b1fe947e3");
        byte[] defectMask = Enumerable.Range(0, 16)
            .Select(value => (byte)value)
            .ToArray();
        DefectEditItem regionEdit = new(
            Guid.Parse("ff9a1c0e-03b1-427f-a19a-c13679147037"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.6,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(100, 80),
            [])
        {
            RegionMask = new DefectMask(false, defectMask),
            RegionRoi = new DefectRect(12, 34, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRecipeSnapshot defectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 3,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit]);
        DevelopRequestResult defectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = defectRecipe,
            },
            destination);
        Check(defectRequest.IsSuccess &&
              defectRequest.Request?.DefectRegions.Count == 1 &&
              defectRequest.Request.DefectRegions[0].RoiX == 12 &&
              defectRequest.Request.DefectRegions[0].RoiY == 34 &&
              defectRequest.Request.DefectRegions[0].MaskStrideBytes == 8 &&
              defectRequest.Request.DefectRegions[0].Strength == 0.6 &&
              defectRequest.Request.DefectRegions[0].Mask.Span.SequenceEqual(defectMask) &&
              defectRequest.Request.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
              ]) &&
              defectRequest.Request.DefectSourceIdentity ==
                  new DevelopDefectSourceIdentity(123, new string('d', 64)),
            "develop_request_projects_persisted_region_defect");

        byte[] infraredCoreRgba = new byte[4 * 4 * 4];
        infraredCoreRgba[5 * 4] = 255;
        infraredCoreRgba[6 * 4] = 128;
        byte[] infraredAttenuation = new byte[4 * 4 * 2];
        infraredAttenuation[2 * 5] = 0x00;
        infraredAttenuation[2 * 5 + 1] = 0x80;
        DefectEditItem infraredEdit = new(
            Guid.Parse("f56375c4-43f8-48ba-8daf-f2ae95d06d97"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 0.8,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown([], 0.9)),
            new DefectSize(100, 80),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(24, 30, 4, 4),
                    new DefectMask(false, infraredCoreRgba),
                    4,
                    4,
                    new DefectMask(false, infraredAttenuation)),
            ],
        };

        DefectEditItem cloneEdit = new(
            Guid.Parse("4a72f873-a8b3-44fc-a427-e57e85d7bb01"),
            DefectEditKind.Clone,
            Enabled: true,
            Strength: 0.7,
            new DefectEditLabel(DefectEditLabelKind.Clone, 12),
            new DefectEditSummary(DefectEditSummaryKind.Clone),
            new DefectSize(100, 80),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.4, 0.5), new DefectPoint(0.45, 0.55)],
                    -0.1,
                    0.2,
                    12,
                    0.8),
            ],
        };
        DefectEditItem secondRegionEdit = regionEdit with
        {
            Id = Guid.Parse("60db3ee5-c25e-4182-840b-8a7196190d61"),
            RegionRoi = new DefectRect(20, 30, 2, 2),
        };
        DefectRecipeSnapshot orderedDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, infraredEdit, cloneEdit, secondRegionEdit]);
        DevelopRequestResult orderedDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = orderedDefectRecipe,
            },
            destination);
        Check(
            orderedDefectRequest.IsSuccess &&
            orderedDefectRequest.Request?.DefectRegions.Count == 2 &&
            orderedDefectRequest.Request.DefectInfrared.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0].RoiX == 24 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMaskStrideBytes == 4 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[5] == 255 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[6] == 128 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationStrideBytes == 8 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationR16?.Span[
                2 * 5 + 1] == 0x80 &&
            orderedDefectRequest.Request.DefectClones.Count == 1 &&
            orderedDefectRequest.Request.DefectClones[0].Strength == 0.7 &&
            orderedDefectRequest.Request.DefectClones[0].Strokes[0].OffsetX == -0.1 &&
            orderedDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Clone, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 1),
            ]),
            "develop_request_preserves_interleaved_region_infrared_clone_order");

        DefectEditItem legacyInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with { AttenuationR16 = null },
            ],
        };
        DefectRecipeSnapshot legacyInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [legacyInfraredEdit]);
        Check(legacyInfraredRecipe.Items[0].Clusters![0].AttenuationR16 is null,
            "defect_recipe_keeps_legacy_attenuation_absent");
        DevelopRequestResult legacyInfraredRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = legacyInfraredRecipe,
            },
            destination);
        Check(legacyInfraredRequest.IsSuccess,
            "develop_request_accepts_legacy_mask_only_infrared");
        Check(legacyInfraredRequest.Request?.DefectInfrared.Count == 1,
            "develop_request_keeps_legacy_infrared_separate");
        Check(legacyInfraredRequest.Request is { } legacyNativeRequest &&
              legacyNativeRequest.DefectInfrared[0].Clusters[0]
                  .AttenuationR16 is null,
            "develop_request_preserves_missing_legacy_attenuation");
        Check(legacyInfraredRequest.Request?.DefectInfrared[0].Clusters[0]
                  .AttenuationStrideBytes == 0,
            "develop_request_zeros_missing_legacy_attenuation_stride");
        Check(legacyInfraredRequest.Request?.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
              ]) == true,
            "develop_request_orders_legacy_infrared_separately");

        DefectEditItem corruptInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(true, [1, 2, 3]),
                },
            ],
        };
        DefectRecipeSnapshot corruptInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [corruptInfraredEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = corruptInfraredRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_corrupt_infrared_attenuation");

        DefectRecipeSnapshot unboundRegionRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            sourceIdentity: null,
            [regionEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = unboundRegionRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_unbound_region_defect_recipe");

        DefectEditItem brushEdit = new(
            Guid.Parse("43309589-b878-48d5-969e-52d00683a2f4"),
            DefectEditKind.Brush,
            Enabled: true,
            Strength: 1,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush),
            new DefectSize(100, 80),
            [])
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(0.2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot brushDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, brushEdit]);
        DevelopRequestResult brushDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = brushDefectRecipe,
            },
            destination);
        Check(
            brushDefectRequest.IsSuccess &&
            brushDefectRequest.Request?.DefectBrushes.Count == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strength == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Thickness == 0.01 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Points.SequenceEqual(
            [
                new DevelopDefectBrushPoint(0.2, 0.3),
            ]) &&
            brushDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
            ]) &&
            brushDefectRequest.Request.DefectSourceIdentity ==
                new DevelopDefectSourceIdentity(123, new string('d', 64)),
            "develop_request_projects_brush_and_preserves_order");

        DefectEditItem invalidBrushEdit = brushEdit with
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot invalidBrushRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [invalidBrushEdit]);
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = invalidBrushRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_out_of_range_brush_geometry");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), filmType: FilmType.BlackAndWhiteNegative),
                destination).Request?.FilmType == NegativeFilmType.BlackAndWhite,
            "develop_request_bw_film_type");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), emulation: FilmEmulation.None),
                destination).Request?.FilmEmulation == FilmEmulationProfile.None,
            "develop_request_no_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    filmType: FilmType.BlackAndWhiteNegative,
                    emulation: FilmEmulation.TriX400),
                destination).Request?.FilmEmulation == FilmEmulationProfile.TriX400,
            "develop_request_bw_emulation");

        Check(
            DevelopRequestFactory.Create(
                Frame(
                    null,
                    signal: SourceSignalKind.RenderedDigital,
                    filmType: FilmType.ColorPositive,
                    emulation: FilmEmulation.Vision3_500T),
                destination).Request?.FilmEmulation == FilmEmulationProfile.Vision3_500T,
            "develop_request_motion_picture_emulation");

        DevelopRequestResult auto = DevelopRequestFactory.Create(Frame(null), destination);
        Check(auto.IsSuccess, "develop_request_auto_without_manual_base_succeeds");
        Check(
            auto.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto,
            "develop_request_auto_mode");

        // Auto에는 이전 manual value가 남아 있을 수 있지만 resolver가 그것을 재사용하면 안 됩니다.
        DevelopRequestResult autoWithStaleManual = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: BaseRecipe.Auto),
            destination);
        Check(
            autoWithStaleManual.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Auto &&
                autoWithStaleManual.Request?.DminRed == 0.0F,
            "develop_request_auto_ignores_stale_manual_base");

        DevelopRequestResult noBase = DevelopRequestFactory.Create(
            Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            destination);
        Check(!noBase.IsSuccess, "develop_request_missing_base_refused");
        Check(
            noBase.Refusal == DevelopRequestRefusal.MissingManualBase,
            "develop_request_missing_base_reason");
        Check(noBase.Request is null, "develop_request_no_partial_request");

        DevelopRequestResult preset = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(
                    BaseEstimationMode.Preset,
                    "kodak-portra-400",
                    "warm-led",
                    "noritsu__color-nega__kodak-portra-400")),
            destination);
        Check(
            preset.IsSuccess &&
                preset.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Preset &&
                preset.Request?.FilmStockDminId == "kodak-portra-400" &&
                preset.Request?.LightSourceProfileId == "warm-led" &&
                preset.Request?.ScannerProfileId ==
                    "noritsu__color-nega__kodak-portra-400",
            "develop_request_carries_film_and_scanner_profile_identifiers");
        Check(
            DevelopRequestFactory.Create(
                Frame(
                    new ManualBaseRgb(0.2, 0.2, 0.2),
                    baseRecipe: new BaseRecipe(BaseEstimationMode.Preset, null, null, null)),
                destination).Refusal == DevelopRequestRefusal.MissingFilmStock,
            "develop_request_preset_requires_film_stock");

        DevelopRequestResult digital = DevelopRequestFactory.Create(
            Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive),
            destination);
        Check(
            digital.IsSuccess &&
                digital.Request?.FilmLookSourceKind == DevelopSourceKind.RenderedDigital &&
                digital.Request?.FilmType == NegativeFilmType.Color &&
                digital.Request?.FilmPolarity == FilmPolarity.Positive &&
                digital.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual &&
                digital.Request?.DminRed == 0.0F,
            "develop_request_digital_bypasses_negative_base");

        DevelopRequestResult positiveFilm = DevelopRequestFactory.Create(
            Frame(null, SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive),
            destination);
        Check(
            positiveFilm.IsSuccess &&
                positiveFilm.Request?.FilmLookSourceKind == DevelopSourceKind.FilmScan &&
                positiveFilm.Request?.FilmPolarity == FilmPolarity.Positive &&
                positiveFilm.Request?.BaseEstimationMode == DevelopBaseEstimationMode.Manual,
            "develop_request_positive_film_bypasses_negative_base");

        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "IMG_0001.png").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_relative_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                "  ").Refusal == DevelopRequestRefusal.InvalidDestination,
            "develop_request_blank_destination_refused");
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2)),
                destination,
                (DevelopExportFormat)99).Refusal ==
                DevelopRequestRefusal.UnknownOutputFormat,
            "develop_request_unknown_format_refused");
    }

}
