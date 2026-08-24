using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 실제 LibraryHostService의 선택 debounce→IR 검출→sidecar/catalog 저장→상태 통지를 반복
/// 측정합니다. Develop preview 갱신은 상태 통지 뒤 FrameEdited에서 시작하므로 포함하지 않습니다.
/// </summary>
internal static class GrainMendInfraredStatusDiagnostics
{
    private sealed record Sample(
        double SelectionToStatusMilliseconds,
        double? DetectingToStatusMilliseconds,
        double? StatusToFrameEditedMilliseconds,
        int DefectCount,
        string? RecipeSha256,
        string? FinalStatus,
        bool StatusPrecededFrameEdited,
        string? Failure);

    private sealed record Scenario(
        string Tool,
        double TargetMilliseconds,
        Sample Warmup,
        IReadOnlyList<double> SelectionToStatusSamplesMilliseconds,
        IReadOnlyList<double?> DetectingToStatusSamplesMilliseconds,
        IReadOnlyList<double?> StatusToFrameEditedSamplesMilliseconds,
        int DefectCount,
        string? RecipeSha256,
        GrainMendLatencySummary SelectionToStatus,
        GrainMendLatencySummary DetectingToStatus,
        GrainMendLatencySummary StatusToFrameEdited,
        bool AllSucceeded,
        bool DefectCountStable,
        bool RecipeStable,
        bool StatusOrderStable,
        bool MeetsSelectionTarget,
        bool MeetsProcessingTarget);

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--grainmend-ir-status-p95")
        {
            return false;
        }
        if (args.Length is < 3 or > 4 ||
            !int.TryParse(args.ElementAtOrDefault(3) ?? "20", out int iterations) ||
            iterations is < 20 or > 100)
        {
            Console.Error.WriteLine(
                "usage: --grainmend-ir-status-p95 <visibleIR> <infraredIR> [iterations=20]");
            exitCode = 2;
            return true;
        }

        exitCode = Run(
            Path.GetFullPath(args[1]),
            Path.GetFullPath(args[2]),
            iterations);
        return true;
    }

    private static int Run(string visiblePath, string infraredPath, int iterations)
    {
        if (!File.Exists(visiblePath) || !File.Exists(infraredPath))
        {
            Console.Error.WriteLine("infrared pair unavailable");
            return 2;
        }
        string storageRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-gm-ir-p95-{Guid.NewGuid():N}");
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        Environment.SetEnvironmentVariable("NEGA_TIMING", "1");
        using (PumpDispatcher seedDispatcher = new())
        using (LibraryHostService seedHost = new(
            seedDispatcher,
            new NativeDevelopExporterAdapter(),
            sourceMetadataReader: null,
            token => Task.Delay(Timeout.Infinite, token)))
        {
            if (seedHost.Open(roots) != LibraryHostState.Open)
            {
                Console.Error.WriteLine("seed catalog refused");
                return 2;
            }
            FrameImportPlan imported = seedHost.Import(
                [visiblePath, infraredPath],
                DevelopmentProcess.C41);
            if (imported.Rows.Count != 1 || imported.Rejected.Count != 0 ||
                seedHost.Frames.SingleOrDefault(frame =>
                    string.Equals(frame.SourcePath, visiblePath, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(frame.InfraredPath, infraredPath, StringComparison.OrdinalIgnoreCase)) is null)
            {
                Console.Error.WriteLine("infrared pair import refused");
                return 2;
            }
        }

        Sample warmup = Measure(roots, visiblePath);
        List<Sample> samples = new(iterations);
        for (int index = 0; index < iterations; ++index)
        {
            samples.Add(Measure(roots, visiblePath));
        }

        Scenario scenario = Summarize(warmup, samples);
        bool passed = Approved(scenario);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            status = passed ? "ok" : "failed",
            operation = "grainmend_ir_status_p95",
            evidenceBoundary = "LibraryHostService selection through IR apply, sidecar/catalog persistence, and status publication; not develop preview",
            selectionDebounceMilliseconds = InfraredCleanPolicy.SelectionDebounceMilliseconds,
            adapterEvidence = "same-process IR GPU transfer counts only; this command does not emit adapter description",
            visibleSource = Path.GetFileName(visiblePath),
            infraredSource = Path.GetFileName(infraredPath),
            storageRoot,
            iterations,
            percentile = "nearest-rank p95",
            scenario,
        }, new JsonSerializerOptions { WriteIndented = true }));
        return passed ? 0 : 1;
    }

    private static Sample Measure(StorageRootSet roots, string visiblePath)
    {
        using PumpDispatcher dispatcher = new();
        using LibraryHostService host = new(dispatcher);
        if (host.Open(roots) != LibraryHostState.Open ||
            host.Frames.SingleOrDefault(frame =>
                string.Equals(frame.SourcePath, visiblePath, StringComparison.OrdinalIgnoreCase)) is not
                { } frame)
        {
            return Failed("catalog frame unavailable");
        }

        object sync = new();
        using ManualResetEventSlim completed = new();
        Stopwatch clock = new();
        double? detectingMilliseconds = null;
        double? statusMilliseconds = null;
        double? frameEditedMilliseconds = null;
        int defectCount = 0;
        string? recipeSha = null;
        string? finalStatus = null;
        string? failure = null;
        bool finalStatusSeen = false;

        host.InfraredCleanStatusChanged += (frameId, status) =>
        {
            if (!string.Equals(frameId, frame.Id, StringComparison.Ordinal))
            {
                return;
            }
            lock (sync)
            {
                if (status.Message == InfraredCleanMessage.Detecting)
                {
                    detectingMilliseconds ??= clock.Elapsed.TotalMilliseconds;
                    return;
                }

                statusMilliseconds = clock.Elapsed.TotalMilliseconds;
                finalStatus = status.Message.ToString();
                defectCount = status.DefectCount;
                finalStatusSeen = true;
                if (status.Message != InfraredCleanMessage.Applied ||
                    host.Frames.FirstOrDefault(candidate =>
                        string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal))?.DefectRecipe is
                        not { } recipe)
                {
                    failure = $"infrared final status {status.Message}";
                    completed.Set();
                    return;
                }
                recipeSha = GrainMendQualitySignature.FromRecipe(recipe);
            }
        };
        host.FrameEdited += (_, _) =>
        {
            lock (sync)
            {
                if (!finalStatusSeen)
                {
                    return;
                }
                frameEditedMilliseconds ??= clock.Elapsed.TotalMilliseconds;
                completed.Set();
            }
        };

        clock.Start();
        dispatcher.Send(() => host.SetSelection([frame.Id], frame.Id));
        if (!completed.Wait(TimeSpan.FromSeconds(120)))
        {
            clock.Stop();
            failure = "infrared status timeout";
        }
        else
        {
            clock.Stop();
        }

        // ☠️ **여기서 `Undo()` 를 쓰면 안 됩니다.** IR 편집의 undo 는 제품 계약상
        //    **IR 레이어를 보존**합니다 — `InfraredRecipeTests` 의
        //    `defect_history_mode_ir_noop_undo_preserves_ir_revision_6` 가 그것을 못 박습니다.
        //    그래서 undo 는 이름을 돌려주면서도 IR 항목을 지우지 않았고, 다음 반복이
        //    `LibraryHostService.Infrared.cs:144` 의 "이미 IR 이 있으면 건너뛴다" 가드에 걸려
        //    상태를 영영 못 받고 120초 타임아웃으로 끝났습니다. 그래서 warm-up 뒤 모든
        //    표본이 실패했고 이 진단이 쓸모없어져 있었습니다.
        //
        //    도구별 초기화가 정확히 이 일을 합니다. macOS 의 도구별 리셋과 같은 경로입니다.
        LibraryFrameError cleanup = LibraryFrameError.None;
        bool selected = false;
        dispatcher.Send(() =>
        {
            var panel = new DevelopPanelState(host, ToneLimits.Read(), NegativeLimits.Read());
            selected = panel.Select(frame.Id);
            if (selected)
            {
                cleanup = panel.RemoveDefectEdits(DefectEditLabelKind.Infrared);
            }
        });
        if (!selected)
        {
            failure ??= "infrared cleanup could not select the frame";
        }
        else if (cleanup != LibraryFrameError.None)
        {
            failure ??= $"infrared cleanup refused: {cleanup}";
        }
        else if (host.Frames.FirstOrDefault(candidate =>
                     string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal))
                 is { } cleaned &&
                 cleaned.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true)
        {
            // 지웠다고 했는데 남아 있으면 다음 반복이 또 타임아웃합니다. 조용히 넘기지 않습니다.
            failure ??= "infrared cleanup left the layer in place";
        }

        lock (sync)
        {
            double selectionToStatus = statusMilliseconds ?? clock.Elapsed.TotalMilliseconds;
            return new Sample(
                selectionToStatus,
                detectingMilliseconds is { } detecting && statusMilliseconds is { } status
                    ? status - detecting
                    : null,
                statusMilliseconds is { } published && frameEditedMilliseconds is { } edited
                    ? edited - published
                    : null,
                defectCount,
                recipeSha,
                finalStatus,
                statusMilliseconds is { } final && frameEditedMilliseconds is { } frameEdited &&
                    final <= frameEdited,
                failure);
        }
    }

    private static Scenario Summarize(Sample warmup, IReadOnlyList<Sample> samples)
    {
        GrainMendLatencySummary selection = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.SelectionToStatusMilliseconds));
        GrainMendLatencySummary processing = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.DetectingToStatusMilliseconds).OfType<double>());
        GrainMendLatencySummary publication = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.StatusToFrameEditedMilliseconds).OfType<double>());
        return new Scenario(
            "infrared-selection-status",
            1000.0,
            warmup,
            samples.Select(sample => Math.Round(sample.SelectionToStatusMilliseconds, 1)).ToArray(),
            samples.Select(sample => Round(sample.DetectingToStatusMilliseconds)).ToArray(),
            samples.Select(sample => Round(sample.StatusToFrameEditedMilliseconds)).ToArray(),
            warmup.DefectCount,
            warmup.RecipeSha256,
            selection,
            processing,
            publication,
            warmup.Failure is null && samples.All(sample => sample.Failure is null),
            samples.All(sample => sample.DefectCount == warmup.DefectCount),
            Stable(warmup.RecipeSha256, samples.Select(sample => sample.RecipeSha256)),
            warmup.StatusPrecededFrameEdited &&
                samples.All(sample => sample.StatusPrecededFrameEdited),
            selection.P95Milliseconds <= 1000.0,
            processing.P95Milliseconds <= 1000.0);
    }

    private static Sample Failed(string failure) =>
        new(0.0, null, null, 0, null, null, false, failure);

    private static bool Stable(string? expected, IEnumerable<string?> values) =>
        expected is not null && values.All(value =>
            string.Equals(expected, value, StringComparison.Ordinal));

    private static bool Approved(Scenario scenario) =>
        scenario.AllSucceeded && scenario.DefectCountStable && scenario.RecipeStable &&
        scenario.StatusOrderStable && scenario.MeetsSelectionTarget && scenario.MeetsProcessingTarget;

    private static double? Round(double? value) =>
        value is { } measured ? Math.Round(measured, 1) : null;
}
