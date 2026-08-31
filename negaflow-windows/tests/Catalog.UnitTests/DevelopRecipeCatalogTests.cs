using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

using static Negaflow.Catalog.UnitTests.LibraryFrameFixture;

internal static class DevelopRecipeCatalogTests
{
    public static void Run()
    {
        VerifyLookPresets();
        VerifyDevelopSettingsTransfer();
        VerifyBwToning();
    }

    private static void VerifyLookPresets()
    {
        static bool Near(double actual, double expected) => Math.Abs(actual - expected) < 1e-12;

        string presetRoot = Path.Combine(AppContext.BaseDirectory, "presets");
        IReadOnlyList<LookPreset> bundled = PresetRegistry.LoadAll(presetRoot);
        Check(bundled.Count == PresetRegistry.BundledIds.Count, "preset_all_bundled_load");
        Check(bundled.Select(preset => preset.Id).SequenceEqual(PresetRegistry.BundledIds),
            "preset_bundled_order");
        Check(bundled.All(preset => preset.FilmTypes.Count > 0), "preset_bundled_have_film_types");

        LookPreset? neutral = bundled.FirstOrDefault(preset => preset.Id == "neutral");
        Check(neutral is not null && neutral.BaseTone == ToneAdjustment.Neutral,
            "preset_neutral_is_identity_tone");
        Check(neutral is not null && neutral.AppliesTo(FilmType.BlackAndWhitePositive),
            "preset_neutral_applies_to_all_film");

        // warm-lab 은 두 가지 미묘한 매핑을 모두 가진 유일한 번들 프로파일입니다.
        LookPreset? warmLab = bundled.FirstOrDefault(preset => preset.Id == "warm-lab");
        Check(warmLab is not null, "preset_warm_lab_present");
        if (warmLab is not null)
        {
            ToneAdjustment tone = warmLab.BaseTone;
            // highlightRollOff 0.30 → highlight -0.30. 부호가 살아 있지 않으면 명부 보호가
            // 명부 증폭이 됩니다.
            Check(Near(tone.Highlight, -0.30), "preset_highlight_roll_off_inverted");
            // midtoneLift 0.02 → exposure +0.002.
            Check(Near(tone.Exposure, 0.002), "preset_midtone_lift_scales_exposure");
            Check(Near(tone.Density, 0.12) && Near(tone.Contrast, 0.08),
                "preset_tone_passthrough");
            Check(Near(tone.Shadow, -0.02), "preset_black_softness_is_shadow");
            Check(tone.CurveHighlights == 0.0 && tone.CurveShadows == 0.0,
                "preset_leaves_point_curve_alone");
            Check(warmLab.AppliesTo(FilmType.ColorNegative) &&
                !warmLab.AppliesTo(FilmType.BlackAndWhiteNegative),
                "preset_film_type_gate");
        }

        Check(PresetRegistry.LoadAll(Path.Combine(presetRoot, "missing")).Count == 0,
            "preset_missing_directory_is_empty");

        // 어느 필름에도 걸리지 않는 프로파일은 UI 에서 조용히 사라집니다. 읽는 자리에서 거부합니다.
        using JsonDocument noFilm = JsonDocument.Parse(
            """{"name":"Ghost","filmTypes":[],"tone":{},"color":{},"texture":{}}""");
        Check(PresetRegistry.Parse(noFilm.RootElement, "ghost") is null,
            "preset_rejects_empty_film_types");
        using JsonDocument unknownFilm = JsonDocument.Parse(
            """{"name":"Ghost","filmTypes":["instant"],"tone":{},"color":{},"texture":{}}""");
        Check(PresetRegistry.Parse(unknownFilm.RootElement, "ghost") is null,
            "preset_rejects_unknown_film_types");
        using JsonDocument noName = JsonDocument.Parse(
            """{"filmTypes":["colorNegative"]}""");
        Check(PresetRegistry.Parse(noName.RootElement, "nameless") is null,
            "preset_requires_name");

        LookPreset composed = new(
            "test",
            "Test",
            1,
            [FilmType.ColorNegative],
            new LookPresetTone(0.1, 0.2, 0.3, 0.4, 0.05, 0.5),
            new LookPresetColor(0.1, 0.2, 0.3, 0.4),
            new LookPresetTexture(0.5, 0.2, 0.3));

        ToneAdjustment userTone = new(
            Exposure: 0.25,
            Contrast: -0.1,
            CurveHighlights: 0.7,
            CurveLights: 0.0,
            CurveDarks: 0.0,
            CurveShadows: -0.4,
            Density: 0.05,
            Highlight: 0.2,
            Shadow: 0.1,
            Whites: 0.3,
            Blacks: -0.3);
        ToneAdjustment mergedTone = LookPresetComposition.Compose(composed, userTone);
        Check(Near(mergedTone.Exposure, 0.15 + 0.25), "compose_tone_adds_exposure");
        Check(Near(mergedTone.Contrast, 0.3 - 0.1), "compose_tone_adds_contrast");
        // 프리셋이 정하지 않는 축은 사용자 값이 그대로 살아남아야 합니다.
        Check(Near(mergedTone.CurveHighlights, 0.7) && Near(mergedTone.CurveShadows, -0.4),
            "compose_tone_keeps_point_curve");
        Check(Near(mergedTone.Whites, 0.3) && Near(mergedTone.Blacks, -0.3),
            "compose_tone_keeps_whites_blacks");
        Check(Near(mergedTone.Highlight, -0.4 + 0.2), "compose_tone_adds_over_inverted_highlight");

        TextureRecipe userTexture = new(
            Grain: 0.0, Sharpness: 0.9, Halation: 0.3, Clarity: -0.2, Vignette: 0.4);
        TextureRecipe mergedTexture = LookPresetComposition.Compose(composed, userTexture);
        // 사용자가 0 이어도 프리셋의 입자는 남습니다. 더하기였다면 0.5 가 아니라 0.5 를 넘습니다.
        Check(Near(mergedTexture.Grain, 0.5), "compose_texture_takes_preset_grain");
        Check(Near(mergedTexture.Sharpness, 0.9), "compose_texture_takes_larger_sharpness");
        Check(Near(mergedTexture.Halation, 0.3), "compose_texture_halation_tie");
        Check(Near(mergedTexture.Clarity, -0.2) && Near(mergedTexture.Vignette, 0.4),
            "compose_texture_passes_clarity_vignette");
        Check(mergedTexture.IsValid, "compose_texture_stays_in_range");

        ColorModelRecipe userColor = new(
            Warmth: 0.05, Tint: -0.05, ColorDepth: 0.1, Vibrance: 0.6,
            Saturation: -0.2, RedPrimary: 0.11, GreenPrimary: -0.12, BluePrimary: 0.13);
        ColorModelRecipe mergedColor = LookPresetComposition.Compose(composed, userColor);
        Check(Near(mergedColor.Warmth, 0.15) && Near(mergedColor.Tint, 0.15),
            "compose_color_adds_warmth_tint");
        Check(Near(mergedColor.ColorDepth, 0.4) && Near(mergedColor.Saturation, 0.2),
            "compose_color_adds_depth_saturation");
        Check(Near(mergedColor.Vibrance, 0.6) && Near(mergedColor.RedPrimary, 0.11) &&
            Near(mergedColor.GreenPrimary, -0.12) && Near(mergedColor.BluePrimary, 0.13),
            "compose_color_keeps_unpreset_axes");

        // catalog 왕복. presetID 는 params 형제이며, 떼기와 안 건드림이 구별돼야 합니다.
        Check(ReadFrame(FrameRecord()).Frame?.LookPresetId is null,
            "preset_absent_key_is_no_preset");

        JsonObject tagged = FrameRecord();
        LibraryFrameWriteResult applied = LibraryFrameWriter.Apply(
            tagged,
            new LibraryFrameEdit(ToneAdjustment.Neutral, null,
                LookPreset: new LookPresetSelection("warm-lab")));
        Check(applied.IsSuccess, "preset_write_success");
        Check(tagged[LibraryFrameReader.LookPresetIdName] is null,
            "preset_write_leaves_input_untouched");
        if (applied.FrameRecord is { } writtenFrame)
        {
            Check(ReadFrame(writtenFrame).Frame?.LookPresetId == "warm-lab",
                "preset_round_trips_through_catalog");
            Check(writtenFrame[LibraryFrameReader.ParametersName]?
                    .AsObject().ContainsKey(LibraryFrameReader.LookPresetIdName) != true,
                "preset_is_not_written_into_params");

            // 값을 주지 않으면 그대로 두고, None 을 주면 뗍니다.
            LibraryFrameWriteResult untouched = LibraryFrameWriter.Apply(
                writtenFrame, new LibraryFrameEdit(ToneAdjustment.Neutral, null));
            Check(untouched.FrameRecord is { } keptFrame &&
                ReadFrame(keptFrame).Frame?.LookPresetId == "warm-lab",
                "preset_unspecified_edit_keeps_preset");

            LibraryFrameWriteResult cleared = LibraryFrameWriter.Apply(
                writtenFrame,
                new LibraryFrameEdit(ToneAdjustment.Neutral, null,
                    LookPreset: LookPresetSelection.None));
            Check(cleared.FrameRecord is { } clearedFrame &&
                ReadFrame(clearedFrame).Frame?.LookPresetId is null,
                "preset_none_selection_detaches");
        }

        Check(LibraryFrameWriter.Apply(
                FrameRecord(),
                new LibraryFrameEdit(ToneAdjustment.Neutral, null,
                    LookPreset: new LookPresetSelection("  "))).Error ==
            LibraryFrameError.InvalidLookPresetId,
            "preset_write_rejects_blank_id");

        JsonObject brokenPreset = FrameRecord();
        brokenPreset[LibraryFrameReader.LookPresetIdName] = 7;
        Check(ReadFrame(brokenPreset).Error == LibraryFrameError.InvalidLookPresetId,
            "preset_read_rejects_non_string");

        // neutral 을 얹는 것은 아무것도 얹지 않는 것과 같아야 합니다.
        if (neutral is not null)
        {
            Check(LookPresetComposition.Compose(neutral, userTone) == userTone,
                "compose_neutral_tone_is_identity");
            Check(LookPresetComposition.Compose(neutral, userColor) == userColor,
                "compose_neutral_color_is_identity");
            Check(LookPresetComposition.Compose(neutral, userTexture) == userTexture,
                "compose_neutral_texture_is_identity");
        }
    }

    /// <summary>
    /// 현상 설정 복사/붙여넣기입니다. 무엇이 옮겨가고 무엇이 남는지가 이 기능의 전부이므로
    /// 묶음별 경계와 record 왕복만 봅니다.
    /// </summary>
    private static void VerifyDevelopSettingsTransfer()
    {
        static JsonObject PlainRecord() => new()
        {
            ["id"] = "frame-2",
            ["rawScanPath"] = @"C:\scans\roll-01\IMG_0002.tif",
            ["sourceKind"] = "scanner",
            ["filmType"] = "bwNegative",
            ["params"] = new JsonObject
            {
                ["filmType"] = "bwNegative",
                ["exposure"] = -0.4,
                ["grain"] = 0.05,
                ["keepMe"] = 42,
            },
        };

        if (ReadFrame(FrameRecord()).Frame is not { } source ||
            ReadFrame(PlainRecord()).Frame is not { } destination)
        {
            Check(false, "transfer_fixtures_read");
            return;
        }

        Check(DevelopSettingsPasteScope.Empty.IsEmpty &&
            DevelopSettingsPasteScope.All.IsFullDevelopScope,
            "transfer_scope_edges");
        Check(ReferenceEquals(
            DevelopSettingsPasteScope.Empty.Apply(source, destination), destination),
            "transfer_empty_scope_changes_nothing");

        // 톤만 옮기면 톤과 프리셋만 갑니다. 질감과 필름 종류는 대상 것이 남아야 합니다.
        LibraryFrameSnapshot toneOnly =
            new DevelopSettingsPasteScope(false, true, false, false, false)
                .Apply(source, destination);
        Check(toneOnly.Tone == source.Tone && toneOnly.PointCurves == source.PointCurves,
            "transfer_tone_scope_moves_tone");
        Check(toneOnly.Texture == destination.Texture &&
            toneOnly.Route.FilmType == destination.Route.FilmType &&
            toneOnly.ImageTransform == destination.ImageTransform,
            "transfer_tone_scope_leaves_the_rest");

        LibraryFrameSnapshot baseOnly =
            new DevelopSettingsPasteScope(true, false, false, false, false)
                .Apply(source, destination);
        Check(baseOnly.Route.FilmType == source.Route.FilmType &&
            baseOnly.Base == source.Base && baseOnly.ManualBase == source.ManualBase,
            "transfer_base_scope_moves_route_and_base");
        Check(baseOnly.Tone == destination.Tone, "transfer_base_scope_leaves_tone");

        // 베이스 R/G/B 는 "어떻게 잴지" 가 아니라 **잰 값 자체**를 옮깁니다. 한 컷에서 제대로
        // 잡아 둔 Dmin 을 같은 롤 나머지에 물리는 자리라, 받는 쪽이 수동으로 바뀌어야 합니다 -
        // 자동인 채로 두면 받는 쪽이 자기 사진에서 다시 재서 컷마다 값이 달라집니다.
        LibraryFrameSnapshot baseRgbOnly =
            new DevelopSettingsPasteScope(false, false, false, false, false, true)
                .Apply(source, destination);
        Check(baseRgbOnly.Base.Mode == BaseEstimationMode.Manual,
            "transfer_base_rgb_scope_switches_to_manual");
        Check(baseRgbOnly.ManualBase == (source.AppliedBase ?? source.ManualBase),
            "transfer_base_rgb_scope_moves_the_measured_value");
        Check(baseRgbOnly.Tone == destination.Tone &&
            baseRgbOnly.Route.FilmType == destination.Route.FilmType,
            "transfer_base_rgb_scope_leaves_the_rest");
        // 베이스 묶음만으로는 값이 따라가지 않습니다 - 모드만 갑니다.
        Check(!new DevelopSettingsPasteScope(true, false, false, false, false).BaseRgb,
            "transfer_base_scope_does_not_imply_base_rgb");
        // 사용자 프리셋은 여러 사진에 다시 쓰는 것이라 한 컷의 Dmin 을 실으면 안 됩니다.
        // 그것을 담으면 그 프리셋을 쓰는 모든 사진이 남의 필름 베이스로 현상됩니다.
        Check(!DevelopSettingsPasteScope.Preset.BaseRgb,
            "preset_scope_never_carries_one_frames_base_rgb");
        Check(DevelopSettingsPasteScope.Preset.Base &&
            DevelopSettingsPasteScope.Preset.Tone &&
            DevelopSettingsPasteScope.Preset.Color &&
            DevelopSettingsPasteScope.Preset.Detail &&
            DevelopSettingsPasteScope.Preset.Geometry,
            "preset_scope_carries_everything_else");

        LibraryFrameSnapshot everything =
            DevelopSettingsPasteScope.All.Apply(source, destination);
        // "모든 설정" 은 베이스 R/G/B 도 데려가야 합니다.
        Check(DevelopSettingsPasteScope.All.BaseRgb, "transfer_all_scope_includes_base_rgb");
        Check(everything.Base.Mode == BaseEstimationMode.Manual &&
            everything.ManualBase == (source.AppliedBase ?? source.ManualBase),
            "transfer_all_scope_moves_the_measured_base");
        Check(everything.Id == destination.Id &&
            everything.SourcePath == destination.SourcePath &&
            everything.Rating == destination.Rating,
            "transfer_never_moves_frame_identity");
        Check(everything.Route.SourceTransport == destination.Route.SourceTransport,
            "transfer_never_moves_source_transport");
        Check(everything.Texture == source.Texture &&
            everything.NoiseReduction == source.NoiseReduction &&
            everything.ImageTransform == source.ImageTransform &&
            everything.ColorMixer == source.ColorMixer,
            "transfer_full_scope_moves_the_recipe");

        // record 왕복. writer 가 모르는 키는 그대로 남아야 합니다.
        JsonObject target = PlainRecord();
        LibraryFrameWriteResult pasted = DevelopSettingsTransfer.Paste(
            target, source, destination, DevelopSettingsPasteScope.All);
        Check(pasted.IsSuccess, "transfer_paste_writes");
        if (pasted.FrameRecord is { } pastedRecord)
        {
            Check(target["params"]?["exposure"]?.GetValue<double>() == -0.4,
                "transfer_paste_leaves_input_untouched");
            Check(pastedRecord["params"]?["keepMe"]?.GetValue<int>() == 42,
                "transfer_paste_preserves_unknown_keys");
            Check(pastedRecord["rawScanPath"]?.GetValue<string>() ==
                @"C:\scans\roll-01\IMG_0002.tif",
                "transfer_paste_keeps_destination_path");
            if (ReadFrame(pastedRecord).Frame is { } reread)
            {
                Check(reread.Tone == source.Tone && reread.Texture == source.Texture &&
                    reread.Route.FilmType == source.Route.FilmType &&
                    reread.Route.FilmEmulation == source.Route.FilmEmulation,
                    "transfer_paste_round_trips");
            }
            else
            {
                Check(false, "transfer_paste_round_trips");
            }
        }

        // 사용자 프리셋은 같은 붙여넣기를 파일에 담아 둔 것입니다.
        DevelopUserPreset? captured = DevelopUserPresetStore.Capture(source, "프리셋 1");
        Check(captured is not null, "user_preset_capture");
        if (captured is not null)
        {
            Check(captured.Recipe["rawScanPath"]?.GetValue<string>() !=
                source.SourcePath,
                "user_preset_does_not_store_the_photo_path");
            LibraryFrameWriteResult appliedPreset = DevelopUserPresetStore.Apply(
                PlainRecord(), captured, destination);
            Check(appliedPreset.FrameRecord is { } appliedRecord &&
                ReadFrame(appliedRecord).Frame is { } appliedFrame &&
                appliedFrame.Tone == source.Tone &&
                appliedFrame.Texture == source.Texture &&
                appliedFrame.SourcePath == destination.SourcePath,
                "user_preset_apply_round_trips");

            string presetPath = Path.Combine(
                AppContext.BaseDirectory,
                "user-preset-tests",
                $"{Environment.ProcessId}-{Guid.NewGuid():N}",
                "user-presets.json");
            Check(DevelopUserPresetStore.Save(presetPath, [captured]), "user_preset_save");
            IReadOnlyList<DevelopUserPreset> loaded = DevelopUserPresetStore.Load(presetPath);
            Check(loaded.Count == 1 && loaded[0].Id == captured.Id &&
                loaded[0].Name == "프리셋 1",
                "user_preset_load_round_trips");
            Check(loaded.Count == 1 &&
                DevelopUserPresetStore.Apply(PlainRecord(), loaded[0], destination)
                    .FrameRecord is { } reloadedRecord &&
                ReadFrame(reloadedRecord).Frame?.Tone == source.Tone,
                "user_preset_survives_the_file");
            Check(DevelopUserPresetStore.Load(presetPath + ".missing").Count == 0,
                "user_preset_missing_file_is_empty");
        }
    }

    /// <summary>
    /// 흑백 토닝입니다. 값이 없을 때 0 이 아니라 모드별 기본 색조를 쓰는 것이 이 recipe 의
    /// 유일한 함정이라 거기에 집중합니다.
    /// </summary>
    private static void VerifyBwToning()
    {
        static bool Near(double actual, double expected) => Math.Abs(actual - expected) < 1e-12;

        Check(BwToningRecipe.None.IsIdentity && BwToningRecipe.None.IsValid,
            "bw_toning_none_is_identity");
        Check(Near(BwToningRecipe.For(BwToningMode.Sepia).ShadowHue, 32.0) &&
            Near(BwToningRecipe.For(BwToningMode.Sepia).HighlightHue, 48.0),
            "bw_toning_sepia_default_hues");
        Check(Near(BwToningRecipe.For(BwToningMode.Selenium).ShadowHue, 285.0) &&
            Near(BwToningRecipe.For(BwToningMode.Selenium).HighlightHue, 34.0),
            "bw_toning_selenium_default_hues");
        // 모드를 켜도 세기가 0 이면 그림이 그대로입니다.
        Check(BwToningRecipe.For(BwToningMode.Sepia).IsIdentity,
            "bw_toning_zero_strength_is_identity");
        Check(!BwToningRecipe.For(BwToningMode.Sepia, 0.45).IsIdentity,
            "bw_toning_engaged_strength_is_not_identity");
        Check(Near(BwToningRecipe.NormalizeHue(370.0), 10.0) &&
            Near(BwToningRecipe.NormalizeHue(-10.0), 350.0) &&
            Near(BwToningRecipe.NormalizeHue(190.0), 190.0),
            "bw_toning_hue_wraps_like_swift");

        // 모드만 적힌 payload 는 그 모드의 기본 색조로 읽혀야 합니다 — 0 으로 읽으면 전혀
        // 다른 색이 나옵니다.
        JsonObject modeOnly = FrameRecord();
        modeOnly["params"]!.AsObject()["bwToning"] = new JsonObject
        {
            ["mode"] = "sepia",
            ["strength"] = 0.6,
        };
        Check(ReadFrame(modeOnly).Frame is { } sepiaFrame &&
            sepiaFrame.BwToning.Mode == BwToningMode.Sepia &&
            Near(sepiaFrame.BwToning.ShadowHue, 32.0) &&
            Near(sepiaFrame.BwToning.HighlightHue, 48.0),
            "bw_toning_missing_hues_fall_back_per_mode");

        Check(ReadFrame(FrameRecord()).Frame?.BwToning == BwToningRecipe.None,
            "bw_toning_absent_key_is_off");

        JsonObject unknownMode = FrameRecord();
        unknownMode["params"]!.AsObject()["bwToning"] = new JsonObject { ["mode"] = "platinum" };
        Check(ReadFrame(unknownMode).Error == LibraryFrameError.InvalidBwToning,
            "bw_toning_rejects_unknown_mode");

        JsonObject outOfRange = FrameRecord();
        outOfRange["params"]!.AsObject()["bwToning"] = new JsonObject
        {
            ["mode"] = "selenium",
            ["shadowHue"] = 400.0,
        };
        Check(ReadFrame(outOfRange).Error == LibraryFrameError.InvalidBwToning,
            "bw_toning_rejects_hue_out_of_range");

        BwToningRecipe written = new(BwToningMode.Selenium, 280.0, 40.0, 0.7);
        LibraryFrameWriteResult applied = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(ToneAdjustment.Neutral, null, BwToning: written));
        Check(applied.FrameRecord is { } appliedRecord &&
            ReadFrame(appliedRecord).Frame?.BwToning == written,
            "bw_toning_round_trips");

        // 끄면 키를 지웁니다. 컬러 frame 의 params 에 쓸모없는 색조를 남기지 않습니다.
        // 자동 GrainMend 세기는 macOS 앱 UI 에 없지만 CLI·프리셋·붙여넣기로 들어옵니다.
        // 버리면 그런 frame 이 Windows 에서 다르게 현상됩니다.
        JsonObject withRemoval = FrameRecord();
        withRemoval["params"]!.AsObject()["defectRemoval"] = 0.6;
        Check(ReadFrame(withRemoval).Frame?.DefectRemovalStrength == 0.6,
            "defect_removal_strength_round_trips");
        JsonObject badRemoval = FrameRecord();
        badRemoval["params"]!.AsObject()["defectRemoval"] = 1.5;
        Check(ReadFrame(badRemoval).Error == LibraryFrameError.InvalidDefectRecipe,
            "defect_removal_strength_rejects_out_of_range");

        Check(applied.FrameRecord is { } toClear &&
            LibraryFrameWriter.Apply(
                toClear,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral, null, BwToning: BwToningRecipe.None))
                .FrameRecord?["params"]?.AsObject().ContainsKey("bwToning") == false,
            "bw_toning_off_removes_the_key");
    }

}
