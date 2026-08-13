using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    /// <summary>
    /// 이 인자로 실행되면 테스트가 아니라 lock 경쟁자로 동작합니다. 자기 자신을 다시 띄워
    /// **다른 프로세스**에서 세션을 열어 보게 하는 용도이며, 그래야 단일 작성자 계약이 프로세스
    /// 경계에서도 성립한다는 것이 추론이 아니라 관측이 됩니다.
    /// </summary>
    private const string LockContenderArgument = "--lock-contender";

    private static int Main(string[] args)
    {
        if (args.Length == 2 && args[0] == LockContenderArgument)
        {
            return RunLockContender(args[1]);
        }

        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        VerifyValidFixtureCases(fixture.RootElement);
        VerifyInvalidFixtureCases(fixture.RootElement);
        VerifyReaderShapeErrors();
        VerifyRouteWriting(fixture.RootElement);
        VerifyAllFilmEmulationNames(fixture.RootElement);
        VerifyInvalidSelections(fixture.RootElement);
        VerifyCanonicalJson();
        VerifyLookPresets();
        VerifyDevelopSettingsTransfer();
        VerifyBwToning();
        VerifyStorageRootResolution();
        VerifyCatalogProcessLock();
        VerifySqliteCatalogStore();
        VerifyLibraryFrameProjection();
        VerifyLocalDodgeBurnPersistence();

        var report = new
        {
            status = Failures.Count == 0 ? "ok" : "failed",
            operation = "catalog_unit_tests",
            assertions = assertionCount,
            failures = Failures,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return Failures.Count == 0 ? 0 : 1;
    }

    private static void VerifyValidFixtureCases(JsonElement root)
    {
        Check(root.GetProperty("schemaVersion").GetInt32() == 1, "fixture_schema_version");

        foreach (JsonElement testCase in root.GetProperty("validCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(result.IsSuccess, $"{id}_read_success");
            if (result.Route is not { } route)
            {
                continue;
            }

            JsonElement expected = testCase.GetProperty("expected");
            Check(SourceTransportName(route.SourceTransport) ==
                expected.GetProperty("sourceTransport").GetString(), $"{id}_transport");
            Check(SourceSignalName(route.SourceSignalKind) ==
                expected.GetProperty("sourceSignalKind").GetString(), $"{id}_signal");
            Check(ProcessName(route.DevelopmentProcess) ==
                expected.GetProperty("developmentProcess").GetString(), $"{id}_process");
            Check(FilmLookSourceName(route.FilmLookSource) ==
                expected.GetProperty("filmLookSource").GetString(), $"{id}_look_source");
            Check(FilmEmulationName(route.FilmEmulation) ==
                expected.GetProperty("filmEmulation").GetString(), $"{id}_emulation");
            Check(Math.Abs(route.FilmEmulationIntensity -
                expected.GetProperty("filmEmulationIntensity").GetDouble()) < 1e-12,
                $"{id}_intensity");
            Check(route.UsedLegacySourceSignal ==
                expected.GetProperty("usedLegacySourceSignal").GetBoolean(),
                $"{id}_legacy_signal");
            Check(route.UsedLegacyIntensityDefault ==
                expected.GetProperty("usedLegacyIntensityDefault").GetBoolean(),
                $"{id}_legacy_intensity");
            Check(route.IsDigitalSource ==
                (route.SourceSignalKind == SourceSignalKind.RenderedDigital),
                $"{id}_digital_derived");
        }
    }

    private static void VerifyInvalidFixtureCases(JsonElement root)
    {
        foreach (JsonElement testCase in root.GetProperty("invalidCases").EnumerateArray())
        {
            string id = testCase.GetProperty("id").GetString() ?? "missing-id";
            DevelopRouteReadResult result = DevelopRouteReader.Read(
                testCase.GetProperty("frame"));
            Check(!result.IsSuccess, $"{id}_read_rejected");
            Check(ErrorName(result.Error) == testCase.GetProperty("expectedError").GetString(),
                $"{id}_error");
            Check(result.Route is null, $"{id}_no_partial_route");
        }
    }

    private static void VerifyRouteWriting(JsonElement root)
    {
        JsonElement legacyFrame = root.GetProperty("validCases")[0].GetProperty("frame");
        JsonObject original = JsonNode.Parse(legacyFrame.GetRawText())!.AsObject();
        DevelopRouteSelection digitalSelection = DevelopRouteSelection.FromProcess(
            DevelopmentProcess.DigitalColor,
            FilmEmulation.Portra400);

        Check(digitalSelection.FilmEmulationIntensity == 0.5, "new_recipe_intensity_half");
        DevelopRouteWriteResult write = DevelopRouteWriter.Apply(original, digitalSelection);
        Check(write.IsSuccess, "write_digital_success");
        if (write.FrameRecord is not { } digitalFrame)
        {
            return;
        }

        Check(original["sourceSignalKind"] is null, "write_original_unchanged");
        Check(digitalFrame["sourceKind"]!.GetValue<string>() == "imported",
            "write_preserves_transport");
        Check(digitalFrame["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "write_preserves_unknown_frame_field");
        JsonObject digitalParameters = digitalFrame["params"]!.AsObject();
        Check(digitalParameters["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "write_preserves_unknown_parameter_field");
        Check(digitalParameters["isDigitalSource"]!.GetValue<bool>(),
            "write_sets_legacy_digital_marker");

        DevelopRouteReadResult digitalRead = ReadNode(digitalFrame);
        Check(digitalRead.IsSuccess, "write_digital_round_trip");
        Check(digitalRead.Route?.DevelopmentProcess == DevelopmentProcess.DigitalColor,
            "write_digital_process");
        Check(digitalRead.Route?.SourceTransport == FrameSourceTransport.Imported,
            "import_transport_does_not_override_signal");

        DevelopRouteWriteResult filmWrite = DevelopRouteWriter.Apply(
            digitalFrame,
            DevelopRouteSelection.FromProcess(
                DevelopmentProcess.E6,
                FilmEmulation.Velvia50,
                0.35));
        Check(filmWrite.IsSuccess, "write_film_success");
        if (filmWrite.FrameRecord is not { } filmFrame)
        {
            return;
        }
        Check(!filmFrame["params"]!.AsObject().ContainsKey("isDigitalSource"),
            "write_film_omits_false_marker");
        DevelopRouteReadResult filmRead = ReadNode(filmFrame);
        Check(filmRead.IsSuccess, "write_film_round_trip");
        Check(filmRead.Route?.SourceSignalKind == SourceSignalKind.FilmPositiveScan,
            "write_film_explicit_signal");
        Check(filmRead.Route?.UsedLegacySourceSignal == false,
            "write_film_not_legacy_signal");
    }

    private static void VerifyReaderShapeErrors()
    {
        using JsonDocument array = JsonDocument.Parse("[]");
        DevelopRouteReadResult result = DevelopRouteReader.Read(array.RootElement);
        Check(result.Error == DevelopRouteError.FrameRecordNotObject,
            "reader_rejects_non_object");
        Check(result.Route is null, "reader_non_object_no_partial_route");
    }

    private static void VerifyAllFilmEmulationNames(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[1].GetProperty("frame").GetRawText())!.AsObject();
        foreach (FilmEmulation emulation in Enum.GetValues<FilmEmulation>())
        {
            DevelopRouteWriteResult write = DevelopRouteWriter.Apply(
                frame,
                DevelopRouteSelection.FromProcess(DevelopmentProcess.D76, emulation));
            Check(write.IsSuccess, $"emulation_{emulation}_write");
            if (write.FrameRecord is not { } written)
            {
                continue;
            }
            DevelopRouteReadResult read = ReadNode(written);
            Check(read.Route?.FilmEmulation == emulation, $"emulation_{emulation}_round_trip");
            Check(read.Route?.SourceTransport == FrameSourceTransport.Imported,
                $"emulation_{emulation}_transport_independent");
        }
    }

    private static void VerifyInvalidSelections(JsonElement root)
    {
        JsonObject frame = JsonNode.Parse(
            root.GetProperty("validCases")[0].GetProperty("frame").GetRawText())!.AsObject();
        DevelopRouteWriteResult mismatched = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.RenderedDigital,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5));
        Check(mismatched.Error == DevelopRouteError.SourceSignalFilmTypeMismatch,
            "invalid_selection_signal_type");
        Check(mismatched.FrameRecord is null, "invalid_selection_no_partial_record");
        Check(frame["sourceSignalKind"] is null, "invalid_selection_input_unchanged");

        DevelopRouteWriteResult nonfinite = DevelopRouteWriter.Apply(
            frame,
            new DevelopRouteSelection(
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive,
                FilmEmulation.None,
                double.NaN));
        Check(nonfinite.Error == DevelopRouteError.InvalidFilmEmulationIntensity,
            "invalid_selection_nonfinite");

        JsonObject missingTransport = new()
        {
            ["params"] = new JsonObject(),
        };
        DevelopRouteWriteResult missingTransportWrite = DevelopRouteWriter.Apply(
            missingTransport,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(missingTransportWrite.Error == DevelopRouteError.MissingSourceTransport,
            "writer_requires_transport");

        JsonObject invalidParameters = new()
        {
            ["sourceKind"] = "scanner",
            ["params"] = new JsonArray(),
        };
        DevelopRouteWriteResult invalidParametersWrite = DevelopRouteWriter.Apply(
            invalidParameters,
            DevelopRouteSelection.FromProcess(DevelopmentProcess.C41));
        Check(invalidParametersWrite.Error == DevelopRouteError.ParametersNotObject,
            "writer_rejects_non_object_parameters");
    }

    private static void VerifyCanonicalJson()
    {
        JsonNode first = JsonNode.Parse(
            """{"z":0,"a":{"b":2,"a":1},"list":[{"z":3,"a":2}]}""")!;
        JsonNode second = JsonNode.Parse(
            """{"list":[{"a":2,"z":3}],"a":{"a":1,"b":2},"z":0}""")!;
        byte[] firstBytes = CatalogJson.SerializeCanonical(first);
        byte[] secondBytes = CatalogJson.SerializeCanonical(second);
        const string expected = "{\"a\":{\"a\":1,\"b\":2},\"list\":[{\"a\":2,\"z\":3}],\"z\":0}";

        Check(firstBytes.SequenceEqual(secondBytes), "canonical_order_independent");
        Check(Encoding.UTF8.GetString(firstBytes) == expected, "canonical_expected_bytes");
    }

    /// <summary>
    /// 앱이 싣는 프로파일 여섯 개를 그대로 읽고, 프리셋이 현상 값으로 번역되는 규칙과 그 위에
    /// 사용자 값이 얹히는 규칙을 확인합니다. 이 두 규칙이 곧 룩의 결과입니다.
    /// </summary>
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

        LibraryFrameSnapshot everything =
            DevelopSettingsPasteScope.All.Apply(source, destination);
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

    private static void VerifyStorageRootResolution()
    {
        StorageRootResolutionResult missing = StorageRootResolver.ResolveForTests(string.Empty);
        Check(missing.Error == StorageRootResolutionError.MissingBaseRoot,
            "storage_root_rejects_empty");
        Check(missing.Roots is null, "storage_root_empty_no_partial_result");

        StorageRootResolutionResult relative = StorageRootResolver.ResolveForTests("relative");
        Check(relative.Error == StorageRootResolutionError.BaseRootNotFullyQualified,
            "storage_root_rejects_relative");

        string isolatedBase = Path.Combine(
            AppContext.BaseDirectory,
            "storage-root-tests",
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootResolutionResult resolution = StorageRootResolver.ResolveForTests(isolatedBase);
        Check(resolution.IsSuccess, "storage_root_test_resolution_success");
        if (resolution.Roots is not { } roots)
        {
            return;
        }

        string expectedProductRoot = Path.Combine(
            Path.GetFullPath(isolatedBase),
            "Negaflow");
        Check(roots.IsTestIsolated, "storage_root_marks_test_isolation");
        Check(roots.ProductDataRoot == expectedProductRoot, "storage_root_product_path");
        Check(roots.LibraryRoot == Path.Combine(expectedProductRoot, "Library"),
            "storage_root_library_path");
        Check(roots.CatalogPath == Path.Combine(roots.LibraryRoot, "library.sqlite"),
            "storage_root_catalog_path");
        Check(roots.CatalogBackupPath ==
            Path.Combine(roots.LibraryRoot, "library.backup.sqlite"),
            "storage_root_catalog_backup_path");
        Check(roots.CatalogLockPath ==
            Path.Combine(roots.LibraryRoot, "library.sqlite.lock"),
            "storage_root_catalog_lock_path");
        Check(roots.DefectRecipeRoot == Path.Combine(roots.LibraryRoot, "defects"),
            "storage_root_defects_path");
        Check(roots.BackupRoot == Path.Combine(roots.LibraryRoot, "Backups"),
            "storage_root_backups_path");
        Check(roots.PendingRestoreRoot == Path.Combine(roots.LibraryRoot, "PendingRestore"),
            "storage_root_pending_restore_path");
        Check(roots.MigrationRoot == Path.Combine(roots.LibraryRoot, "Migration"),
            "storage_root_migration_path");
        Check(roots.CacheRoot == Path.Combine(expectedProductRoot, "Cache"),
            "storage_root_cache_path");
        Check(roots.JournalRoot == Path.Combine(expectedProductRoot, "Journals"),
            "storage_root_journal_path");
        Check(roots.PluginRoot == Path.Combine(expectedProductRoot, "Plugins"),
            "storage_root_plugin_path");
        Check(roots.LogRoot == Path.Combine(expectedProductRoot, "Logs"),
            "storage_root_log_path");
        Check(roots.SettingsRoot == Path.Combine(expectedProductRoot, "Settings"),
            "storage_root_settings_path");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.CatalogPath), "storage_path_catalog_contained");
        Check(StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            roots.ProductDataRoot), "storage_path_root_contains_itself");
        Check(!StoragePathPolicy.IsLexicallyContained(
            roots.ProductDataRoot,
            $"{roots.ProductDataRoot}-outside"), "storage_path_rejects_prefix_sibling");

        Check(StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", "library.sqlite"),
            out string resolvedCatalog), "storage_path_resolves_relative");
        Check(resolvedCatalog == roots.CatalogPath, "storage_path_relative_value");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("..", "outside"),
            out _), "storage_path_rejects_parent_escape");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            roots.CatalogPath,
            out _), "storage_path_rejects_rooted_input");
        Check(!StoragePathPolicy.TryResolveRelative(
            roots.ProductDataRoot,
            Path.Combine("Library", ".", "library.sqlite"),
            out _), "storage_path_rejects_dot_component");
    }

    private static void VerifyCatalogProcessLock()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "storage-lock-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        CatalogProcessLock? firstLock = null;
        CatalogProcessLock? reacquiredLock = null;

        try
        {
            Check(!Directory.Exists(roots.ProductDataRoot), "catalog_lock_root_initially_absent");
            CatalogProcessLockAcquireResult first = CatalogProcessLock.TryAcquire(roots);
            firstLock = first.Lock;
            Check(first.IsSuccess, "catalog_lock_first_acquire");
            Check(firstLock?.IsHeld == true, "catalog_lock_first_held");
            Check(Directory.Exists(roots.LibraryRoot), "catalog_lock_creates_library_root");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_file_exists");
            Check(!File.Exists(roots.CatalogPath), "catalog_lock_does_not_create_catalog");
            Check(!Directory.Exists(roots.CacheRoot), "catalog_lock_does_not_create_cache");

            CatalogProcessLockAcquireResult second = CatalogProcessLock.TryAcquire(roots);
            Check(!second.IsSuccess, "catalog_lock_second_rejected");
            Check(second.Error == CatalogProcessLockError.Busy, "catalog_lock_second_busy");
            Check(second.Lock is null, "catalog_lock_busy_no_partial_handle");

            firstLock?.Dispose();
            Check(firstLock?.IsHeld == false, "catalog_lock_dispose_releases_handle");
            Check(File.Exists(roots.CatalogLockPath), "catalog_lock_stale_file_is_not_owner");

            CatalogProcessLockAcquireResult reacquired = CatalogProcessLock.TryAcquire(roots);
            reacquiredLock = reacquired.Lock;
            Check(reacquired.IsSuccess, "catalog_lock_reacquire_after_dispose");
            Check(reacquiredLock?.IsHeld == true, "catalog_lock_reacquired_held");
            reacquiredLock?.Dispose();
            reacquiredLock?.Dispose();
            Check(reacquiredLock?.IsHeld == false, "catalog_lock_dispose_idempotent");
        }
        finally
        {
            reacquiredLock?.Dispose();
            firstLock?.Dispose();
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static void VerifySqliteCatalogStore()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "catalog-store-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            VerifyStoreLifecycle(roots);
            VerifyStoreRefusals(roots);
            VerifyVerifiedCommit(roots);
            VerifyDefectSidecarStore(roots);
            VerifyBackupGeneration(roots);
            VerifyPendingRestore(roots);
            VerifyDefectCatalogHealthAndRestore(roots);
            VerifyInterruptedDefectRestore(roots);
            VerifyCatalogSession(roots);
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

    private static void VerifyDefectSidecarStore(StorageRootSet parentRoots)
    {
        string sidecarBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-sidecar");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(sidecarBase).Roots!;
        Guid frameId = Guid.Parse("8ac67219-88d5-46b0-af56-42b4600615f3");
        IReadOnlyList<DefectEditItem> items = DefectRecipeItems();

        DefectEditItem fingerprintProbe = new(
            Guid.Parse("00000000-0000-0000-0000-000000000001"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(DefectEditSummaryKind.ClassBreakdown),
            BaseSize: null,
            Preview: [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0, 0, 3, 3),
                    new DefectMask(false, new byte[36]),
                    3,
                    3,
                    new DefectMask(false, new byte[18])),
            ],
        };
        string canonicalV2 = DefectRecipeFingerprint.Compute(
            [fingerprintProbe],
            DefectRecipeFingerprint.LegacyVersion);
        Check(canonicalV2 ==
              "cc899b7949653a977862b0f24247b10dbcb820b7fcd38341823ede922b74b599",
            "defect_fingerprint_preserves_canonical_v2_golden");
        DefectEditItem changedProbe = fingerprintProbe with
        {
            Clusters =
            [
                fingerprintProbe.Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(
                        false,
                        Enumerable.Repeat((byte)1, 18).ToArray()),
                },
            ],
        };
        Check(DefectRecipeFingerprint.Compute(
                  [changedProbe],
                  DefectRecipeFingerprint.LegacyVersion) == canonicalV2,
            "defect_fingerprint_v2_ignores_post_baseline_attenuation");
        Check(DefectRecipeFingerprint.Compute([changedProbe]) !=
              DefectRecipeFingerprint.Compute([fingerprintProbe]),
            "defect_fingerprint_v3_binds_attenuation_bytes");

        DefectRecipeSnapshot revisionOne = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity: null,
            items);
        DefectSidecarWriteResult first = DefectSidecarStore.Write(roots, revisionOne);
        Check(first.IsSuccess && first.Kind == DefectSidecarWriteKind.Written,
            "defect_sidecar_first_write");

        DefectSidecarReadResult read = DefectSidecarStore.Read(roots, frameId);
        Check(read.IsSuccess && read.Snapshot?.RecipeRevision == 1,
            "defect_sidecar_read_revision");
        Check(read.Snapshot?.Items.Select(item => item.Kind).SequenceEqual(
            new[]
            {
                DefectEditKind.Brush,
                DefectEditKind.Region,
                DefectEditKind.Infrared,
                DefectEditKind.Clone,
            }) == true,
            "defect_sidecar_preserves_ordered_kinds");
        JsonObject legacyFingerprintJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(revisionOne))!.AsObject();
        legacyFingerprintJson["fingerprintVersion"] =
            DefectRecipeFingerprint.LegacyVersion;
        legacyFingerprintJson["recipeSHA256"] = DefectRecipeFingerprint.Compute(
            revisionOne.Items,
            DefectRecipeFingerprint.LegacyVersion);
        DefectSidecarReadResult migratedFingerprint = DefectSidecarCodec.Decode(
            CatalogJson.SerializeCanonical(legacyFingerprintJson),
            frameId,
            validateCompressedMasks: true);
        Check(migratedFingerprint.IsSuccess &&
              migratedFingerprint.Snapshot?.FingerprintVersion ==
                  DefectRecipeFingerprint.CurrentVersion &&
              migratedFingerprint.Snapshot.RecipeSha256 == revisionOne.RecipeSha256,
            "defect_sidecar_dual_reads_v2_and_migrates_identity_to_v3");
        JsonObject migratedFingerprintJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(migratedFingerprint.Snapshot!))!.AsObject();
        Check(migratedFingerprintJson["fingerprintVersion"]!.GetValue<int>() ==
                  DefectRecipeFingerprint.CurrentVersion &&
              migratedFingerprintJson["recipeSHA256"]!.GetValue<string>() ==
                  revisionOne.RecipeSha256,
            "defect_sidecar_migrated_snapshot_serializes_as_v3");
        Check(read.Snapshot is { } decodedRecipe &&
              DefectMaskCodec.TryDecodeRgba8(
                  decodedRecipe.Items[1].RegionMask!,
                  2,
                  2,
                  out byte[] decodedRegionMask) &&
              decodedRegionMask.SequenceEqual(
                  Enumerable.Range(0, 16).Select(value => (byte)value)),
            "defect_sidecar_preserves_region_mask");
        Check(read.Snapshot is { } decodedInfraredRecipe &&
              DefectMaskCodec.TryDecodeR16LittleEndian(
                  decodedInfraredRecipe.Items[2].Clusters![0].AttenuationR16!,
                  2,
                  2,
                  out byte[] decodedAttenuation) &&
              decodedAttenuation.SequenceEqual(
                  new byte[] { 0x00, 0x00, 0x01, 0x00, 0x34, 0x12, 0xff, 0xff }),
            "defect_sidecar_preserves_infrared_attenuation_r16");
        Check(DefectSidecarStore.Write(roots, revisionOne).Kind ==
              DefectSidecarWriteKind.AlreadyCurrent,
            "defect_sidecar_same_snapshot_idempotent");

        string firstSidecarPath = DefectSidecarStore.PathFor(roots, frameId);
        byte[] firstSidecarBytes = File.ReadAllBytes(firstSidecarPath);
        JsonObject corruptedAttenuation = JsonNode.Parse(firstSidecarBytes)!.AsObject();
        JsonObject infraredCluster = corruptedAttenuation["items"]![2]!["clusters"]![0]!
            .AsObject();
        infraredCluster["attenuationR16"]!["data"] = Convert.ToBase64String([1, 2, 3]);
        File.WriteAllBytes(
            firstSidecarPath,
            CatalogJson.SerializeCanonical(corruptedAttenuation));
        Check(DefectSidecarStore.Read(roots, frameId).Error ==
              DefectSidecarError.InvalidContent,
            "defect_sidecar_corrupt_infrared_attenuation_rejected");
        File.WriteAllBytes(firstSidecarPath, firstSidecarBytes);

        Guid legacyFrameId = Guid.Parse("316fb66a-b882-4130-82dd-854976a6e6ac");
        DefectEditItem legacyInfrared = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with { AttenuationR16 = null },
            ],
        };
        DefectRecipeSnapshot legacySnapshot = DefectRecipeSnapshot.Create(
            legacyFrameId,
            recipeRevision: 1,
            sourceIdentity: null,
            [legacyInfrared]);
        JsonObject legacyJson = JsonNode.Parse(
            DefectSidecarCodec.Serialize(legacySnapshot))!.AsObject();
        legacyJson["items"]![0]!["clusters"]![0]!.AsObject()
            .Remove("attenuationR16");
        Check(DefectSidecarCodec.Decode(
                  CatalogJson.SerializeCanonical(legacyJson),
                  legacyFrameId,
                  validateCompressedMasks: true).IsSuccess,
            "defect_sidecar_legacy_mask_only_cluster_reads");

        DefectSourceIdentity sourceIdentity = new(
            1_234,
            new string('a', 64));
        DefectRecipeSnapshot bound = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            items);
        Check(DefectSidecarStore.Write(roots, bound).Kind ==
              DefectSidecarWriteKind.Written,
            "defect_sidecar_same_revision_binds_source_identity");
        Check(DefectSidecarStore.Read(roots, frameId).Snapshot?.SourceIdentity ==
              sourceIdentity,
            "defect_sidecar_source_identity_readback");

        DefectEditItem changedAttenuation = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(
                        false,
                        new byte[] { 0x00, 0x00, 0x01, 0x00, 0x35, 0x12, 0xff, 0xff }),
                },
            ],
        };
        DefectRecipeSnapshot attenuationConflict = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            [items[0], items[1], changedAttenuation, items[3]]);
        Check(DefectSidecarStore.Write(roots, attenuationConflict).Error ==
              DefectSidecarError.ConflictingSameRevision,
            "defect_sidecar_same_revision_attenuation_conflict");

        DefectEditItem changedRegion = items[1] with { Strength = 0.25 };
        DefectRecipeSnapshot conflicting = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 1,
            sourceIdentity,
            [items[0], changedRegion, items[2], items[3]]);
        Check(DefectSidecarStore.Write(roots, conflicting).Error ==
              DefectSidecarError.ConflictingSameRevision,
            "defect_sidecar_same_revision_conflict");

        DefectRecipeSnapshot revisionTwo = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 2,
            sourceIdentity,
            [items[0], changedRegion, items[2], items[3]]);
        Check(DefectSidecarStore.Write(roots, revisionTwo).Kind ==
              DefectSidecarWriteKind.Written,
            "defect_sidecar_newer_revision_writes");
        DefectSidecarWriteResult stale = DefectSidecarStore.Write(roots, bound);
        Check(stale.Kind == DefectSidecarWriteKind.SkippedNewer &&
              stale.ExistingRevision == 2,
            "defect_sidecar_stale_completion_skipped");

        Check(DefectSidecarStore.Remove(roots, frameId, minimumRevision: 3).IsSuccess,
            "defect_sidecar_revision_aware_remove");
        Check(DefectSidecarStore.Write(roots, revisionTwo).Kind ==
              DefectSidecarWriteKind.SkippedNewer,
            "defect_sidecar_removed_revision_floor_blocks_late_write");
        Check(DefectSidecarStore.Read(roots, frameId).Error ==
              DefectSidecarError.NotFound,
            "defect_sidecar_remove_leaves_missing");

        DefectRecipeSnapshot revisionFour = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 4,
            sourceIdentity,
            items);
        Check(DefectSidecarStore.Write(roots, revisionFour).IsSuccess,
            "defect_sidecar_write_after_floor");
        string sidecarPath = DefectSidecarStore.PathFor(roots, frameId);
        JsonObject future = JsonNode.Parse(File.ReadAllBytes(sidecarPath))!.AsObject();
        future["version"] = 99;
        File.WriteAllBytes(sidecarPath, CatalogJson.SerializeCanonical(future));
        DefectSidecarReadResult unsupported = DefectSidecarStore.Read(roots, frameId);
        Check(unsupported.Error == DefectSidecarError.UnsupportedVersion &&
              unsupported.ObservedVersion == 99,
            "defect_sidecar_future_version_rejected");
        Check(DefectSidecarStore.Write(roots, revisionFour).Error ==
              DefectSidecarError.UnsupportedVersion,
            "defect_sidecar_future_version_not_overwritten");

        Guid invalidFrameId = Guid.Parse("2a35899b-f983-47d4-8047-57e99c5e2504");
        DefectEditItem invalidCompressed = items[2] with
        {
            Clusters =
            [
                items[2].Clusters![0] with
                {
                    Mask = new DefectMask(true, [1, 2, 3]),
                },
            ],
        };
        DefectRecipeSnapshot invalidZlib = DefectRecipeSnapshot.Create(
            invalidFrameId,
            recipeRevision: 1,
            sourceIdentity,
            [invalidCompressed]);
        Check(DefectSidecarStore.Write(roots, invalidZlib).Error ==
              DefectSidecarError.InvalidSnapshot,
            "defect_sidecar_invalid_zlib_rejected_before_publish");
    }

    private static IReadOnlyList<DefectEditItem> DefectRecipeItems()
    {
        DefectEditItem brush = new(
            Guid.Parse("1394d226-caff-4448-8669-b4dd09cf9946"),
            DefectEditKind.Brush,
            Enabled: true,
            Strength: 0.8,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush),
            new DefectSize(4_000, 3_000),
            [])
        {
            Strokes =
            [
                new DefectStroke(
                    [new DefectPoint(0.1, 0.2), new DefectPoint(0.2, 0.3)],
                    0.01),
            ],
        };

        DefectEditItem region = new(
            Guid.Parse("83566683-7599-439b-8ba3-599548916110"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(4_000, 3_000),
            [
                new DefectPreviewComponent(
                    DefectClassification.Dust,
                    0.9,
                    [new DefectPoint(0.25, 0.75)]),
            ])
        {
            RegionMask = new DefectMask(
                false,
                Enumerable.Range(0, 16).Select(value => (byte)value).ToArray()),
            RegionRoi = new DefectRect(12, 34, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };

        byte[] infraredMask = Enumerable.Repeat((byte)255, 16).ToArray();
        DefectEditItem infrared = new(
            Guid.Parse("33dedb29-b303-4551-b48a-081a2b454fe3"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 0.75,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Pinhole, 1)],
                    0.95)),
            new DefectSize(4_000, 3_000),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(50, 60, 2, 2),
                    new DefectMask(true, CompressZlib(infraredMask)),
                    2,
                    2,
                    new DefectMask(
                        false,
                        new byte[]
                        {
                            0x00, 0x00,
                            0x01, 0x00,
                            0x34, 0x12,
                            0xff, 0xff,
                        })),
            ],
        };

        DefectEditItem clone = new(
            Guid.Parse("392b167c-78ce-4d0f-a90f-b6fbb976ebfe"),
            DefectEditKind.Clone,
            Enabled: false,
            Strength: 0.5,
            new DefectEditLabel(DefectEditLabelKind.Clone, 24),
            new DefectEditSummary(DefectEditSummaryKind.Clone),
            new DefectSize(4_000, 3_000),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.4, 0.5), new DefectPoint(0.45, 0.55)],
                    0.05,
                    -0.02,
                    24,
                    0.6),
            ],
        };

        return [brush, region, infrared, clone];
    }

    private static byte[] CompressZlib(byte[] data)
    {
        using MemoryStream output = new();
        using (ZLibStream zlib = new(output, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            zlib.Write(data);
        }
        return output.ToArray();
    }

    private static void VerifyDefectCatalogHealthAndRestore(
        StorageRootSet parentRoots)
    {
        string healthBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-health");
        StorageRootSet healthRoots = StorageRootResolver.ResolveForTests(
            healthBase).Roots!;
        Guid healthFrameId = Guid.Parse("e4d63c51-532e-4d52-a41c-2212246a45e0");
        DefectSourceIdentity sourceIdentity = new(900, new string('c', 64));
        DefectRecipeSnapshot healthRecipe = DefectRecipeSnapshot.Create(
            healthFrameId,
            recipeRevision: 1,
            sourceIdentity,
            DefectRecipeItems());
        CatalogSnapshot healthCatalog = Snapshot(
            "health",
            DefectCatalogRow(healthFrameId, "health"));

        CatalogSessionOpenResult healthInitial = CatalogSession.Open(healthRoots);
        using (CatalogSession? initial = healthInitial.Session)
        {
            Check(healthInitial.IsSuccess, "defect_health_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "defect_health_initial_create");
                Check(initial.WriteDefectRecipe(healthRecipe).IsSuccess,
                    "defect_health_sidecar_first");
                Check(initial.Write(healthCatalog).IsSuccess,
                    "defect_health_catalog_after_sidecar");
                Check(initial.RemoveDefectRecipe(healthFrameId, 2).Error ==
                      DefectSidecarError.InvalidSnapshot,
                    "defect_health_remove_while_declared_blocked");
            }
        }

        CatalogSessionOpenResult healthyReopen = CatalogSession.Open(healthRoots);
        using (CatalogSession? healthy = healthyReopen.Session)
        {
            Check(healthyReopen.IsSuccess,
                "defect_health_restart_with_sidecar_opens");
            Check(healthy?.ReadDefectRecipe(healthFrameId).Snapshot?.RecipeRevision == 1,
                "defect_health_restart_reads_recipe");
        }

        string healthSidecarPath = DefectSidecarStore.PathFor(
            healthRoots,
            healthFrameId);
        byte[] healthyBytes = File.ReadAllBytes(healthSidecarPath);
        File.Delete(healthSidecarPath);
        CatalogSessionOpenResult missingOpen = CatalogSession.Open(healthRoots);
        missingOpen.Session?.Dispose();
        Check(missingOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              missingOpen.DefectSidecarError == DefectSidecarError.NotFound,
            "defect_health_missing_sidecar_blocks_library_open");

        File.WriteAllBytes(healthSidecarPath, healthyBytes);
        JsonObject damaged = JsonNode.Parse(healthyBytes)!.AsObject();
        damaged["recipeSHA256"] = new string('0', 64);
        File.WriteAllBytes(
            healthSidecarPath,
            CatalogJson.SerializeCanonical(damaged));
        CatalogSessionOpenResult damagedOpen = CatalogSession.Open(healthRoots);
        damagedOpen.Session?.Dispose();
        Check(damagedOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              damagedOpen.DefectSidecarError == DefectSidecarError.InvalidContent,
            "defect_health_damaged_sidecar_blocks_library_open");
        File.WriteAllBytes(healthSidecarPath, healthyBytes);

        string restoreBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-pending-restore");
        StorageRootSet restoreRoots = StorageRootResolver.ResolveForTests(
            restoreBase).Roots!;
        Guid selectedFrameId = Guid.Parse("9c7c5995-615b-4356-89de-e9440c36726c");
        Guid currentFrameId = Guid.Parse("d8f62712-9e03-46f6-b251-f66f0cd9a080");
        DateTimeOffset now = new(2026, 8, 10, 3, 0, 0, TimeSpan.Zero);
        string generationId = string.Empty;

        CatalogSessionOpenResult restoreInitial = CatalogSession.Open(restoreRoots);
        using (CatalogSession? restore = restoreInitial.Session)
        {
            Check(restoreInitial.IsSuccess, "defect_restore_initial_open");
            if (restore is not null)
            {
                Check(restore.ReadOrCreate().IsSuccess,
                    "defect_restore_initial_create");
                DefectRecipeSnapshot selectedRecipe = DefectRecipeSnapshot.Create(
                    selectedFrameId,
                    recipeRevision: 4,
                    sourceIdentity,
                    DefectRecipeItems());
                Check(restore.WriteDefectRecipe(selectedRecipe).IsSuccess &&
                      restore.Write(Snapshot(
                          "selected-defect",
                          DefectCatalogRow(selectedFrameId, "selected"))).IsSuccess,
                    "defect_restore_selected_generation_written");
                CatalogBackupCreateResult selectedBackup =
                    restore.CreateBackupForTesting(now);
                Check(selectedBackup.IsSuccess && selectedBackup.GenerationPath is not null,
                    "defect_restore_selected_generation_backed_up");
                generationId = selectedBackup.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selectedBackup.GenerationPath);

                DefectRecipeSnapshot currentRecipe = DefectRecipeSnapshot.Create(
                    currentFrameId,
                    recipeRevision: 7,
                    sourceIdentity,
                    [DefectRecipeItems()[1]]);
                Check(restore.WriteDefectRecipe(currentRecipe).IsSuccess &&
                      restore.Write(Snapshot(
                          "current-defect",
                          DefectCatalogRow(currentFrameId, "current"))).IsSuccess,
                    "defect_restore_current_generation_written");
                Check(restore.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "defect_restore_schedule_with_sidecars");
            }
        }

        CatalogSessionOpenResult restoredOpen = CatalogSession.Open(restoreRoots);
        using (CatalogSession? restored = restoredOpen.Session)
        {
            Check(restoredOpen.IsSuccess &&
                  restored?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied,
                "defect_restore_restart_applies_generation");
            Check(restored is not null &&
                  FrameOrder(restored.Read()) == selectedFrameId.ToString("D"),
                "defect_restore_catalog_and_sidecar_generation_match");
            Check(restored?.ReadDefectRecipe(selectedFrameId).Snapshot?.RecipeRevision == 4,
                "defect_restore_selected_recipe_restored");
            Check(restored?.ReadDefectRecipe(currentFrameId).Error ==
                  DefectSidecarError.NotFound,
                "defect_restore_replaces_previous_sidecar_set");
            Check(Directory.EnumerateDirectories(
                    restoreRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Select(CatalogBackupStore.ValidateGeneration)
                .Any(value =>
                    value.Snapshot?.ActiveRollId == "current-defect" &&
                    value.Manifest?.DefectFrameIds.SequenceEqual(
                        [currentFrameId.ToString("D")]) == true),
                "defect_restore_safety_generation_preserves_previous_sidecar");
        }
    }

    /// <summary>
    /// Defects directory의 두 번째 move가 끝난 뒤 catalog commit 전에 프로세스가 끊긴 상태입니다.
    /// 다음 시작은 이미 새 sidecar가 live에 있다는 사실을 검증하고 commit만 재개해야 하며,
    /// 서로 맞지 않는 현재 catalog/sidecar 조합으로 safety backup을 만들면 안 됩니다.
    /// </summary>
    private static void VerifyInterruptedDefectRestore(StorageRootSet parentRoots)
    {
        string restoreBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-interrupted-restore");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(restoreBase).Roots!;
        Guid selectedFrameId = Guid.Parse("ed0b9d5e-7652-4fdf-b6c7-802abc4a9a2e");
        Guid currentFrameId = Guid.Parse("6cae1efe-f8ff-42ea-aec1-96fb6372d4de");
        DefectSourceIdentity identity = new(900, new string('d', 64));
        DateTimeOffset now = new(2026, 8, 14, 4, 0, 0, TimeSpan.Zero);
        string pendingPath = string.Empty;
        CatalogPendingRestoreMarker? marker = null;

        CatalogSessionOpenResult initialOpen = CatalogSession.Open(roots);
        using (CatalogSession? initial = initialOpen.Session)
        {
            Check(initialOpen.IsSuccess, "interrupted_restore_initial_open");
            if (initial is null)
            {
                return;
            }

            Check(initial.ReadOrCreate().IsSuccess,
                "interrupted_restore_initial_create");
            DefectRecipeSnapshot selectedRecipe = DefectRecipeSnapshot.Create(
                selectedFrameId,
                recipeRevision: 4,
                identity,
                DefectRecipeItems());
            Check(initial.WriteDefectRecipe(selectedRecipe).IsSuccess &&
                  initial.Write(Snapshot(
                      "interrupted-selected",
                      DefectCatalogRow(selectedFrameId, "selected"))).IsSuccess,
                "interrupted_restore_selected_written");
            CatalogBackupCreateResult selectedBackup = initial.CreateBackupForTesting(now);
            Check(selectedBackup.IsSuccess && selectedBackup.GenerationPath is not null,
                "interrupted_restore_selected_backed_up");

            DefectRecipeSnapshot currentRecipe = DefectRecipeSnapshot.Create(
                currentFrameId,
                recipeRevision: 7,
                identity,
                [DefectRecipeItems()[1]]);
            Check(initial.WriteDefectRecipe(currentRecipe).IsSuccess &&
                  initial.Write(Snapshot(
                      "interrupted-current",
                      DefectCatalogRow(currentFrameId, "current"))).IsSuccess,
                "interrupted_restore_current_written");
            string generationId = selectedBackup.GenerationPath is null
                ? string.Empty
                : Path.GetFileName(selectedBackup.GenerationPath);
            Check(initial.ScheduleRestoreForTesting(generationId, now.AddMinutes(1)).IsSuccess,
                "interrupted_restore_scheduled");
        }

        Check(CatalogPendingRestoreFiles.TryReadMarker(roots, out CatalogPendingRestoreMarker read) &&
              CatalogBackupStore.ValidateGeneration(
                  pendingPath = Path.Combine(roots.PendingRestoreRoot, read.DirectoryName))
                  .Manifest is not null,
            "interrupted_restore_pending_copy_valid");
        if (string.IsNullOrEmpty(pendingPath) ||
            !CatalogPendingRestoreFiles.TryReadMarker(roots, out marker) ||
            CatalogBackupStore.ValidateGeneration(pendingPath).Manifest is not { } manifest)
        {
            return;
        }

        // 실제 apply는 이 시점에서 현재 state를 safety generation으로 먼저 남깁니다.
        Check(CatalogBackupStore.Create(
                roots,
                now.AddMinutes(2),
                CatalogBackupStore.DefaultRetentionCount).IsSuccess,
            "interrupted_restore_safety_generation_exists");
        CatalogPendingRestoreError prepared = CatalogDefectRestoreTransaction.TryPrepare(
            roots,
            pendingPath,
            marker.DirectoryName,
            manifest,
            out CatalogDefectRestoreTransaction transaction);
        Check(prepared == CatalogPendingRestoreError.None &&
              transaction.Activate() == CatalogPendingRestoreError.None,
            "interrupted_restore_defect_swap_completed_before_kill");
        CatalogPendingRestoreError recovery =
            CatalogDefectRestoreTransaction.RecoverInterruptedActivation(
                roots,
                marker.DirectoryName,
                manifest,
                out CatalogDefectRestoreTransaction? recoveredTransaction);
        Check(recovery == CatalogPendingRestoreError.None && recoveredTransaction is not null,
            "interrupted_restore_recognizes_completed_defect_swap");
        Check(DefectSidecarStore.ValidateCatalogDeclarations(
                roots,
                CatalogBackupStore.ValidateGeneration(pendingPath).Snapshot!).IsHealthy,
            "interrupted_restore_swapped_defects_match_pending_catalog");

        // 여기서 process가 죽었다고 가정합니다. rollback/cleanup/marker 갱신을 호출하지 않은 채
        // 새 session을 열어, scheduled marker와 .previous artifact만으로 재개하는지 확인합니다.
        CatalogSessionOpenResult resumedOpen = CatalogSession.Open(roots);
        using (CatalogSession? resumed = resumedOpen.Session)
        {
            Check(resumedOpen.IsSuccess &&
                  resumed?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied &&
                  resumed.PendingRestoreApplication.DidApplyRestore,
                "interrupted_restore_restart_resumes_catalog_commit");
            Check(resumed is not null &&
                  FrameOrder(resumed.Read()) == selectedFrameId.ToString("D") &&
                  resumed.ReadDefectRecipe(selectedFrameId).Snapshot?.RecipeRevision == 4,
                "interrupted_restore_catalog_and_defects_rejoin_selected_generation");
            Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(roots)) &&
                  !Directory.EnumerateDirectories(
                      roots.LibraryRoot,
                      $".defects-{marker.DirectoryName}.*",
                      SearchOption.TopDirectoryOnly).Any(),
                "interrupted_restore_cleans_swap_artifacts_after_commit");
        }
    }

    private static CatalogEntityRow DefectCatalogRow(Guid frameId, string label) =>
        new(frameId.ToString("D"), new JsonObject
        {
            ["label"] = label,
            ["hasDefectEdits"] = true,
        });

    private static void VerifyStoreLifecycle(StorageRootSet roots)
    {
        string catalogPath = roots.CatalogPath;

        // 없는 파일을 빈 라이브러리로 읽지 않습니다.
        CatalogReadResult absent = SqliteCatalogStore.Read(catalogPath);
        Check(!absent.IsSuccess, "store_absent_not_success");
        Check(absent.Error == CatalogStoreError.NotFound, "store_absent_not_found");
        Check(absent.Snapshot is null, "store_absent_no_partial_snapshot");

        CatalogSnapshot first = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"),
            Row("frame-3", "three"));
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_first_write");
        Check(File.Exists(catalogPath), "store_first_write_creates_file");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.IsSuccess, "store_reopen_success");
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3", "store_reopen_preserves_order");
        Check(FrameLabels(reopened) == "one,two,three", "store_reopen_preserves_payload");
        Check(reopened.Snapshot?.ActiveRollId == "roll-a", "store_reopen_preserves_active_roll");
        Check(reopened.Snapshot?.Rows(CatalogEntityTable.Rolls).Count == 0,
            "store_reopen_untouched_table_empty");

        // 자리 바꾸기입니다. position 이 UNIQUE 이므로 재배치 중 제약을 어기면 여기서 걸립니다.
        CatalogSnapshot reordered = Snapshot(
            "roll-a",
            Row("frame-3", "three"),
            Row("frame-1", "one-edited"),
            Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(reordered, catalogPath).IsSuccess, "store_reorder_write");
        CatalogReadResult afterReorder = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterReorder) == "frame-3,frame-1,frame-2", "store_reorder_order");
        Check(FrameLabels(afterReorder) == "three,one-edited,two", "store_reorder_payload");

        // 되돌리기도 같은 경로를 반대 방향으로 지납니다.
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_reorder_back_write");
        Check(FrameOrder(SqliteCatalogStore.Read(catalogPath)) == "frame-1,frame-2,frame-3",
            "store_reorder_back_order");

        CatalogSnapshot removed = Snapshot("roll-a", Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(removed, catalogPath).IsSuccess, "store_remove_write");
        CatalogReadResult afterRemove = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterRemove) == "frame-2", "store_remove_drops_rows");

        CatalogSnapshot cleared = Snapshot(activeRollId: null);
        Check(SqliteCatalogStore.Write(cleared, catalogPath).IsSuccess, "store_clear_write");
        CatalogReadResult afterClear = SqliteCatalogStore.Read(catalogPath);
        Check(afterClear.IsSuccess, "store_clear_reopen_success");
        Check(afterClear.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
            "store_clear_empties_table");
        Check(afterClear.Snapshot?.ActiveRollId is null, "store_clear_active_roll_null");

        Check(CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_valid_recovery_source");

        // Pooling 을 켜 두면 여기서 파일이 잠겨 backup 교체가 막힙니다.
        File.Delete(catalogPath);
        Check(!File.Exists(catalogPath), "store_no_lingering_file_handle");
    }

    private static void VerifyStoreRefusals(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "refusals.sqlite");

        CatalogSnapshot duplicated = Snapshot(
            null,
            Row("frame-1", "one"),
            Row("frame-1", "again"));
        CatalogWriteResult duplicateWrite = SqliteCatalogStore.Write(duplicated, catalogPath);
        Check(duplicateWrite.Error == CatalogStoreError.InvalidSnapshot,
            "store_rejects_duplicate_ids");
        Check(!File.Exists(catalogPath), "store_rejects_duplicate_ids_without_creating_file");

        CatalogSnapshot emptyId = Snapshot(null, Row(string.Empty, "one"));
        Check(SqliteCatalogStore.Write(emptyId, catalogPath).Error ==
            CatalogStoreError.InvalidSnapshot, "store_rejects_empty_id");

        Check(SqliteCatalogStore.Write(Snapshot(null, Row("frame-1", "one")), catalogPath)
            .IsSuccess, "store_refusal_fixture_write");

        // 물리 schema 가 미래 버전이면 읽지 않습니다.
        SetStorageVersion(catalogPath, 99);
        CatalogReadResult futureStorage = SqliteCatalogStore.Read(catalogPath);
        Check(futureStorage.Error == CatalogStoreError.UnsupportedStorageVersion,
            "store_rejects_future_storage_version");
        Check(futureStorage.ObservedVersion == 99, "store_reports_observed_storage_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_future_storage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), catalogPath).Error ==
            CatalogStoreError.UnsupportedStorageVersion,
            "store_refuses_write_over_future_storage_version");
        SetStorageVersion(catalogPath, 1);

        // macOS 파일은 논리 version 6 입니다. 조용히 읽지 않고 그 값을 보고합니다.
        SetCatalogVersion(catalogPath, 6);
        CatalogReadResult foreign = SqliteCatalogStore.Read(catalogPath);
        Check(foreign.Error == CatalogStoreError.UnsupportedCatalogVersion,
            "store_rejects_foreign_catalog_version");
        Check(foreign.ObservedVersion == 6, "store_reports_observed_catalog_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_foreign_catalog_is_not_recovery_source");
        SetCatalogVersion(catalogPath, CatalogSnapshot.CurrentCatalogVersion);
        Check(SqliteCatalogStore.Read(catalogPath).IsSuccess, "store_restored_fixture_reads");

        string garbagePath = Path.Combine(roots.LibraryRoot, "garbage.sqlite");
        File.WriteAllBytes(garbagePath, "this is not a database"u8.ToArray());
        CatalogReadResult garbage = SqliteCatalogStore.Read(garbagePath);
        Check(garbage.Error == CatalogStoreError.CorruptDatabase, "store_rejects_garbage_file");
        Check(garbage.Snapshot is null, "store_garbage_no_partial_snapshot");
        Check(!CatalogRecovery.IsValidCatalogSource(garbagePath),
            "store_garbage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), garbagePath).Error !=
            CatalogStoreError.None, "store_refuses_write_over_garbage_file");

        Check(SqliteCatalogStore.Read("library.sqlite").Error == CatalogStoreError.InvalidPath,
            "store_rejects_relative_path");
        Check(SqliteCatalogStore.Write(Snapshot(null), "library.sqlite").Error ==
            CatalogStoreError.InvalidPath, "store_write_rejects_relative_path");
    }

    private static void VerifyVerifiedCommit(StorageRootSet parentRoots)
    {
        string commitBase = Path.Combine(parentRoots.LocalApplicationDataRoot, "verified-commit");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(commitBase).Roots!;
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        using CatalogSession? session = opened.Session;
        Check(opened.IsSuccess, "commit_session_open");
        if (session is null)
        {
            return;
        }

        Check(session.ReadOrCreate().IsSuccess, "commit_initial_create");
        Check(!File.Exists(roots.CatalogBackupPath), "commit_initial_create_has_no_backup");

        CatalogSnapshot baseline = Snapshot("roll-a", Row("frame-1", "baseline"));
        CatalogSnapshot changed = Snapshot("roll-b", Row("frame-2", "changed"));
        CatalogSnapshot next = Snapshot("roll-c", Row("frame-3", "next"));
        Check(session.Write(baseline).IsSuccess, "commit_baseline_write");
        byte[] baselinePrimary = File.ReadAllBytes(roots.CatalogPath);
        Check(session.Write(changed).IsSuccess, "commit_changed_write");
        Check(File.Exists(roots.CatalogBackupPath), "commit_previous_primary_backup_exists");
        if (!File.Exists(roots.CatalogBackupPath))
        {
            return;
        }
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(baselinePrimary),
            "commit_previous_primary_backup_exact_bytes");
        Check(FrameLabels(SqliteCatalogStore.Read(roots.CatalogBackupPath)) == "baseline",
            "commit_previous_primary_backup_payload");

        byte[] backupBeforeNoOp = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(changed).IsSuccess, "commit_noop_success");
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(backupBeforeNoOp),
            "commit_noop_preserves_older_backup");

        byte[] changedPrimary = File.ReadAllBytes(roots.CatalogPath);
        CatalogWriteResult mismatch = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            readback: _ => CatalogReadResult.Success(
                Snapshot("roll-wrong", Row("frame-wrong", "wrong"))));
        Check(mismatch.Error == CatalogStoreError.ReadbackFailed,
            "commit_readback_mismatch_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_readback_mismatch_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_readback_mismatch_restores_payload");

        CatalogWriteResult writerFailure = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            writer: (_, path) =>
            {
                CatalogWriteResult substituted = SqliteCatalogStore.Write(
                    Snapshot("roll-external", Row("frame-external", "external")),
                    roots.CatalogBackupPath);
                if (!substituted.IsSuccess)
                {
                    return substituted;
                }
                File.WriteAllBytes(path, "partial write"u8.ToArray());
                throw new IOException("injected writer failure");
            });
        Check(writerFailure.Error == CatalogStoreError.IoFailure,
            "commit_writer_failure_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_writer_failure_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_writer_failure_restores_payload");

        CatalogWriteResult rollbackFailure = session.WriteForTesting(
            next,
            readback: _ => CatalogReadResult.Failure(CatalogStoreError.CorruptDatabase),
            restore: (_, _) => false);
        Check(rollbackFailure.Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_is_distinct");
        Check(FrameLabels(session.Read()) == "next",
            "commit_rollback_failure_does_not_claim_old_primary");
        byte[] unverifiedPrimary = File.ReadAllBytes(roots.CatalogPath);
        byte[] knownGoodBackup = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(baseline).Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_followup_write");
        Check(session.ReadOrCreate().Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_normal_open");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(unverifiedPrimary) &&
              File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(knownGoodBackup),
            "commit_blocked_followup_preserves_primary_and_backup");

        string absenceBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-absence");
        StorageRootSet absenceRoots = StorageRootResolver.ResolveForTests(absenceBase).Roots!;
        string journalPath = $"{absenceRoots.CatalogPath}-journal";
        CatalogWriteResult absenceMismatch = CatalogCommitVerifier.CommitForTesting(
            baseline,
            absenceRoots,
            writer: (_, path) =>
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllBytes(path, "partial database"u8.ToArray());
                File.WriteAllBytes(journalPath, "hot journal"u8.ToArray());
                return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
            });
        Check(absenceMismatch.Error == CatalogStoreError.IoFailure,
            "commit_absence_writer_error");
        Check(!File.Exists(absenceRoots.CatalogPath),
            "commit_absence_writer_restores_absence");
        Check(!File.Exists(journalPath),
            "commit_absence_writer_removes_journal");
        Check(!File.Exists(absenceRoots.CatalogBackupPath),
            "commit_absence_readback_does_not_create_backup");

        string guardedBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-guarded");
        StorageRootSet guardedRoots = StorageRootResolver.ResolveForTests(guardedBase).Roots!;
        CatalogSessionOpenResult guardedOpen = CatalogSession.Open(guardedRoots);
        using CatalogSession? guarded = guardedOpen.Session;
        Check(guardedOpen.IsSuccess, "commit_guarded_session_open");
        if (guarded is null)
        {
            return;
        }
        Check(guarded.ReadOrCreate().IsSuccess, "commit_guarded_create");
        Check(guarded.Write(baseline).IsSuccess, "commit_guarded_baseline");
        Check(guarded.Write(changed).IsSuccess, "commit_guarded_changed");
        byte[] guardedBackup = File.ReadAllBytes(guardedRoots.CatalogBackupPath);

        File.Delete(guardedRoots.CatalogPath);
        Check(guarded.ReadOrCreate().Error == CatalogStoreError.MissingAuthoritativeData,
            "commit_missing_primary_with_backup_blocks_empty_create");
        Check(!File.Exists(guardedRoots.CatalogPath),
            "commit_missing_primary_with_backup_preserves_absence");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_missing_primary_preserves_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath);
        byte[] corruptPrimary = "not a database"u8.ToArray();
        File.WriteAllBytes(guardedRoots.CatalogPath, corruptPrimary);
        CatalogWriteResult corruptWrite = guarded.Write(next);
        Check(corruptWrite.Error == CatalogStoreError.CorruptDatabase,
            "commit_corrupt_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(corruptPrimary),
            "commit_corrupt_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_corrupt_primary_does_not_overwrite_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath, overwrite: true);
        SetStorageVersion(guardedRoots.CatalogPath, 99);
        byte[] futurePrimary = File.ReadAllBytes(guardedRoots.CatalogPath);
        CatalogWriteResult futureWrite = guarded.Write(next);
        Check(futureWrite.Error == CatalogStoreError.UnsupportedStorageVersion,
            "commit_future_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(futurePrimary),
            "commit_future_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_future_primary_does_not_overwrite_backup");
    }

    private static void VerifyBackupGeneration(StorageRootSet parentRoots)
    {
        string backupBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "backup-generation");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(backupBase).Roots!;
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        using CatalogSession? session = opened.Session;
        Check(opened.IsSuccess, "backup_session_open");
        if (session is null)
        {
            return;
        }

        DateTimeOffset now = new(2026, 8, 9, 12, 0, 0, TimeSpan.Zero);
        Check(session.ReadOrCreate().IsSuccess, "backup_initial_create");
        Check(session.Write(Snapshot("backup-a", Row("frame-1", "one"))).IsSuccess,
            "backup_first_catalog_write");

        CatalogBackupCreateResult first = session.CreateBackupForTesting(now);
        Check(first.IsSuccess && first.Sequence == 1, "backup_first_generation_created");
        Check(first.GenerationPath is not null && Directory.Exists(first.GenerationPath),
            "backup_first_generation_visible");
        Check(first.GenerationPath is not null &&
              CatalogBackupStore.ValidateGeneration(first.GenerationPath).IsValid,
            "backup_first_generation_validates");

        CatalogBackupCreateResult rejected = session.CreateBackupForTesting(
            now.AddMinutes(1),
            beforeValidation: staging => File.AppendAllText(
                Path.Combine(staging, "library.json"),
                " "));
        Check(rejected.Error == CatalogBackupError.ValidationFailed,
            "backup_invalid_staging_not_published");
        Check(!Directory.EnumerateDirectories(
                roots.BackupRoot,
                "staging-*",
                SearchOption.TopDirectoryOnly).Any(),
            "backup_failed_staging_cleaned");

        Guid defectFrameId = Guid.Parse("5de22616-5b54-4739-949e-1c2bfd6cf3ef");
        JsonObject defectPayload = new()
        {
            ["label"] = "defect",
            ["hasDefectEdits"] = true,
        };
        CatalogSnapshot defectCatalog = Snapshot(
                "backup-defect",
                new CatalogEntityRow(defectFrameId.ToString("D"), defectPayload));
        Check(session.Write(defectCatalog).Error ==
              CatalogStoreError.MissingAuthoritativeData,
            "backup_defect_catalog_write_requires_sidecar_first");

        DefectSourceIdentity sourceIdentity = new(321, new string('b', 64));
        DefectRecipeSnapshot defectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 1,
            sourceIdentity,
            DefectRecipeItems());
        Check(session.WriteDefectRecipe(defectRecipe).IsSuccess,
            "backup_defect_sidecar_write");
        Check(session.Write(defectCatalog).IsSuccess,
            "backup_defect_catalog_write_after_sidecar");
        File.Delete(DefectSidecarStore.PathFor(roots, defectFrameId));
        Check(session.CreateBackupForTesting(now.AddMinutes(2)).Error ==
              CatalogBackupError.DefectSidecarUnavailable,
            "backup_defect_without_sidecar_blocked");

        DefectRecipeSnapshot recoveredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 2,
            sourceIdentity,
            DefectRecipeItems());
        Check(session.WriteDefectRecipe(recoveredRecipe).IsSuccess,
            "backup_defect_sidecar_recovered");
        CatalogBackupCreateResult withDefect =
            session.CreateBackupForTesting(now.AddMinutes(2));
        Check(withDefect.IsSuccess && withDefect.Sequence == 2,
            "backup_defect_generation_created");
        Check(withDefect.GenerationPath is not null &&
              File.Exists(Path.Combine(
                  withDefect.GenerationPath,
                  "defects",
                  DefectSidecarStore.FileName(defectFrameId))) &&
              CatalogBackupStore.ValidateGeneration(withDefect.GenerationPath).IsValid,
            "backup_defect_sidecar_copied_and_validated");
        if (withDefect.GenerationPath is not null)
        {
            File.AppendAllText(
                Path.Combine(
                    withDefect.GenerationPath,
                    "defects",
                    DefectSidecarStore.FileName(defectFrameId)),
                " ");
            Check(!CatalogBackupStore.ValidateGeneration(
                    withDefect.GenerationPath).IsValid,
                "backup_defect_sidecar_hash_damage_rejected");
        }

        Check(session.Write(Snapshot("backup-b", Row("frame-2", "two"))).IsSuccess,
            "backup_second_catalog_write");
        CatalogBackupCreateResult second = session.CreateBackupForTesting(now.AddMinutes(3));
        Check(second.IsSuccess && second.Sequence == 3, "backup_second_sequence");
        Check(session.Write(Snapshot("backup-c", Row("frame-3", "three"))).IsSuccess,
            "backup_third_catalog_write");
        CatalogBackupCreateResult third = session.CreateBackupForTesting(now.AddMinutes(4));
        Check(third.IsSuccess && third.Sequence == 4, "backup_third_sequence");

        string future = Path.Combine(roots.BackupRoot, "backup-future-version");
        Directory.CreateDirectory(future);
        File.WriteAllBytes(
            Path.Combine(future, "manifest.json"),
            CatalogJson.SerializeCanonical(new JsonObject
            {
                ["version"] = 99,
                ["sequence"] = JsonValue.Create((ulong)99),
            }));

        Check(session.Write(Snapshot("backup-d", Row("frame-4", "four"))).IsSuccess,
            "backup_fourth_catalog_write");
        CatalogBackupCreateResult fourth = session.CreateBackupForTesting(now.AddMinutes(5));
        Check(fourth.IsSuccess && fourth.Sequence == 100,
            "backup_future_manifest_keeps_sequence_monotonic");
        Check(Directory.Exists(future), "backup_future_generation_not_pruned");
        Check(first.GenerationPath is not null && !Directory.Exists(first.GenerationPath),
            "backup_retention_prunes_oldest_valid_generation");

        string[] valid = Directory.EnumerateDirectories(
                roots.BackupRoot,
                "backup-*",
                SearchOption.TopDirectoryOnly)
            .Where(path => CatalogBackupStore.ValidateGeneration(path).IsValid)
            .ToArray();
        Check(valid.Length == CatalogBackupStore.DefaultRetentionCount,
            "backup_retention_keeps_three_valid_generations");

        if (fourth.GenerationPath is not null)
        {
            File.AppendAllText(Path.Combine(fourth.GenerationPath, "library.json"), " ");
            Check(!CatalogBackupStore.ValidateGeneration(fourth.GenerationPath).IsValid,
                "backup_hash_damage_is_rejected");
        }
    }

    private static void VerifyPendingRestore(StorageRootSet parentRoots)
    {
        DateTimeOffset now = new(2026, 8, 9, 14, 0, 0, TimeSpan.Zero);

        string pinningBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-pinning");
        StorageRootSet pinningRoots = StorageRootResolver.ResolveForTests(
            pinningBase).Roots!;
        CatalogSessionOpenResult pinningOpen = CatalogSession.Open(pinningRoots);
        using (CatalogSession? pinning = pinningOpen.Session)
        {
            Check(pinningOpen.IsSuccess, "pending_pinning_session_open");
            if (pinning is not null)
            {
                Check(pinning.ReadOrCreate().IsSuccess,
                    "pending_pinning_initial_create");
                Check(pinning.Write(Snapshot(
                        "restore-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_pinning_selected_write");
                CatalogBackupCreateResult selected =
                    pinning.CreateBackupForTesting(now);
                Check(selected.IsSuccess && selected.GenerationPath is not null,
                    "pending_pinning_source_created");
                Check(pinning.Write(Snapshot(
                        "restore-live",
                        Row("frame-live", "live"))).IsSuccess,
                    "pending_pinning_live_write");

                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                CatalogPendingRestoreScheduleResult scheduled =
                    pinning.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1));
                Check(scheduled.IsSuccess,
                    "pending_pinning_schedule_success");
                Check(FrameLabels(pinning.Read()) == "live",
                    "pending_pinning_does_not_replace_live_session");

                if (selected.GenerationPath is not null &&
                    Directory.Exists(selected.GenerationPath))
                {
                    Directory.Delete(selected.GenerationPath, recursive: true);
                }
                bool markerRead = CatalogPendingRestoreFiles.TryReadMarker(
                    pinningRoots,
                    out CatalogPendingRestoreMarker pinnedMarker);
                Check(markerRead, "pending_pinning_marker_readback");
                string pinnedPath = markerRead
                    ? Path.Combine(
                        pinningRoots.PendingRestoreRoot,
                        pinnedMarker.DirectoryName)
                    : string.Empty;
                Check(markerRead &&
                      CatalogBackupStore.ValidateGeneration(pinnedPath).IsValid,
                    "pending_pinning_survives_source_removal");

                Check(pinning.CancelScheduledRestore().IsSuccess,
                    "pending_pinning_cancel_success");
                Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(
                        pinningRoots)),
                    "pending_pinning_cancel_removes_marker");
                Check(string.IsNullOrEmpty(pinnedPath) || !Directory.Exists(pinnedPath),
                    "pending_pinning_cancel_removes_copy");
            }
        }

        string applyBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-apply");
        StorageRootSet applyRoots = StorageRootResolver.ResolveForTests(applyBase).Roots!;
        CatalogSessionOpenResult applyInitialOpen = CatalogSession.Open(applyRoots);
        using (CatalogSession? initial = applyInitialOpen.Session)
        {
            Check(applyInitialOpen.IsSuccess, "pending_apply_initial_session_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_apply_initial_create");
                Check(initial.Write(Snapshot(
                        "restore-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_apply_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "restore-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_apply_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_apply_schedule_success");
                Check(FrameLabels(initial.Read()) == "current",
                    "pending_apply_current_visible_until_restart");
            }
        }

        CatalogSessionOpenResult appliedOpen = CatalogSession.Open(applyRoots);
        using (CatalogSession? applied = appliedOpen.Session)
        {
            Check(appliedOpen.IsSuccess, "pending_apply_restart_open");
            if (applied is not null)
            {
                Check(applied.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied &&
                      applied.PendingRestoreApplication.DidApplyRestore,
                    "pending_apply_reports_application");
                Check(FrameLabels(applied.Read()) == "selected",
                    "pending_apply_selected_generation_visible");
                Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(applyRoots)),
                    "pending_apply_marker_cleaned");
                Check(!Directory.Exists(applyRoots.PendingRestoreRoot) ||
                      !Directory.EnumerateDirectories(
                          applyRoots.PendingRestoreRoot,
                          "restore-*",
                          SearchOption.TopDirectoryOnly).Any(),
                    "pending_apply_copy_cleaned");
                Check(Directory.EnumerateDirectories(
                        applyRoots.BackupRoot,
                        "backup-*",
                        SearchOption.TopDirectoryOnly)
                    .Select(CatalogBackupStore.ValidateGeneration)
                    .Any(validation =>
                        validation.Snapshot?.ActiveRollId == "restore-current"),
                    "pending_apply_preserves_current_as_safety_generation");
            }
        }

        string futureBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-future");
        StorageRootSet futureRoots = StorageRootResolver.ResolveForTests(futureBase).Roots!;
        CatalogSessionOpenResult futureInitialOpen = CatalogSession.Open(futureRoots);
        using (CatalogSession? initial = futureInitialOpen.Session)
        {
            Check(futureInitialOpen.IsSuccess, "pending_future_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_future_initial_create");
                Check(initial.Write(Snapshot(
                        "future-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_future_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "future-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_future_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_future_schedule_success");
            }
        }
        SetStorageVersion(futureRoots.CatalogPath, 99);
        byte[] futureBytes = File.ReadAllBytes(futureRoots.CatalogPath);
        CatalogSessionOpenResult blockedFuture = CatalogSession.Open(futureRoots);
        blockedFuture.Session?.Dispose();
        Check(blockedFuture.Error == CatalogSessionError.PendingRestoreFailed &&
              blockedFuture.PendingRestoreError ==
                  CatalogPendingRestoreError.UnsupportedCurrentCatalog &&
              blockedFuture.ObservedVersion == 99,
            "pending_future_blocks_downgrade");
        Check(File.ReadAllBytes(futureRoots.CatalogPath).SequenceEqual(futureBytes),
            "pending_future_preserves_primary_bytes");
        bool futureMarkerRead = CatalogPendingRestoreFiles.TryReadMarker(
            futureRoots,
            out CatalogPendingRestoreMarker futureMarker);
        Check(futureMarkerRead &&
              Directory.Exists(Path.Combine(
                  futureRoots.PendingRestoreRoot,
                  futureMarker.DirectoryName)),
            "pending_future_preserves_marker_and_copy");

        string cleanupBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-cleanup");
        StorageRootSet cleanupRoots = StorageRootResolver.ResolveForTests(
            cleanupBase).Roots!;
        CatalogSessionOpenResult cleanupInitialOpen = CatalogSession.Open(cleanupRoots);
        using (CatalogSession? initial = cleanupInitialOpen.Session)
        {
            Check(cleanupInitialOpen.IsSuccess, "pending_cleanup_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_cleanup_initial_create");
                Check(initial.Write(Snapshot(
                        "cleanup-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_cleanup_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "cleanup-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_cleanup_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_cleanup_schedule_success");
            }
        }

        CatalogPendingRestoreCleanup markerFailure = new(
            RemoveDirectory: path =>
            {
                if (!CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                        path,
                        cleanupRoots.PendingRestoreRoot,
                        "restore-",
                        requireValidGeneration: true))
                {
                    throw new IOException("injected cleanup setup failure");
                }
            },
            RemoveMarker: _ => throw new IOException(
                "injected marker delete failure"));
        CatalogSessionOpenResult cleanupPendingOpen = CatalogSession.OpenForTesting(
            cleanupRoots,
            markerFailure);
        int validGenerationCount;
        using (CatalogSession? cleanupPending = cleanupPendingOpen.Session)
        {
            Check(cleanupPendingOpen.IsSuccess,
                "pending_cleanup_failure_still_opens_session");
            Check(cleanupPending?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.CleanupPending &&
                  cleanupPending.PendingRestoreApplication.DidApplyRestore,
                "pending_cleanup_failure_reports_applied_cleanup_pending");
            Check(cleanupPending is not null &&
                  FrameLabels(cleanupPending.Read()) == "selected",
                "pending_cleanup_failure_keeps_applied_catalog");
            Check(CatalogPendingRestoreFiles.TryReadMarker(
                    cleanupRoots,
                    out CatalogPendingRestoreMarker appliedMarker) &&
                  appliedMarker.Phase == CatalogPendingRestorePhase.Applied,
                "pending_cleanup_failure_persists_applied_fence");
            validGenerationCount = Directory.EnumerateDirectories(
                    cleanupRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Count(path => CatalogBackupStore.ValidateGeneration(path).IsValid);
        }

        CatalogSessionOpenResult cleanupRetryOpen = CatalogSession.Open(cleanupRoots);
        using (CatalogSession? cleanupRetry = cleanupRetryOpen.Session)
        {
            Check(cleanupRetryOpen.IsSuccess,
                "pending_cleanup_retry_session_open");
            Check(cleanupRetry?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.CleanupOnly &&
                  !cleanupRetry.PendingRestoreApplication.DidApplyRestore,
                "pending_cleanup_retry_is_cleanup_only");
            Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(cleanupRoots)),
                "pending_cleanup_retry_removes_marker");
            Check(Directory.EnumerateDirectories(
                    cleanupRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Count(path => CatalogBackupStore.ValidateGeneration(path).IsValid) ==
                validGenerationCount,
                "pending_cleanup_retry_does_not_create_safety_generation");
        }
    }

    private static JsonObject FrameRecord()
    {
        return new JsonObject
        {
            ["id"] = "frame-1",
            ["rawScanPath"] = @"C:\scans\roll-01\IMG_0001.tif",
            ["infraredScanPath"] = @"C:\scans\roll-01\IMG_0001.ir.tif",
            ["customDisplayName"] = "Roll 01 / 1",
            ["sourceKind"] = "scanner",
            ["filmType"] = "colorNegative",
            ["sourceMetadata"] = new JsonObject
            {
                ["fileBytes"] = 123456UL,
                ["pixelWidth"] = 6400U,
                ["pixelHeight"] = 4200U,
                ["samplesPerPixel"] = 3,
                ["bitsPerSample"] = 16,
                ["sampleFormat"] = 1,
                ["orientation"] = 1,
            },
            ["futureFrameValue"] = "preserve-me",
            ["params"] = new JsonObject
            {
                ["filmType"] = "colorNegative",
                ["baseEstimationMode"] = "preset",
                ["manualBaseRGB"] = new JsonArray(0.21, 0.22, 0.23),
                ["filmStockDminID"] = "kodak-portra-400",
                ["lightSourceProfileID"] = "v850-led",
                ["scannerProfileID"] = "noritsu__color-nega__kodak-portra-400",
                ["exposure"] = 0.5,
                ["curveShadows"] = -0.25,
                ["pointCurves"] = new JsonObject
                {
                    ["rgb"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 1.0, ["y"] = 1.0 },
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.0 },
                        new JsonObject { ["x"] = 0.45, ["y"] = 0.52 },
                    },
                    ["red"] = new JsonArray
                    {
                        new JsonObject { ["x"] = 0.0, ["y"] = 0.03 },
                        new JsonObject { ["x"] = 1.0, ["y"] = 0.97 },
                    },
                    ["green"] = new JsonArray(),
                    ["blue"] = new JsonArray(),
                },
                ["colorMixer"] = new JsonObject
                {
                    ["hue"] = new JsonArray(0.1, -0.2),
                    ["saturation"] = new JsonArray(0.3),
                    ["luminance"] = new JsonArray(-0.4),
                },
                ["imageTransform"] = new JsonObject
                {
                    ["rotation"] = 1,
                    ["flipHorizontal"] = true,
                    ["flipVertical"] = false,
                    ["cropRect"] = new JsonArray(0.1, 0.2, 0.7, 0.6),
                    ["straightenAngle"] = 1.5,
                    ["cropAspect"] = 1.5,
                },
                ["grain"] = 0.35,
                ["sharpness"] = 0.45,
                ["halation"] = 0.20,
                ["clarity"] = -0.15,
                ["vignette"] = 0.25,
                ["noiseReduction"] = 0.60,
                ["noiseReductionLuma"] = 0.70,
                ["noiseReductionChroma"] = 0.40,
                ["noiseReductionDarkTone"] = 0.55,
                ["noiseReductionDetail"] = 0.65,
                ["noiseReductionGrainProtect"] = 0.30,
                ["unknownAdjustment"] = new JsonObject { ["value"] = 7 },
            },
        };
    }

    private static LibraryFrameReadResult ReadFrame(JsonObject frameRecord)
    {
        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(frameRecord));
        return LibraryFrameReader.Read(document.RootElement);
    }

    private static void VerifyLibraryFrameProjection()
    {
        LibraryFrameReadResult read = ReadFrame(FrameRecord());
        Check(read.IsSuccess, "library_frame_read_success");
        if (read.Frame is not { } frame)
        {
            return;
        }

        Check(frame.Id == "frame-1", "library_frame_id");
        Check(frame.SourcePath == @"C:\scans\roll-01\IMG_0001.tif", "library_frame_source_path");
        Check(frame.InfraredPath == @"C:\scans\roll-01\IMG_0001.ir.tif",
            "library_frame_infrared_source_path");
        Check(
            frame.SourceMetadata == new LibrarySourceMetadata(123456, 6400, 4200, 3, 16, 1, 1),
            "library_frame_source_metadata");
        Check(frame.EffectiveDisplayName == "Roll 01 / 1", "library_frame_display_name");
        Check(frame.Route.FilmType == FilmType.ColorNegative, "library_frame_route_film_type");
        Check(frame.CanDevelop, "library_frame_preset_with_stock_can_develop");
        Check(frame.ManualBase == new ManualBaseRgb(0.21, 0.22, 0.23), "library_frame_manual_base");
        Check(frame.Base.Mode == BaseEstimationMode.Preset, "library_frame_base_mode");
        Check(frame.Base.FilmStockDminId == "kodak-portra-400", "library_frame_film_stock_id");
        Check(frame.Base.LightSourceProfileId == "v850-led", "library_frame_light_source_id");
        Check(frame.Base.ScannerProfileId == "noritsu__color-nega__kodak-portra-400", "library_frame_scanner_profile_id");
        Check(frame.Tone.Exposure == 0.5, "library_frame_exposure");
        Check(frame.Tone.CurveShadows == -0.25, "library_frame_curve_shadows");
        Check(frame.PointCurves.Rgb.Count == 3, "library_frame_point_curve_rgb_count");
        Check(frame.PointCurves.Rgb[0] == new PointCurvePoint(0.0, 0.0),
            "library_frame_point_curve_sorts_rgb");
        Check(frame.PointCurves.Rgb[1] == new PointCurvePoint(0.45, 0.52),
            "library_frame_point_curve_rgb_middle");
        Check(frame.PointCurves.Red.Count == 2 && frame.PointCurves.Green.Count == 0 &&
                frame.PointCurves.Blue.Count == 0,
            "library_frame_point_curve_channel_shapes");
        Check(frame.ColorMixer.Hue[0] == 0.1 && frame.ColorMixer.Hue[1] == -0.2 &&
                frame.ColorMixer.Hue[2] == 0.0 && frame.ColorMixer.Saturation[0] == 0.3 &&
                frame.ColorMixer.Luminance[0] == -0.4,
            "library_frame_color_mixer_normalizes_mac_shape");
        Check(frame.ColorGrading == ColorGradingRecipe.Identity,
            "library_frame_missing_color_grading_defaults_to_identity");
        Check(frame.ColorModel == ColorModelRecipe.Identity,
            "library_frame_missing_color_model_defaults_to_identity");
        Check(!frame.AutoLevels && !frame.AutoNeutralBalance,
            "library_frame_missing_scene_correction_defaults_off");
        Check(frame.DevelopTarget == DevelopTarget.Main,
            "library_frame_missing_develop_target_defaults_main");
        Check(frame.ImageTransform == new ImageTransformRecipe(
                ImageRotation.Degrees90,
                true,
                false,
                new ImageCropRect(0.1, 0.2, 0.7, 0.6),
                1.5,
                1.5),
            "library_frame_image_transform_projection");
        Check(frame.Texture == new TextureRecipe(0.35, 0.45, 0.20, -0.15, 0.25),
            "library_frame_texture_projection");
        Check(frame.NoiseReduction == new NoiseReductionRecipe(0.60, 0.70, 0.40, 0.55, 0.65, 0.30),
            "library_frame_noise_reduction_projection");
        ColorGradingRecipe colorGrading = new(
            new ColorGradeRegionRecipe(45.0, 0.2, -0.1),
            new ColorGradeRegionRecipe(180.0, 0.4, 0.1),
            new ColorGradeRegionRecipe(300.0, 0.6, 0.2),
            0.35,
            -0.25);
        LibraryFrameWriteResult writtenColorGrading = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorGrading: colorGrading));
        Check(
            writtenColorGrading.IsSuccess &&
                ReadFrame(writtenColorGrading.FrameRecord!).Frame?.ColorGrading == colorGrading,
            "library_frame_color_grading_write_round_trip");
        ColorModelRecipe colorModel = new(
            0.25, -0.2, 0.3, 0.4, -0.1, 0.1, -0.15, 0.2);
        LibraryFrameWriteResult writtenColorModel = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorModel: colorModel,
                AutoLevels: true,
                AutoNeutralBalance: true,
                DevelopTarget: DevelopTarget.Rescue));
        Check(
            writtenColorModel.IsSuccess &&
                ReadFrame(writtenColorModel.FrameRecord!).Frame is { } correctedFrame &&
                correctedFrame.ColorModel == colorModel &&
                correctedFrame.AutoLevels && correctedFrame.AutoNeutralBalance &&
                correctedFrame.DevelopTarget == DevelopTarget.Rescue,
            "library_frame_color_model_scene_correction_and_target_write_round_trip");
        // 없는 톤 키는 macOS 와 같이 0 입니다.
        Check(frame.Tone.Contrast == 0.0, "library_frame_missing_tone_is_zero");

        // Preset resolver가 아직 없으면 manual base가 있어도 Auto로 바꾸어 추정하지 않습니다.
        JsonObject withoutBase = FrameRecord();
        withoutBase["params"]!.AsObject().Remove("manualBaseRGB");
        LibraryFrameReadResult noBase = ReadFrame(withoutBase);
        Check(noBase.IsSuccess, "library_frame_missing_base_still_reads");
        Check(noBase.Frame?.ManualBase is null, "library_frame_missing_base_is_absent");
        Check(noBase.Frame?.CanDevelop == true, "library_frame_preset_does_not_require_manual_base");

        JsonObject defaultBase = FrameRecord();
        JsonObject defaultBaseParams = defaultBase["params"]!.AsObject();
        defaultBaseParams.Remove("baseEstimationMode");
        defaultBaseParams.Remove("filmStockDminID");
        defaultBaseParams.Remove("lightSourceProfileID");
        defaultBaseParams.Remove("scannerProfileID");
        Check(ReadFrame(defaultBase).Frame?.Base == BaseRecipe.Auto,
            "library_frame_missing_base_recipe_defaults_to_auto");
        Check(ReadFrame(defaultBase).Frame?.CanDevelop == true,
            "library_frame_default_auto_can_develop");

        JsonObject withoutPointCurves = FrameRecord();
        withoutPointCurves["params"]!.AsObject().Remove("pointCurves");
        PointCurveRecipe? defaultPointCurves = ReadFrame(withoutPointCurves).Frame?.PointCurves;
        Check(defaultPointCurves is not null &&
                defaultPointCurves.Rgb.Count == 0 && defaultPointCurves.Red.Count == 0 &&
                defaultPointCurves.Green.Count == 0 && defaultPointCurves.Blue.Count == 0,
            "library_frame_missing_point_curves_defaults_to_identity");

        JsonObject withoutName = FrameRecord();
        withoutName.Remove("customDisplayName");
        Check(
            ReadFrame(withoutName).Frame?.EffectiveDisplayName == "IMG_0001.tif",
            "library_frame_falls_back_to_file_name");

        VerifyLibraryFrameRefusals();
        VerifyLibraryFrameWriting();
    }

    private static void VerifyLocalDodgeBurnPersistence()
    {
        Guid brushId = Guid.Parse("00000000-0000-0000-0000-000000000101");
        Guid polygonId = Guid.Parse("00000000-0000-0000-0000-000000000102");
        LocalDodgeBurnAdjustment[] recipe =
        [
            new(
                brushId,
                LocalDodgeBurnMode.Dodge,
                0.45,
                true,
                LocalDodgeBurnMask.Brush(
                [
                    new LocalDodgeBurnStroke(
                        [new(-0.1, 0.25), new(0.65, 1.1)],
                        0.06,
                        0.03),
                ])),
            new(
                polygonId,
                LocalDodgeBurnMode.Burn,
                0.7,
                false,
                LocalDodgeBurnMask.Polygon(
                    [new(0.1, 0.1), new(0.9, 0.2), new(0.5, 0.85)],
                    0.2)),
        ];

        LibraryFrameWriteResult written = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(
                ToneAdjustment.Neutral,
                null,
                LocalDodgeBurn: recipe));
        LibraryFrameReadResult reread = written.FrameRecord is { } record
            ? ReadFrame(record)
            : default;
        Check(
            written.IsSuccess && reread.IsSuccess && reread.Frame?.LocalDodgeBurn.Count == 2 &&
            reread.Frame.LocalDodgeBurn[0].Id == brushId &&
            reread.Frame.LocalDodgeBurn[0].Mask.Strokes[0].Points[0] == new LocalDodgeBurnPoint(-0.1, 0.25) &&
            reread.Frame.LocalDodgeBurn[1].Id == polygonId &&
            !reread.Frame.LocalDodgeBurn[1].IsEnabled &&
            reread.Frame.LocalDodgeBurn[1].Mask.Points.Count == 3,
            "library_frame_local_dodge_burn_round_trip");

        LibraryFrameWriteResult ratingWrite = LibraryFrameWriter.Apply(
            FrameRecord(),
            new LibraryFrameEdit(ToneAdjustment.Neutral, null, Rating: 4));
        LibraryFrameReadResult ratingRead = ratingWrite.FrameRecord is { } ratingRecord
            ? ReadFrame(ratingRecord)
            : default;
        Check(
            ratingWrite.IsSuccess && ratingRead.IsSuccess && ratingRead.Frame?.Rating == 4,
            "library_frame_rating_round_trip");
        Check(
            ReadFrame(FrameRecord()).Frame?.Rating == 0,
            "library_frame_rating_defaults_to_zero");
        JsonObject outOfRange = FrameRecord();
        outOfRange["rating"] = 7;
        Check(
            ReadFrame(outOfRange).Error == LibraryFrameError.InvalidRating &&
            !LibraryFrameWriter.Apply(
                FrameRecord(),
                new LibraryFrameEdit(ToneAdjustment.Neutral, null, Rating: -1)).IsSuccess,
            "library_frame_rating_rejects_out_of_range");

        JsonObject malformed = FrameRecord();
        malformed["params"]!["localDodgeBurn"] = new JsonArray
        {
            new JsonObject { ["mode"] = "dodge", ["amount"] = 0.5 },
        };
        Check(
            ReadFrame(malformed).Error == LibraryFrameError.InvalidLocalDodgeBurn,
            "library_frame_rejects_local_dodge_burn_without_mask");
    }

    private static void VerifyLibraryFrameRefusals()
    {
        JsonObject missingId = FrameRecord();
        missingId.Remove("id");
        Check(
            ReadFrame(missingId).Error == LibraryFrameError.MissingId,
            "library_frame_rejects_missing_id");

        JsonObject blankId = FrameRecord();
        blankId["id"] = "   ";
        Check(
            ReadFrame(blankId).Error == LibraryFrameError.InvalidId,
            "library_frame_rejects_blank_id");

        JsonObject missingPath = FrameRecord();
        missingPath.Remove("rawScanPath");
        Check(
            ReadFrame(missingPath).Error == LibraryFrameError.MissingSourcePath,
            "library_frame_rejects_missing_source_path");

        // 상대 경로는 무엇을 기준으로 푸는지가 catalog 에 없습니다.
        JsonObject relativePath = FrameRecord();
        relativePath["rawScanPath"] = @"scans\IMG_0001.tif";
        Check(
            ReadFrame(relativePath).Error == LibraryFrameError.InvalidSourcePath,
            "library_frame_rejects_relative_source_path");

        JsonObject relativeInfraredPath = FrameRecord();
        relativeInfraredPath["infraredScanPath"] = @"scans\IMG_0001.ir.tif";
        Check(
            ReadFrame(relativeInfraredPath).Error == LibraryFrameError.InvalidInfraredPath,
            "library_frame_rejects_relative_infrared_path");

        JsonObject malformedMetadata = FrameRecord();
        malformedMetadata["sourceMetadata"]!.AsObject()["pixelWidth"] = 0;
        Check(
            ReadFrame(malformedMetadata).Error == LibraryFrameError.InvalidSourceMetadata,
            "library_frame_rejects_invalid_source_metadata");

        JsonObject sameInfraredPath = FrameRecord();
        sameInfraredPath["infraredScanPath"] = sameInfraredPath["rawScanPath"]!.GetValue<string>();
        Check(
            ReadFrame(sameInfraredPath).Error == LibraryFrameError.InvalidInfraredPath,
            "library_frame_rejects_ir_path_equal_to_rgb_path");

        JsonObject shortBase = FrameRecord();
        shortBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, 0.2);
        Check(
            ReadFrame(shortBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_two_channel_base");

        JsonObject textBase = FrameRecord();
        textBase["params"]!["manualBaseRGB"] = new JsonArray(0.2, "0.2", 0.2);
        Check(
            ReadFrame(textBase).Error == LibraryFrameError.InvalidManualBase,
            "library_frame_rejects_non_numeric_base");

        JsonObject invalidBaseMode = FrameRecord();
        invalidBaseMode["params"]!["baseEstimationMode"] = "guessed";
        Check(
            ReadFrame(invalidBaseMode).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_unknown_base_mode");

        JsonObject invalidBaseIdentifier = FrameRecord();
        invalidBaseIdentifier["params"]!["filmStockDminID"] = " ";
        Check(
            ReadFrame(invalidBaseIdentifier).Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_rejects_blank_base_identifier");

        JsonObject invalidImageTransform = FrameRecord();
        invalidImageTransform["params"]!["imageTransform"]!["cropRect"] =
            new JsonArray(0.7, 0.2, 0.4, 0.6);
        Check(
            ReadFrame(invalidImageTransform).Error == LibraryFrameError.InvalidImageTransform,
            "library_frame_rejects_out_of_bounds_crop");

        JsonObject invalidNoiseReduction = FrameRecord();
        invalidNoiseReduction["params"]!["noiseReductionDetail"] = 1.1;
        Check(
            ReadFrame(invalidNoiseReduction).Error == LibraryFrameError.InvalidNoiseReduction,
            "library_frame_rejects_out_of_range_noise_reduction");

        JsonObject invalidPointCurveShape = FrameRecord();
        invalidPointCurveShape["params"]!["pointCurves"]!["rgb"] = new JsonObject();
        Check(
            ReadFrame(invalidPointCurveShape).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_array");

        JsonObject invalidPointCurveCoordinate = FrameRecord();
        invalidPointCurveCoordinate["params"]!["pointCurves"]!["red"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.25, ["y"] = "0.25" },
        };
        Check(
            ReadFrame(invalidPointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_non_numeric_coordinate");

        JsonObject duplicatePointCurveCoordinate = FrameRecord();
        duplicatePointCurveCoordinate["params"]!["pointCurves"]!["blue"] = new JsonArray
        {
            new JsonObject { ["x"] = 0.5, ["y"] = 0.4 },
            new JsonObject { ["x"] = 0.5, ["y"] = 0.6 },
        };
        Check(
            ReadFrame(duplicatePointCurveCoordinate).Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_rejects_point_curve_duplicate_x");

        // 있는데 수가 아니면 조용히 0 으로 만들지 않습니다.
        JsonObject textTone = FrameRecord();
        textTone["params"]!["exposure"] = "0.5";
        Check(
            ReadFrame(textTone).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_rejects_non_numeric_tone");

        JsonObject missingParameters = FrameRecord();
        missingParameters.Remove("params");
        Check(
            ReadFrame(missingParameters).Error == LibraryFrameError.MissingParameters,
            "library_frame_rejects_missing_parameters");

        // route 거부는 그대로 전달되고 어느 쪽이 문제인지 구별됩니다.
        JsonObject brokenRoute = FrameRecord();
        brokenRoute["params"]!["filmType"] = "colorPositive";
        LibraryFrameReadResult routeFailure = ReadFrame(brokenRoute);
        Check(
            routeFailure.Error == LibraryFrameError.InvalidDevelopRoute,
            "library_frame_reports_route_failure");
        Check(
            routeFailure.RouteError == DevelopRouteError.MismatchedFilmType,
            "library_frame_preserves_route_error");
        Check(routeFailure.Frame is null, "library_frame_no_partial_snapshot");
    }

    private static void VerifyLibraryFrameWriting()
    {
        JsonObject original = FrameRecord();
        LibraryFrameEdit edit = new(
            new ToneAdjustment(
                1.25,
                -0.5,
                0.1,
                0.2,
                0.3,
                0.4,
                0.5,
                -0.6,
                0.7,
                -0.8,
                0.9),
            new ManualBaseRgb(0.31, 0.32, 0.33));

        LibraryFrameWriteResult write = LibraryFrameWriter.Apply(original, edit);
        Check(write.IsSuccess, "library_frame_write_success");
        if (write.FrameRecord is not { } updated)
        {
            return;
        }

        Check(
            original["params"]!["exposure"]!.GetValue<double>() == 0.5,
            "library_frame_write_leaves_input_alone");
        Check(
            updated["futureFrameValue"]!.GetValue<string>() == "preserve-me",
            "library_frame_write_preserves_unknown_frame_field");
        Check(
            updated["params"]!["unknownAdjustment"]!["value"]!.GetValue<int>() == 7,
            "library_frame_write_preserves_unknown_parameter_field");

        LibraryFrameReadResult reread = ReadFrame(updated);
        Check(reread.IsSuccess, "library_frame_write_round_trip");
        Check(reread.Frame?.Tone == edit.Tone, "library_frame_write_tone_round_trip");
        Check(
            updated["params"]!["density"]!.GetValue<double>() == 0.5 &&
                updated["params"]!["highlight"]!.GetValue<double>() == -0.6 &&
                updated["params"]!["shadow"]!.GetValue<double>() == 0.7 &&
                updated["params"]!["whites"]!.GetValue<double>() == -0.8 &&
                updated["params"]!["blacks"]!.GetValue<double>() == 0.9,
            "library_frame_write_basic_tone_names");
        Check(reread.Frame?.ManualBase == edit.ManualBase, "library_frame_write_base_round_trip");
        ImageTransformRecipe imageTransform = new(
            ImageRotation.Degrees270,
            true,
            true,
            new ImageCropRect(0.15, 0.10, 0.70, 0.75),
            -2.25,
            4.0 / 3.0);
        LibraryFrameWriteResult imageTransformWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, ImageTransform: imageTransform));
        Check(
            imageTransformWrite.IsSuccess &&
                ReadFrame(imageTransformWrite.FrameRecord!).Frame?.ImageTransform == imageTransform,
            "library_frame_image_transform_write_round_trip");
        TextureRecipe texture = new(0.25, 0.55, 0.15, 0.30, -0.20);
        NoiseReductionRecipe noiseReduction = new(0.65, 0.75, 0.45, 0.60, 0.80, 0.35);
        LibraryFrameWriteResult postProcessingWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(
                edit.Tone,
                edit.ManualBase,
                Texture: texture,
                NoiseReduction: noiseReduction));
        Check(
            postProcessingWrite.IsSuccess &&
                ReadFrame(postProcessingWrite.FrameRecord!).Frame is { } postProcessingFrame &&
                postProcessingFrame.Texture == texture &&
                postProcessingFrame.NoiseReduction == noiseReduction,
            "library_frame_post_processing_write_round_trip");
        Check(reread.Frame?.Base == new BaseRecipe(
                BaseEstimationMode.Preset,
                "kodak-portra-400",
                "v850-led",
                "noritsu__color-nega__kodak-portra-400"),
            "library_frame_write_preserves_base_recipe_when_not_edited");
        Check(reread.Frame?.PointCurves.Rgb.Count == 3,
            "library_frame_write_preserves_point_curves_when_not_edited");
        Check(reread.Frame?.ColorMixer.Hue[0] == 0.1 && reread.Frame.ColorMixer.Hue[2] == 0.0,
            "library_frame_write_preserves_color_mixer_when_not_edited");

        BaseRecipe manualRecipe = new(
            BaseEstimationMode.Manual,
            "kodak-portra-400",
            null,
            null);
        LibraryFrameWriteResult baseWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, manualRecipe));
        Check(baseWrite.IsSuccess, "library_frame_base_recipe_write_success");
        Check(ReadFrame(baseWrite.FrameRecord!).Frame?.Base == manualRecipe,
            "library_frame_base_recipe_write_round_trip");

        PointCurveRecipe pointCurveEdit = new(
            [
                new PointCurvePoint(1.0, 0.95),
                new PointCurvePoint(0.0, 0.05),
                new PointCurvePoint(0.5, 0.60),
            ],
            [],
            [new PointCurvePoint(0.25, 0.20)],
            []);
        LibraryFrameWriteResult pointCurveWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, PointCurves: pointCurveEdit));
        Check(pointCurveWrite.IsSuccess, "library_frame_point_curve_write_success");
        Check(
            pointCurveWrite.FrameRecord?["params"]!["pointCurves"]!["rgb"]![0]!["x"]!
                .GetValue<double>() == 0.0,
            "library_frame_point_curve_write_canonicalizes_order");
        LibraryFrameReadResult pointCurveReread = ReadFrame(pointCurveWrite.FrameRecord!);
        Check(pointCurveReread.IsSuccess &&
                pointCurveReread.Frame?.PointCurves.Rgb[1] == new PointCurvePoint(0.5, 0.60) &&
                pointCurveReread.Frame?.PointCurves.Green[0] == new PointCurvePoint(0.25, 0.20),
            "library_frame_point_curve_write_round_trip");

        ColorMixerRecipe colorMixerEdit = new(
            [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8],
            [-0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7, -0.8],
            new double[ColorMixerRecipe.BandCount]);
        LibraryFrameWriteResult colorMixerWrite = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(edit.Tone, edit.ManualBase, ColorMixer: colorMixerEdit));
        Check(colorMixerWrite.IsSuccess &&
                colorMixerWrite.FrameRecord?["params"]!["colorMixer"]!["hue"]!.AsArray().Count ==
                    ColorMixerRecipe.BandCount,
            "library_frame_color_mixer_write_canonicalizes_eight_bands");
        LibraryFrameReadResult colorMixerReread = ReadFrame(colorMixerWrite.FrameRecord!);
        Check(colorMixerReread.IsSuccess &&
                colorMixerReread.Frame?.ColorMixer.Hue[7] == 0.8 &&
                colorMixerReread.Frame.ColorMixer.Saturation[7] == -0.8,
            "library_frame_color_mixer_write_round_trip");

        // base 를 지우는 것은 auto 추정으로 되돌린다는 뜻이므로 키를 없앱니다.
        LibraryFrameWriteResult cleared = LibraryFrameWriter.Apply(
            original,
            new LibraryFrameEdit(ToneAdjustment.Neutral, null));
        Check(cleared.IsSuccess, "library_frame_clear_base_write");
        Check(
            cleared.FrameRecord?["params"]!.AsObject().ContainsKey("manualBaseRGB") == false,
            "library_frame_clear_base_removes_key");

        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    new ToneAdjustment(double.NaN, 0, 0, 0, 0, 0),
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_nan_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral with { Density = double.PositiveInfinity },
                    null)).Error == LibraryFrameError.InvalidToneValue,
            "library_frame_write_rejects_non_finite_basic_tone");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    new ManualBaseRgb(0.2, double.PositiveInfinity, 0.2)))
                .Error == LibraryFrameError.InvalidManualBase,
            "library_frame_write_rejects_infinite_base");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    new BaseRecipe((BaseEstimationMode)99, null, null, null)))
                .Error == LibraryFrameError.InvalidBaseRecipe,
            "library_frame_write_rejects_unknown_base_mode");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(0.5, 0.5), new PointCurvePoint(0.5, 0.6)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_duplicate_x");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    PointCurves: new PointCurveRecipe(
                        [new PointCurvePoint(double.NaN, 0.5)],
                        [], [], [])))
                .Error == LibraryFrameError.InvalidPointCurves,
            "library_frame_write_rejects_point_curve_nonfinite_coordinate");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    ColorMixer: new ColorMixerRecipe(
                        [0.0, 0.0],
                        new double[ColorMixerRecipe.BandCount],
                        new double[ColorMixerRecipe.BandCount])))
                .Error == LibraryFrameError.InvalidColorMixer,
            "library_frame_write_rejects_short_color_mixer");
        Check(
            LibraryFrameWriter.Apply(
                original,
                new LibraryFrameEdit(
                    ToneAdjustment.Neutral,
                    null,
                    ImageTransform: ImageTransformRecipe.Identity with
                    {
                        StraightenAngle = 60.0,
                    }))
                .Error == LibraryFrameError.InvalidImageTransform,
            "library_frame_write_rejects_out_of_range_straighten");
    }

    private static int RunLockContender(string isolatedBase)
    {
        StorageRootResolutionResult resolution =
            StorageRootResolver.ResolveForTests(isolatedBase);
        if (resolution.Roots is not { } contenderRoots)
        {
            Console.WriteLine("resolve-failed");
            return 2;
        }

        CatalogSessionOpenResult opened = CatalogSession.Open(contenderRoots);
        if (opened.Session is { } session)
        {
            session.Dispose();
            Console.WriteLine("acquired");
            return 0;
        }
        Console.WriteLine(opened.Error.ToString());
        return 1;
    }

    /// <summary>
    /// 같은 실행 파일을 별도 프로세스로 띄워 lock 을 잡아 보게 합니다. 결과 문자열을 돌려줍니다.
    /// </summary>
    private static string RunContenderProcess(string isolatedBase)
    {
        string executablePath = Environment.ProcessPath ?? string.Empty;
        ProcessStartInfo startInfo = new()
        {
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        // apphost 로 빌드되면 exe 를 바로 띄우고, dotnet 호스트로 실행 중이면 dll 을 넘깁니다.
        string assemblyPath = Path.Combine(
            AppContext.BaseDirectory,
            "Negaflow.Catalog.UnitTests.dll");
        if (Path.GetFileNameWithoutExtension(executablePath) == "dotnet")
        {
            startInfo.FileName = executablePath;
            startInfo.ArgumentList.Add(assemblyPath);
        }
        else
        {
            startInfo.FileName = executablePath;
        }
        startInfo.ArgumentList.Add(LockContenderArgument);
        startInfo.ArgumentList.Add(isolatedBase);

        using Process? contender = Process.Start(startInfo);
        if (contender is null)
        {
            return "start-failed";
        }
        string output = contender.StandardOutput.ReadToEnd().Trim();
        contender.WaitForExit(30_000);
        return output;
    }

    private static void VerifyCatalogSession(StorageRootSet roots)
    {
        string sessionBase = Path.Combine(
            Path.GetDirectoryName(roots.LocalApplicationDataRoot)!,
            $"session-{Guid.NewGuid():N}");
        StorageRootSet sessionRoots = StorageRootResolver.ResolveForTests(sessionBase).Roots!;
        CatalogSession? session = null;

        try
        {
            CatalogSessionOpenResult opened = CatalogSession.Open(sessionRoots);
            session = opened.Session;
            Check(opened.IsSuccess, "session_open");
            Check(session?.IsOpen == true, "session_open_is_open");
            Check(File.Exists(sessionRoots.CatalogLockPath), "session_holds_lock");
            Check(!File.Exists(sessionRoots.CatalogPath), "session_open_does_not_create_catalog");

            // 두 번째 작성자는 lock 에서 막힙니다. 세션 없이는 store 에 닿을 방법이 없습니다.
            CatalogSessionOpenResult second = CatalogSession.Open(sessionRoots);
            Check(!second.IsSuccess, "session_second_rejected");
            Check(second.Error == CatalogSessionError.Busy, "session_second_busy");
            Check(second.Session is null, "session_busy_no_partial_session");

            // 프로세스 경계에서도 같아야 합니다. 같은 프로세스 안의 거부만 보면 FileShare.None 이
            // 실제로 무엇을 막는지는 추론으로 남습니다.
            Check(RunContenderProcess(sessionBase) == "Busy", "session_other_process_busy");

            Check(session!.Read().Error == CatalogStoreError.NotFound,
                "session_read_absent_is_not_found");

            CatalogReadResult created = session.ReadOrCreate();
            Check(created.IsSuccess, "session_read_or_create_success");
            Check(created.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
                "session_read_or_create_is_empty");
            Check(File.Exists(sessionRoots.CatalogPath), "session_read_or_create_creates_file");

            Check(session.Write(Snapshot("roll-s", Row("frame-1", "one"))).IsSuccess,
                "session_write");
            Check(FrameOrder(session.Read()) == "frame-1", "session_write_round_trip");

            // 이미 있는 카탈로그에서는 ReadOrCreate 가 덮지 않습니다.
            CatalogReadResult reopened = session.ReadOrCreate();
            Check(FrameOrder(reopened) == "frame-1", "session_read_or_create_preserves_existing");

            // 손상은 ReadOrCreate 에서도 빈 라이브러리가 되지 않습니다.
            session.Dispose();
            File.WriteAllBytes(sessionRoots.CatalogPath, "not a database"u8.ToArray());
            CatalogSessionOpenResult reopenedSession = CatalogSession.Open(sessionRoots);
            session = reopenedSession.Session;
            Check(reopenedSession.IsSuccess, "session_reopen_after_dispose");
            Check(session!.ReadOrCreate().Error == CatalogStoreError.CorruptDatabase,
                "session_read_or_create_refuses_corrupt");

            session.Dispose();
            Check(session.IsOpen == false, "session_dispose_releases_lock");
            bool threw = false;
            try
            {
                session.Read();
            }
            catch (ObjectDisposedException)
            {
                threw = true;
            }
            Check(threw, "session_read_after_dispose_throws");

            CatalogSessionOpenResult third = CatalogSession.Open(sessionRoots);
            Check(third.IsSuccess, "session_reacquire_after_dispose");
            third.Session?.Dispose();

            // lock 이 풀린 뒤에는 다른 프로세스가 잡을 수 있어야 합니다. 위의 Busy 가 경로 오류나
            // 프로세스 기동 실패를 잘못 읽은 것이 아님을 이것이 확인합니다.
            Check(RunContenderProcess(sessionBase) == "acquired",
                "session_other_process_acquires_when_free");
        }
        finally
        {
            session?.Dispose();
            if (Directory.Exists(sessionBase))
            {
                Directory.Delete(sessionBase, recursive: true);
            }
        }
    }

    private static void SetStorageVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(catalogPath, $"PRAGMA user_version={version}");

    private static void SetCatalogVersion(string catalogPath, int version) =>
        ExecuteFixtureSql(
            catalogPath,
            $"UPDATE catalog_metadata SET catalog_version={version} WHERE singleton=1");

    private static void ExecuteFixtureSql(string catalogPath, string sql)
    {
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = catalogPath,
            Mode = SqliteOpenMode.ReadWrite,
            Pooling = false,
        };
        using SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static CatalogEntityRow Row(string id, string label) =>
        new(id, new JsonObject { ["label"] = label });

    private static CatalogSnapshot Snapshot(
        string? activeRollId,
        params CatalogEntityRow[] frames) =>
        new(activeRollId, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = frames,
        });

    private static string FrameOrder(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Id));

    private static string FrameLabels(CatalogReadResult result) =>
        result.Snapshot is null
            ? "<none>"
            : string.Join(',', result.Snapshot.Rows(CatalogEntityTable.Frames)
                .Select(row => row.Payload["label"]!.GetValue<string>()));

    private static DevelopRouteReadResult ReadNode(JsonObject frameRecord)
    {
        byte[] bytes = CatalogJson.SerializeCanonical(frameRecord);
        using JsonDocument document = JsonDocument.Parse(bytes);
        return DevelopRouteReader.Read(document.RootElement);
    }

    private static string SourceTransportName(FrameSourceTransport value) => value switch
    {
        FrameSourceTransport.Scanner => "scanner",
        FrameSourceTransport.Imported => "imported",
        _ => "invalid",
    };

    private static string SourceSignalName(SourceSignalKind value) => value switch
    {
        SourceSignalKind.FilmNegativeScan => "filmNegativeScan",
        SourceSignalKind.FilmPositiveScan => "filmPositiveScan",
        SourceSignalKind.RenderedDigital => "renderedDigital",
        SourceSignalKind.SceneLinearDigital => "sceneLinearDigital",
        SourceSignalKind.Unknown => "unknown",
        _ => "invalid",
    };

    private static string ProcessName(DevelopmentProcess value) => value switch
    {
        DevelopmentProcess.C41 => "c41",
        DevelopmentProcess.E6 => "e6",
        DevelopmentProcess.D76 => "d76",
        DevelopmentProcess.BlackAndWhiteReversal => "bwReversal",
        DevelopmentProcess.DigitalColor => "digitalColor",
        DevelopmentProcess.DigitalBlackAndWhite => "digitalBW",
        _ => "invalid",
    };

    private static string FilmLookSourceName(FilmLookSource value) => value switch
    {
        FilmLookSource.FilmScan => "filmScan",
        FilmLookSource.RenderedDigital => "renderedDigital",
        _ => "invalid",
    };

    private static string FilmEmulationName(FilmEmulation value) => value switch
    {
        FilmEmulation.None => "none",
        FilmEmulation.EktachromeE100 => "ektachromeE100",
        FilmEmulation.Provia100F => "provia100F",
        FilmEmulation.Velvia50 => "velvia50",
        FilmEmulation.Portra160 => "portra160",
        FilmEmulation.Portra400 => "portra400",
        FilmEmulation.Portra800 => "portra800",
        FilmEmulation.Ektar100 => "ektar100",
        FilmEmulation.Ultramax400 => "ultramax400",
        FilmEmulation.ColorPlus200 => "colorPlus200",
        FilmEmulation.FujicolorC200 => "fujicolorC200",
        FilmEmulation.Pro400H => "pro400H",
        FilmEmulation.TriX400 => "triX400",
        FilmEmulation.Hp5Plus => "hp5Plus",
        FilmEmulation.Fp4Plus => "fp4Plus",
        FilmEmulation.Delta100 => "delta100",
        FilmEmulation.Delta400 => "delta400",
        FilmEmulation.Delta3200 => "delta3200",
        FilmEmulation.TMax100 => "tmax100",
        FilmEmulation.TMax400 => "tmax400",
        FilmEmulation.TMaxP3200 => "tmaxP3200",
        FilmEmulation.Kentmere400 => "kentmere400",
        FilmEmulation.OrthoPlus => "orthoPlus",
        FilmEmulation.Sfx200 => "sfx200",
        FilmEmulation.RolleiIR => "rolleiIR",
        FilmEmulation.Scala200X => "scala200X",
        FilmEmulation.RolleiSuperpan => "rolleiSuperpan",
        FilmEmulation.Velvia100 => "velvia100",
        FilmEmulation.E100VS => "e100VS",
        FilmEmulation.Astia100F => "astia100F",
        FilmEmulation.Kodachrome64 => "kodachrome64",
        FilmEmulation.Gold200 => "gold200",
        FilmEmulation.ProImage100 => "proImage100",
        FilmEmulation.Superia400 => "superia400",
        FilmEmulation.SuperiaPremium400 => "superiaPremium400",
        FilmEmulation.Superia200 => "superia200",
        FilmEmulation.Reala100 => "reala100",
        FilmEmulation.Industrial100 => "industrial100",
        FilmEmulation.LomoCn800 => "lomoCn800",
        FilmEmulation.Vision3_500T => "vision3_500T",
        FilmEmulation.Vision3_250D => "vision3_250D",
        FilmEmulation.Vision3_50D => "vision3_50D",
        FilmEmulation.Vision3_200T => "vision3_200T",
        _ => "invalid",
    };

    private static string ErrorName(DevelopRouteError value) => value switch
    {
        DevelopRouteError.MissingSourceTransport => "missingSourceTransport",
        DevelopRouteError.InvalidSourceTransport => "invalidSourceTransport",
        DevelopRouteError.MissingFilmType => "missingFilmType",
        DevelopRouteError.MissingParameters => "missingParameters",
        DevelopRouteError.ParametersNotObject => "parametersNotObject",
        DevelopRouteError.MismatchedFilmType => "mismatchedFilmType",
        DevelopRouteError.InvalidDigitalSourceMarker => "invalidDigitalSourceMarker",
        DevelopRouteError.InvalidSourceSignal => "invalidSourceSignal",
        DevelopRouteError.UnsupportedSourceSignal => "unsupportedSourceSignal",
        DevelopRouteError.SourceSignalMarkerMismatch => "sourceSignalMarkerMismatch",
        DevelopRouteError.SourceSignalFilmTypeMismatch => "sourceSignalFilmTypeMismatch",
        DevelopRouteError.InvalidFilmEmulation => "invalidFilmEmulation",
        DevelopRouteError.InvalidFilmEmulationIntensity => "invalidFilmEmulationIntensity",
        _ => value.ToString(),
    };

    private static void Check(bool condition, string name)
    {
        ++assertionCount;
        if (!condition)
        {
            Failures.Add(name);
        }
    }
}
