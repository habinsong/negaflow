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

        VerifyEveryInputScopeCombination();
        VerifyEmptyScopeIsANoOp();
        VerifyStoredPrecisionSurvivesTransfer();
    }

    /// <summary>
    /// 입력 감마와 베이스 배율은 <b>서로 독립</b>이어야 합니다 — 네 조합을 모두 봅니다(W30).
    /// </summary>
    /// <remarks>
    /// `Base` 를 함께 켜도 결과가 달라지면 안 됩니다. 앞 판의 생성자는 `Base` 하나로 셋을
    /// 다 켰고(legacy), 그래서 "베이스만" 을 고른 사용자가 감마까지 덮어썼습니다. 여기서는
    /// `Base` 를 켠 경우와 끈 경우를 나란히 돌려 그 사고가 다시 나지 않게 못 박습니다.
    /// </remarks>
    private static void VerifyEveryInputScopeCombination()
    {
        var source = Read(Record("combo-source", 1.8, 0.75));
        var target = Read(Record("combo-target", 2.4, 1.25));
        foreach (bool withBase in new[] { false, true })
        foreach (bool gamma in new[] { false, true })
        foreach (bool scale in new[] { false, true })
        {
            var scope = DevelopSettingsPasteScope.Empty with
            {
                Base = withBase,
                InputGamma = gamma,
                BaseScale = scale,
            };
            var result = scope.Apply(source, target);
            string name = $"combo_base{withBase}_gamma{gamma}_scale{scale}";
            Check(
                result.InputGamma == (gamma ? source.InputGamma : target.InputGamma),
                name + "_gamma",
                () => result.InputGamma.ToString());
            Check(
                result.Base.Scale == (scale ? source.Base.Scale : target.Base.Scale),
                name + "_scale",
                () => result.Base.Scale.ToString());
        }
    }

    /// <summary>모든 범위를 끄면 아무 것도 하지 않아야 합니다(W31).</summary>
    /// <remarks>
    /// 빈 범위가 조용히 "전체 붙여넣기" 로 흐르면 사용자는 아무 것도 고르지 않고 사진을
    /// 통째로 덮어씁니다. 되돌리기 한 번으로 못 돌아오는 자리입니다.
    /// </remarks>
    private static void VerifyEmptyScopeIsANoOp()
    {
        JsonObject targetRecord = Record("empty-target", 2.4, 1.25);
        var source = Read(Record("empty-source", 1.8, 0.75));
        var target = Read(targetRecord);
        var empty = DevelopSettingsPasteScope.Empty;
        Check(empty.IsEmpty, "empty_scope_reports_empty");
        var applied = empty.Apply(source, target);
        Check(applied.InputGamma == target.InputGamma && applied.Base == target.Base,
            "empty_scope_changes_nothing");
        var written = DevelopSettingsTransfer.Paste(targetRecord, source, target, empty);
        Check(Read(targetRecord).InputGamma == target.InputGamma &&
            Read(targetRecord).Base.Scale == target.Base.Scale,
            "empty_scope_leaves_the_record_alone",
            () => written.IsSuccess.ToString());
    }

    /// <summary>
    /// 화면은 한 자리로 보여 주지만 <b>저장값은 그대로</b>여야 합니다(W33).
    /// </summary>
    /// <remarks>
    /// <c>InputGammaValueInput.Round</c> 는 <b>사용자가 입력하거나 화면에 적을 때만</b> 씁니다.
    /// 옮기는 길에서 반올림이 끼면 2.25 로 저장된 사진을 다른 사진에 붙여넣을 때마다 값이
    /// 조금씩 움직입니다 — 붙여넣기를 반복하면 눈에 보이게 밀립니다.
    /// </remarks>
    private static void VerifyStoredPrecisionSurvivesTransfer()
    {
        const double precise = 2.253_75;
        JsonObject sourceRecord = Record("precise-source", precise, 0.815);
        JsonObject targetRecord = Record("precise-target", 2.4, 1.25);
        var source = Read(sourceRecord);
        var target = Read(targetRecord);
        Check(source.InputGamma.Value == precise, "precision_survives_the_record_read",
            () => source.InputGamma.Value?.ToString() ?? "null");

        var scope = DevelopSettingsPasteScope.Empty with { InputGamma = true, BaseScale = true };
        var applied = scope.Apply(source, target);
        Check(applied.InputGamma.Value == precise, "precision_survives_apply",
            () => applied.InputGamma.Value?.ToString() ?? "null");
        Check(applied.Base.Scale == 0.815, "precision_survives_apply_for_scale",
            () => applied.Base.Scale.ToString());

        var result = DevelopSettingsTransfer.Paste(targetRecord, source, target, scope);
        Check(result.FrameRecord is { } record && Read(record).InputGamma.Value == precise,
            "precision_survives_the_record_write",
            () => result.FrameRecord is { } written
                ? Read(written).InputGamma.Value?.ToString() ?? "null"
                : "no record");
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
