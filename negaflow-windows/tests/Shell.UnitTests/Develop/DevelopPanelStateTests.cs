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

internal static class DevelopPanelStateTests
{
    public static void Run()
    {
        VerifyDevelopPanelState();
    }

    private static void VerifyDevelopPanelState()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "develop-panel-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        NegativeLimits negativeLimits = new(MinimumManualDmin: 0.001f, MaximumManualDmin: 1.0f);
        ToneLimits limits = new(
            MaximumExposureStops: 5.0f,
            MaximumToneControl: 1.0f,
            MaximumEndpointToneControl: 2.0f,
            MinimumFilmEmulationIntensity: 0.0,
            MaximumFilmEmulationIntensity: 1.0);

        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                JsonObject autoWithoutManualBase = FrameRecord("frame-2", "IMG_0002.tif", 0.0);
                autoWithoutManualBase["params"]!.AsObject().Remove("manualBaseRGB");
                JsonObject positiveFrame = FrameRecord("frame-3", "IMG_0003.tif", 0.0);
                positiveFrame["sourceSignalKind"] = "filmPositiveScan";
                positiveFrame["filmType"] = "colorPositive";
                positiveFrame["params"]!.AsObject()["filmType"] = "colorPositive";
                // 필름 룩은 digital source 에서만 걸리므로 그 경로도 하나 둡니다.
                JsonObject digitalFrame = FrameRecord("frame-4", "IMG_0004.tif", 0.0);
                digitalFrame["sourceSignalKind"] = "renderedDigital";
                digitalFrame["filmType"] = "colorPositive";
                digitalFrame["params"]!.AsObject()["filmType"] = "colorPositive";
                digitalFrame["params"]!.AsObject()["isDigitalSource"] = true;
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", autoWithoutManualBase),
                            new("frame-3", positiveFrame),
                            new("frame-4", digitalFrame),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);

            DevelopPanelState panel = new(host, limits, negativeLimits);
            int selectedFrameRefreshCount = 0;
            panel.SelectedFrameChanged += _ => ++selectedFrameRefreshCount;
            Check(panel.SelectedFrame is null, "panel_starts_with_no_selection");
            Check(!panel.CanExport, "panel_cannot_export_without_selection");
            Check(!panel.Select("missing"), "panel_select_unknown_id");

            Check(panel.Select("frame-1") && selectedFrameRefreshCount == 1, "panel_select");
            Check(panel.Select("frame-1") && selectedFrameRefreshCount == 2,
                "panel_notifies_same_frame_snapshot_refresh");
            Check(panel.CanExport, "panel_can_export_after_select");
            Check(panel.LastAppliedBase is null, "panel_has_no_applied_base_until_preview");
            panel.RememberAppliedBase(0.72F, 0.54F, 0.34F);
            ManualBaseRgb expectedApplied = new(0.72F, 0.54F, 0.34F);
            Check(
                panel.LastAppliedBase == expectedApplied,
                "panel_remembers_applied_base_from_preview");
            Check(
                DevelopBaseReadout.Format("base %.2f %.2f %.2f", expectedApplied) ==
                    "base 0.72 0.54 0.34",
                "panel_base_readout_uses_macos_fixed2_format");
            Check(panel.Select("frame-2") && panel.LastAppliedBase is null,
                "panel_clears_applied_base_when_the_frame_has_none");
            Check(
                panel.Select("frame-1") && panel.LastAppliedBase == expectedApplied,
                "panel_restores_applied_base_from_catalog");
            Check(panel.Tone.MaximumExposureStops == 5.0, "panel_exposure_range_from_engine");

            Check(
                panel.Tone.SetExposure(1.25) == LibraryFrameError.None,
                "panel_set_exposure");
            Check(panel.Tone.Exposure == 1.25, "panel_exposure_visible_immediately");

            // 범위를 넘는 값은 엔진이 거부할 값이므로 여기서 묶습니다.
            Check(panel.Tone.SetExposure(99.0) == LibraryFrameError.None, "panel_set_high_exposure");
            Check(panel.Tone.Exposure == 5.0, "panel_clamps_high_exposure");
            Check(panel.Tone.SetExposure(-99.0) == LibraryFrameError.None, "panel_set_low_exposure");
            Check(panel.Tone.Exposure == -5.0, "panel_clamps_low_exposure");

            // 현상 버전: 담고 → 바꾸고 → 되돌리면 recipe 가 담을 때 값으로 돌아와야 합니다.
            // 이게 어긋나면 사용자가 되돌렸다고 믿은 상태가 실제와 다릅니다.
            Check(panel.Tone.SetExposure(0.75) == LibraryFrameError.None && panel.Versions.Count == 0,
                "panel_starts_with_no_versions");
            Check(
                panel.CaptureVersion("before") == LibraryFrameError.None &&
                panel.Versions.Count == 1 &&
                panel.Versions[0].Name == "before" &&
                panel.Tone.Exposure == 0.75,
                "panel_capture_version_keeps_current_recipe");

            string capturedId = panel.Versions[0].Id;
            Check(
                panel.Tone.SetExposure(-2.0) == LibraryFrameError.None && panel.Tone.Exposure == -2.0,
                "panel_edits_after_capturing");
            Check(
                panel.RestoreVersion(capturedId) == LibraryFrameError.None &&
                panel.Tone.Exposure == 0.75 &&
                panel.Versions.Count == 1,
                "panel_restore_version_brings_the_recipe_back");
            Check(
                panel.RestoreVersion("missing") == LibraryFrameError.MissingVersion,
                "panel_restore_unknown_version_is_refused");
            Check(
                panel.CaptureVersion("   ") == LibraryFrameError.InvalidVersion &&
                panel.Versions.Count == 1,
                "panel_refuses_a_blank_version_name");
            Check(
                panel.DeleteVersion(capturedId) == LibraryFrameError.None &&
                panel.Versions.Count == 0 &&
                panel.Tone.Exposure == 0.75,
                "panel_delete_version_leaves_the_recipe_alone");
            _ = panel.Tone.SetExposure(0.0);

            Check(panel.SetAppMetadata(metadata => metadata with { Title = "  Archive title  " }) ==
                    LibraryFrameError.None &&
                panel.SelectedFrame?.AppMetadata?.Title == "Archive title" &&
                panel.SelectedFrame.AppMetadata.Revision == 1UL,
                "panel_metadata_normalizes_and_refreshes_the_frame");
            Check(panel.SetAppMetadata(metadata => metadata with { Caption = "Caption" }) ==
                    LibraryFrameError.None &&
                panel.SelectedFrame?.AppMetadata?.Revision == 2UL,
                "panel_metadata_increments_revision");

            Check(panel.CopyDevelopSettings() &&
                panel.CopiedSettings?.Id == "frame-1" &&
                panel.CopiedSettingsSourceName == "IMG_0001.tif",
                "panel_copies_develop_settings_with_source_name");
            panel.PasteScope = new DevelopSettingsPasteScope(
                Base: false,
                Tone: true,
                Color: false,
                Detail: false,
                Geometry: false);
            Check(panel.Select("frame-2") &&
                panel.Tone.SetExposure(-1.0) == LibraryFrameError.None &&
                panel.PasteDevelopSettings() == LibraryFrameError.None &&
                panel.Tone.Exposure == 0.0,
                "panel_pastes_the_selected_settings_scope");
            Check(panel.Select("frame-1"), "panel_reselects_source_after_paste");

            string userPresetPath = Path.Combine(isolatedBase, "user-presets.json");
            panel.OpenUserPresets(userPresetPath);
            DevelopUserPreset? savedPreset = panel.SaveUserPreset("Archive preset");
            Guid savedPresetId = savedPreset?.Id ?? Guid.Empty;
            Check(savedPreset is not null && panel.UserPresets.Count == 1 &&
                File.Exists(userPresetPath),
                "panel_saves_user_preset_through_the_controller");
            Check(panel.Tone.SetExposure(1.0) == LibraryFrameError.None &&
                panel.ApplyUserPreset(savedPresetId) == LibraryFrameError.None &&
                panel.Tone.Exposure == 0.0,
                "panel_applies_user_preset_and_refreshes_the_frame");
            Check(panel.DeleteUserPreset(savedPresetId) && panel.UserPresets.Count == 0,
                "panel_deletes_user_preset");

            // 자동 보정 두 축은 음화에서만 열립니다. 양화에서도 켜지면 macOS 가 내지 않는
            // 단계가 걸려 결과가 갈립니다.
            Check(panel.ShowsAutoCorrections, "panel_negative_shows_auto_corrections");
            Check(
                panel.SetAutoLevels(true) == LibraryFrameError.None && panel.AutoLevels,
                "panel_set_auto_levels");
            Check(
                panel.SetAutoNeutralBalance(true) == LibraryFrameError.None &&
                panel.AutoNeutralBalance && panel.AutoLevels,
                "panel_auto_corrections_are_independent");
            Check(
                panel.SetAutoLevels(false) == LibraryFrameError.None &&
                !panel.AutoLevels && panel.AutoNeutralBalance,
                "panel_clear_auto_levels_keeps_auto_colour");

            Check(panel.Tone.MaximumToneControl == 1.0, "panel_basic_tone_range_from_engine");
            Check(panel.Tone.SetContrast(-0.25) == LibraryFrameError.None && panel.Tone.Contrast == -0.25,
                "panel_set_contrast");
            Check(panel.Tone.SetHighlights(0.5) == LibraryFrameError.None && panel.Tone.Highlights == 0.5,
                "panel_set_highlights");
            Check(panel.Tone.SetShadows(-0.5) == LibraryFrameError.None && panel.Tone.Shadows == -0.5,
                "panel_set_shadows");
            Check(panel.Tone.SetWhites(0.75) == LibraryFrameError.None && panel.Tone.Whites == 0.75,
                "panel_set_whites");
            Check(panel.Tone.SetBlacks(-0.75) == LibraryFrameError.None && panel.Tone.Blacks == -0.75,
                "panel_set_blacks");
            Check(panel.Tone.SetDensity(99.0) == LibraryFrameError.None && panel.Tone.Density == 1.0,
                "panel_clamps_density");
            Check(panel.Tone.SetCurveHighlights(-0.25) == LibraryFrameError.None &&
                panel.Tone.CurveHighlights == -0.25, "panel_set_curve_highlights");
            Check(panel.Tone.SetCurveLights(0.5) == LibraryFrameError.None &&
                panel.Tone.CurveLights == 0.5, "panel_set_curve_lights");
            Check(panel.Tone.SetCurveDarks(-0.5) == LibraryFrameError.None &&
                panel.Tone.CurveDarks == -0.5, "panel_set_curve_darks");
            Check(panel.Tone.SetCurveShadows(99.0) == LibraryFrameError.None &&
                panel.Tone.CurveShadows == 1.0, "panel_clamps_curve_shadows");
            PointCurveRecipe editedPointCurves = new(
                [new PointCurvePoint(0.0, 0.0), new PointCurvePoint(0.5, 0.6), new PointCurvePoint(1.0, 1.0)],
                [], [], []);
            Check(panel.Color.SetPointCurves(editedPointCurves) == LibraryFrameError.None &&
                panel.Color.PointCurves.Rgb[1] == new PointCurvePoint(0.5, 0.6),
                "panel_sets_point_curves");
            Check(
                panel.Color.SetPointCurves(new PointCurveRecipe(
                    [new PointCurvePoint(0.5, 0.4), new PointCurvePoint(0.5, 0.6)],
                    [], [], [])) == LibraryFrameError.InvalidPointCurves,
                "panel_rejects_invalid_point_curves");
            ColorMixerRecipe editedColorMixer = new(
                [0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                new double[ColorMixerRecipe.BandCount],
                new double[ColorMixerRecipe.BandCount]);
            Check(panel.Color.SetColorMixer(editedColorMixer) == LibraryFrameError.None &&
                panel.Color.ColorMixer.Hue[0] == 0.2,
                "panel_sets_color_mixer");
            Check(panel.Color.SetColorMixer(new ColorMixerRecipe(
                    new double[ColorMixerRecipe.BandCount],
                    [0.0, 0.0],
                    new double[ColorMixerRecipe.BandCount])) == LibraryFrameError.InvalidColorMixer,
                "panel_rejects_invalid_color_mixer");
            ColorGradingRecipe editedColorGrading = new(
                new ColorGradeRegionRecipe(0.2, 0.3, -0.1),
                new ColorGradeRegionRecipe(0.4, 0.5, 0.1),
                new ColorGradeRegionRecipe(0.6, 0.7, 0.2),
                0.25,
                -0.2);
            Check(panel.Color.SetColorGrading(editedColorGrading) == LibraryFrameError.None &&
                panel.Color.ColorGrading == editedColorGrading,
                "panel_sets_color_grading");
            PrimaryCalibrationRecipe editedCalibration = new(0.2, -0.3, 0.4, -0.5, 0.6, -0.7);
            Check(panel.Color.SetPrimaryCalibration(editedCalibration) == LibraryFrameError.None &&
                panel.Color.PrimaryCalibration == editedCalibration,
                "panel_sets_primary_calibration");
            TextureRecipe editedTexture = new(0.2, 0.3, 0.4, -0.5, 0.6);
            Check(panel.SetTexture(editedTexture) == LibraryFrameError.None &&
                panel.Texture == editedTexture,
                "panel_sets_texture");
            NoiseReductionRecipe editedNoiseReduction = new(0.8, 0.7, 0.6, 0.5, 0.4, 0.3);
            Check(panel.SetNoiseReduction(editedNoiseReduction) == LibraryFrameError.None &&
                panel.NoiseReduction == editedNoiseReduction,
                "panel_sets_noise_reduction");
            Check(panel.SetNoiseReductionEnabled(false) == LibraryFrameError.None &&
                panel.NoiseReduction.Strength == 0.0,
                "panel_disables_noise_reduction");
            Check(panel.SetNoiseReductionEnabled(true) == LibraryFrameError.None &&
                panel.NoiseReduction.Strength == 0.7,
                "panel_enables_noise_reduction_with_macos_default_strength");

            Check(panel.Tone.ResetBasicTone() == LibraryFrameError.None &&
                panel.Tone.Exposure == 0 && panel.Tone.Contrast == 0 && panel.Tone.Highlights == 0 &&
                panel.Tone.Shadows == 0 && panel.Tone.Whites == 0 && panel.Tone.Blacks == 0 &&
                panel.Tone.Density == 0,
                "panel_resets_basic_tone");
            Check(panel.Tone.CurveHighlights == -0.25 && panel.Tone.CurveLights == 0.5 &&
                panel.Tone.CurveDarks == -0.5 && panel.Tone.CurveShadows == 1.0,
                "panel_basic_tone_reset_preserves_tone_curve");
            Check(panel.Tone.ResetToneCurve() == LibraryFrameError.None &&
                panel.Tone.CurveHighlights == 0 && panel.Tone.CurveLights == 0 &&
                panel.Tone.CurveDarks == 0 && panel.Tone.CurveShadows == 0 &&
                panel.Color.PointCurves.Rgb.Count == 0,
                "panel_resets_tone_curve_and_points");
            Check(panel.Color.ResetColorMixer() == LibraryFrameError.None &&
                panel.Color.ColorMixer.Hue.All(value => value == 0) &&
                panel.Color.ColorMixer.Saturation.All(value => value == 0) &&
                panel.Color.ColorMixer.Luminance.All(value => value == 0),
                "panel_resets_color_mixer");
            Check(panel.Color.ResetColorGrading() == LibraryFrameError.None &&
                panel.Color.ColorGrading == ColorGradingRecipe.Identity,
                "panel_resets_color_grading");
            Check(panel.Color.ResetPrimaryCalibration() == LibraryFrameError.None &&
                panel.Color.PrimaryCalibration == PrimaryCalibrationRecipe.Identity,
                "panel_resets_primary_calibration");
            Check(panel.ResetDetailAndEffects() == LibraryFrameError.None &&
                panel.Texture == TextureRecipe.Identity &&
                panel.NoiseReduction == NoiseReductionRecipe.Identity,
                "panel_resets_detail_and_effects");
            Check(panel.Rotate(clockwise: true) == LibraryFrameError.None &&
                panel.ImageTransform.Rotation == ImageRotation.Degrees90,
                "panel_rotates_image_transform");
            Check(panel.Rotate(clockwise: false) == LibraryFrameError.None &&
                panel.ImageTransform.Rotation == ImageRotation.Degrees0,
                "panel_rotates_image_transform_backwards");
            Check(panel.FlipHorizontally() == LibraryFrameError.None &&
                panel.FlipVertically() == LibraryFrameError.None &&
                panel.ImageTransform.FlipHorizontal && panel.ImageTransform.FlipVertical,
                "panel_flips_image_transform");
            Check(panel.SetStraightenAngle(99.0) == LibraryFrameError.None &&
                panel.ImageTransform.StraightenAngle == 45.0,
                "panel_clamps_straighten_angle");

            // 아직 base 를 고르지 않은 frame 에도 슬라이더 시작 위치는 있어야 하지만, 그것이
            // catalog 에 저장되면 사용자가 고르지 않은 값으로 현상됩니다.
            Check(
                panel.SuggestedManualDmin >= panel.MinimumManualDmin &&
                    panel.SuggestedManualDmin <= panel.MaximumManualDmin,
                "panel_suggested_base_in_range");

            Check(
                panel.SetBaseMode(BaseEstimationMode.Auto) == LibraryFrameError.None,
                "panel_selects_auto_base_mode");
            Check(
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto &&
                    panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_auto_preserves_existing_manual_base");
            Check(
                panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_selects_manual_base_mode");
            Check(
                panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_manual_mode_restores_existing_base");

            Check(panel.SetBaseMode(BaseEstimationMode.Preset) == LibraryFrameError.None,
                "panel_selects_film_base_mode");
            Check(panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Preset,
                "panel_film_base_mode_is_visible_immediately");
            Check(panel.SetFilmStock("kodak-portra-400") == LibraryFrameError.None,
                "panel_sets_known_film_stock");
            Check(panel.SelectedFrame?.Base.FilmStockDminId == "kodak-portra-400" &&
                panel.SelectedFrame.Base.Mode == BaseEstimationMode.Preset,
                "panel_film_stock_selects_preset_mode");
            Check(panel.SetLightSourceProfile("warm-led") == LibraryFrameError.None,
                "panel_sets_known_light_source");
            Check(panel.SelectedFrame?.Base.LightSourceProfileId == "warm-led",
                "panel_light_source_visible_immediately");
            Check(panel.SetFilmStock(null) == LibraryFrameError.None &&
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Auto,
                "panel_film_stock_none_returns_to_auto");
            Check(panel.SelectedFrame?.Base.LightSourceProfileId == "warm-led" &&
                panel.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23),
                "panel_auto_preserves_light_and_manual_base");
            Check(panel.SetLightSourceProfile("neutral") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_light_source_outside_film_mode");
            Check(panel.SetFilmStock("unknown-stock") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_unknown_film_stock");
            Check(panel.SetLightSourceProfile("unknown-light") == LibraryFrameError.InvalidBaseRecipe,
                "panel_rejects_unknown_light_source");

            Check(
                panel.SetManualBase(0.3, 0.31, 0.32) == LibraryFrameError.None,
                "panel_set_manual_base");
            Check(
                panel.ManualBase == new ManualBaseRgb(0.3, 0.31, 0.32),
                "panel_manual_base_visible_immediately");
            Check(
                panel.SelectedFrame?.Base.Mode == BaseEstimationMode.Manual,
                "panel_manual_base_selects_manual_mode");

            // 엔진은 범위를 벗어난 값을 거부하지 않고 조용히 clamp 합니다. 여기서 먼저 묶지
            // 않으면 저장된 값과 실제로 쓰인 값이 달라집니다.
            Check(
                panel.SetManualBase(9.0, -9.0, 0.5) == LibraryFrameError.None,
                "panel_set_out_of_range_base");
            Check(
                panel.ManualBase?.Red == panel.MaximumManualDmin,
                "panel_clamps_high_base");
            Check(
                panel.ManualBase?.Green == panel.MinimumManualDmin,
                "panel_clamps_low_base");
            Check(panel.ManualBase?.Blue == 0.5, "panel_leaves_valid_channel");
            Check(panel.SetBaseMode(BaseEstimationMode.Auto) == LibraryFrameError.None,
                "panel_returns_to_auto_base_mode");
            Check(panel.ManualBase == new ManualBaseRgb(panel.MaximumManualDmin, panel.MinimumManualDmin, 0.5),
                "panel_auto_preserves_manual_base");
            Check(panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_restores_manual_base_mode");
            Check(panel.ManualBase == new ManualBaseRgb(panel.MaximumManualDmin, panel.MinimumManualDmin, 0.5),
                "panel_manual_mode_restores_preserved_base");

            Check(panel.Select("frame-2"), "panel_selects_auto_frame_without_manual_base");
            Check(panel.ManualBase is null && panel.BaseMode == BaseEstimationMode.Auto,
                "panel_auto_frame_starts_without_manual_base");
            Check(panel.SetBaseMode(BaseEstimationMode.Manual) == LibraryFrameError.None,
                "panel_initializes_manual_mode_without_saved_base");
            Check(panel.ManualBase == new ManualBaseRgb(0.9, 0.65, 0.45),
                "panel_manual_mode_uses_mac_fallback_base");

            Check(panel.Select("frame-3"), "panel_selects_positive_frame");
            Check(!panel.CanEditBase, "panel_positive_frame_cannot_edit_base");
            // 필름 스캔 프레임은 macOS 가 필름 룩을 걸지 않는 자리입니다 — 기록도 하지 않습니다.
            Check(
                !panel.AppliesFilmLook &&
                panel.SetFilmEmulation(FilmEmulation.Portra400) == LibraryFrameError.InvalidDevelopRoute,
                "panel_refuses_film_look_on_a_scan_route");

            // digital source 에서는 룩과 세기가 catalog 를 왕복해야 합니다. 42종을 엔진이
            // 이미 갖고 있었는데 고를 길이 없던 자리입니다.
            // 프로세스를 바꾸면 route 가 통째로 옮겨가야 합니다. 가져오기가 C-41 로 고정돼
            // 있어 이 경로가 없으면 슬라이드·흑백·디지털에 영영 닿지 못합니다.
            Check(panel.Select("frame-1"), "panel_selects_scan_frame_for_process_change");
            Check(
                panel.DevelopmentProcess == DevelopmentProcess.C41 && !panel.AppliesFilmLook,
                "panel_reads_c41_from_a_negative_scan");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.DigitalColor) == LibraryFrameError.None &&
                panel.DevelopmentProcess == DevelopmentProcess.DigitalColor &&
                panel.AppliesFilmLook,
                "panel_switches_to_digital_colour");
            Check(
                panel.SetFilmEmulation(FilmEmulation.Ektar100) == LibraryFrameError.None &&
                panel.FilmEmulation == FilmEmulation.Ektar100,
                "panel_can_pick_a_film_after_switching_to_digital");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.D76) == LibraryFrameError.None &&
                panel.DevelopmentProcess == DevelopmentProcess.D76 &&
                !panel.AppliesFilmLook &&
                panel.FilmEmulation == FilmEmulation.Ektar100,
                "panel_keeps_the_film_choice_across_process_changes");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.C41) == LibraryFrameError.None,
                "panel_restores_c41");

            Check(panel.Select("frame-4"), "panel_selects_digital_frame");
            Check(panel.AppliesFilmLook, "panel_digital_frame_applies_film_look");
            Check(
                panel.SetFilmEmulation(FilmEmulation.Portra400) == LibraryFrameError.None &&
                panel.FilmEmulation == FilmEmulation.Portra400,
                "panel_sets_film_emulation");
            Check(
                panel.SetFilmEmulationIntensity(0.25) == LibraryFrameError.None &&
                panel.FilmEmulationIntensity == 0.25 &&
                panel.FilmEmulation == FilmEmulation.Portra400,
                "panel_sets_intensity_without_losing_the_film");
            Check(
                panel.SetFilmEmulationIntensity(9.0) == LibraryFrameError.None &&
                panel.FilmEmulationIntensity == 1.0,
                "panel_clamps_film_intensity");
            Check(
                FilmEmulationCatalog.Count == 42 &&
                FilmEmulationCatalog.DisplayName(FilmEmulation.Portra400) == "Kodak Portra 400" &&
                FilmEmulationCatalog.Films(FilmEmulationKind.MotionPicture).Count == 4,
                "film_emulation_catalog_covers_every_film");
            Check(
                !panel.ShowsAutoCorrections &&
                panel.SetAutoLevels(true) == LibraryFrameError.InvalidDevelopRoute &&
                panel.SetAutoNeutralBalance(true) == LibraryFrameError.InvalidDevelopRoute,
                "panel_rejects_auto_corrections_for_positive_frame");
            Check(panel.SetManualBase(0.3, 0.3, 0.3) == LibraryFrameError.InvalidDevelopRoute,
                "panel_rejects_manual_base_for_positive_frame");
            Check(panel.Tone.SetContrast(0.3) == LibraryFrameError.None,
                "panel_edits_tone_for_positive_frame");
            Check(panel.Tone.SetCurveHighlights(0.3) == LibraryFrameError.None,
                "panel_edits_curve_for_positive_frame");
            Check(panel.Color.SetPointCurves(PointCurveRecipe.Identity) == LibraryFrameError.None,
                "panel_edits_point_curve_for_positive_frame");
            Check(panel.Color.SetColorMixer(ColorMixerRecipe.Identity) == LibraryFrameError.None,
                "panel_edits_color_mixer_for_positive_frame");
            Check(panel.Select("frame-2"), "panel_reselects_developable_frame");

            Check(panel.Save() == CatalogStoreError.None, "panel_save");

            DevelopExportOutcome? outcome = null;
            Check(
                panel.ExportAsync(
                    @"C:\exports\IMG_0001.png",
                    DevelopExportFormat.Png16,
                    completed => outcome = completed).GetAwaiter().GetResult(),
                "panel_export_delivers");
            Check(
                outcome?.Kind == DevelopExportOutcomeKind.Completed,
                "panel_export_completed");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }

    }
}
