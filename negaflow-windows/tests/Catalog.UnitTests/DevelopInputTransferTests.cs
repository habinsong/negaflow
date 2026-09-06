using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

internal static class DevelopInputTransferTests
{
    public static void Run()
    {
        JsonObject sourceRecord = Record("source", 1.8, 0.75);
        JsonObject targetRecord = Record("target", 2.4, 1.25);
        var source = Read(sourceRecord); var target = Read(targetRecord);
        var gamma = DevelopSettingsPasteScope.Empty with { InputGamma = true };
        var scale = DevelopSettingsPasteScope.Empty with { BaseScale = true };
        var gammaOnly = gamma.Apply(source, target);
        Check(!gamma.IsEmpty && gammaOnly.InputGamma == source.InputGamma && gammaOnly.Base == target.Base,
            "gamma_only_scope_keeps_base");
        var scaleOnly = scale.Apply(source, target);
        Check(!scale.IsEmpty && scaleOnly.InputGamma == target.InputGamma && scaleOnly.Base.Scale == 0.75,
            "scale_only_scope_keeps_gamma");
        var baseOnly = (DevelopSettingsPasteScope.Empty with { Base = true }).Apply(source, target);
        Check(baseOnly.InputGamma == target.InputGamma && baseOnly.Base.Scale == target.Base.Scale,
            "base_does_not_override_excluded_input_groups");
        var excluded = DevelopSettingsPasteScope.All with { InputGamma = false, BaseScale = false };
        Check(!excluded.IsFullDevelopScope && excluded.Apply(source, target).InputGamma == target.InputGamma,
            "all_other_groups_keep_excluded_input");
        Check(new DevelopSettingsPasteScope(false, true, false, false, false).InputGamma == false &&
            new DevelopSettingsPasteScope(true, false, false, false, false).BaseScale,
            "legacy_constructor_follows_base_selection");

        foreach (var scope in new[] { gamma, scale, DevelopSettingsPasteScope.All })
        {
            var result = DevelopSettingsTransfer.Paste(targetRecord, source, target, scope);
            Check(result.IsSuccess, "input_transfer_record_writes");
            if (result.FrameRecord is not { } record) { continue; }
            var reread = Read(record);
            Check(reread.InputGamma == (scope.InputGamma ? source.InputGamma : target.InputGamma) &&
                reread.Base.Scale == (scope.BaseScale ? source.Base.Scale : target.Base.Scale), "input_transfer_record_roundtrip");
            Check(reread.SourcePath == target.SourcePath && reread.Id == target.Id, "input_transfer_keeps_source_identity");
        }
        Check(Read(targetRecord).InputGamma == target.InputGamma && Read(sourceRecord).Base.Scale == 0.75,
            "input_transfer_keeps_input_records");
        var invalid = source with { Base = source.Base with { Scale = 1.6 } };
        Check(!DevelopSettingsTransfer.Paste(targetRecord, invalid, target, DevelopSettingsPasteScope.All).IsSuccess &&
            Read(targetRecord).InputGamma == target.InputGamma, "invalid_scale_does_not_partially_write_gamma");

        string directory = Path.Combine(Path.GetTempPath(), "negaflow-input-preset-" + Guid.NewGuid().ToString("N"));
        try
        {
            foreach (var input in new[] { source, source with { InputGamma = InputGammaInterpretation.Automatic } })
            {
                var preset = DevelopUserPresetStore.Capture(input, "입력 프리셋");
                Check(preset is not null, "input_preset_capture");
                if (preset is null) { continue; }
                // Windows에서는 제품의 고정 placeholder를 그대로 검사합니다.
                // macOS의 절대 경로 판정만 맞추며 recipe 값은 바꾸지 않습니다.
                if (!OperatingSystem.IsWindows())
                {
                    preset = preset with { Recipe = preset.Recipe.DeepClone().AsObject() };
                    preset.Recipe[LibraryFrameReader.SourcePathName] = Path.Combine(directory, "preset-source.tif");
                }
                string path = Path.Combine(directory, "presets.json");
                Check(DevelopUserPresetStore.Save(path, [preset]), "input_preset_saved");
                var loaded = DevelopUserPresetStore.Load(path);
                Check(loaded.Count == 1, "input_preset_loaded");
                if (loaded.Count != 1) { continue; }
                var applied = DevelopUserPresetStore.Apply(targetRecord, loaded[0], target);
                Check(applied.FrameRecord is { } record && Read(record).InputGamma == input.InputGamma &&
                    Read(record).Base.Scale == input.Base.Scale, "input_preset_file_apply_keeps_gamma_and_scale");
            }
        }
        finally { if (Directory.Exists(directory)) { Directory.Delete(directory, recursive: true); } }
    }

    private static LibraryFrameSnapshot Read(JsonObject record) =>
        LibraryFrameReader.Read(JsonSerializer.SerializeToElement(record)).Frame!;

    private static JsonObject Record(string id, double gamma, double scale) => new()
    {
        ["id"] = id, ["rawScanPath"] = Path.Combine(Path.GetTempPath(), id + ".tif"),
        ["sourceKind"] = "scanner", ["filmType"] = "colorNegative",
        ["params"] = new JsonObject { ["filmType"] = "colorNegative", ["inputGamma"] = gamma,
            ["baseScale"] = scale, ["baseEstimationMode"] = "auto" }
    };
}
