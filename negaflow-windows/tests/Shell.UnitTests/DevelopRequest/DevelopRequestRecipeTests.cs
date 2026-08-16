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

internal static class DevelopRequestRecipeTests
{
    public static void Run()
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
    }
}
