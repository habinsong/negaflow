using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog.UnitTests;

internal static class Program
{
    private static readonly List<string> Failures = [];
    private static int assertionCount;

    private static int Main()
    {
        string fixturePath = Path.Combine(AppContext.BaseDirectory, "develop-route-v1.json");
        using JsonDocument fixture = JsonDocument.Parse(File.ReadAllBytes(fixturePath));

        VerifyValidFixtureCases(fixture.RootElement);
        VerifyInvalidFixtureCases(fixture.RootElement);
        VerifyReaderShapeErrors();
        VerifyRouteWriting(fixture.RootElement);
        VerifyAllFilmEmulationNames(fixture.RootElement);
        VerifyInvalidSelections(fixture.RootElement);
        VerifyCanonicalJson();

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
