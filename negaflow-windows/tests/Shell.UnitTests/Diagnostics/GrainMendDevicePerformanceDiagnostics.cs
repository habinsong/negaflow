using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 같은 실제 파일과 제품 경로를 한 프로세스에서 반복해 GrainMend 다섯 기능의 p95와 품질
/// 지문을 냅니다. 이 경계는 PreviewCoordinator 배달까지이며 WinUI Composition 프레임은 아닙니다.
/// </summary>
internal static class GrainMendDevicePerformanceDiagnostics
{
    private delegate BuiltRecipe? RecipeBuilder(out string reason);

    private sealed record BuiltRecipe(LibraryFrameSnapshot Frame, string QualitySha256);

    private sealed record Sample(
        double BuildMilliseconds,
        double? InteractiveMilliseconds,
        double? SettledMilliseconds,
        double? InputToInteractiveMilliseconds,
        string? QualitySha256,
        string? InteractivePixelSha256,
        string? SettledPixelSha256,
        string? Failure);

    private sealed record Scenario(
        string Tool,
        double? TargetMilliseconds,
        Sample Warmup,
        IReadOnlyList<double> BuildSamplesMilliseconds,
        IReadOnlyList<double?> InteractiveSamplesMilliseconds,
        IReadOnlyList<double?> SettledSamplesMilliseconds,
        IReadOnlyList<double?> InputToInteractiveSamplesMilliseconds,
        string? QualitySha256,
        string? InteractivePixelSha256,
        string? SettledPixelSha256,
        GrainMendLatencySummary Build,
        GrainMendLatencySummary Interactive,
        GrainMendLatencySummary Settled,
        GrainMendLatencySummary InputToInteractive,
        bool AllSucceeded,
        bool QualityStable,
        bool PreviewStable,
        bool? MeetsTarget);

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--grainmend-device-p95")
        {
            return false;
        }
        if (args.Length is < 5 or > 7 ||
            !int.TryParse(args.ElementAtOrDefault(5) ?? "20", out int iterations) ||
            iterations is < 20 or > 100 ||
            !double.TryParse(args.ElementAtOrDefault(6) ?? "1500", out double canvasPixels) ||
            !double.IsFinite(canvasPixels) || canvasPixels <= 0.0)
        {
            Console.Error.WriteLine(
                "usage: --grainmend-device-p95 <storageRoot> <frameSelector> " +
                "<visibleIR> <infraredIR> [iterations=20] [canvasPixels=1500]");
            exitCode = 2;
            return true;
        }

        exitCode = Run(
            args[1],
            args[2],
            Path.GetFullPath(args[3]),
            Path.GetFullPath(args[4]),
            iterations,
            canvasPixels);
        return true;
    }

    private static int Run(
        string storageRoot,
        string frameSelector,
        string visibleInfraredPath,
        string infraredPath,
        int iterations,
        double canvasPixels)
    {
        if (!File.Exists(visibleInfraredPath) || !File.Exists(infraredPath))
        {
            Console.Error.WriteLine("infrared pair unavailable");
            return 2;
        }
        if (StorageRootResolver.ResolveForTests(Path.GetFullPath(storageRoot)).Roots is not
            { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        // 같은 프로세스에서 실제로 잡은 adapter와 왕복을 종료 시 stderr에 남깁니다.
        Environment.SetEnvironmentVariable("NEGA_TIMING", "1");
        using PumpDispatcher dispatcher = new();
        using LibraryHostService host = new(dispatcher);
        if (host.Open(roots) != LibraryHostState.Open)
        {
            Console.Error.WriteLine("catalog refused");
            return 2;
        }
        if (SelectFrame(host, frameSelector) is not { } selected)
        {
            Console.Error.WriteLine("frame unavailable");
            return 2;
        }
        LibraryFrameSnapshot frame = selected with
        {
            DefectRecipe = null,
            DefectRecipeRevision = 0UL,
            DefectReviewMark = null,
        };
        LibrarySourceMetadata? infraredMetadata =
            LibrarySourceMetadataReader.Read(visibleInfraredPath);
        if (infraredMetadata is null)
        {
            Console.Error.WriteLine("infrared visible metadata unavailable");
            return 2;
        }
        LibraryFrameSnapshot infraredFrame = frame with
        {
            Id = Guid.NewGuid().ToString("D"),
            SourcePath = visibleInfraredPath,
            DisplayName = Path.GetFileName(visibleInfraredPath),
            SourceMetadata = infraredMetadata,
            InfraredPath = infraredPath,
        };

        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, () => canvasPixels);
        GrainMendPreviewLatency baseWarm =
            GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, frame);
        GrainMendPreviewLatency infraredWarm =
            GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, infraredFrame);
        if (baseWarm.Failure is not null || infraredWarm.Failure is not null)
        {
            Console.Error.WriteLine("baseline preview warm-up failed");
            return 1;
        }

        Scenario automatic = RunScenario(
            "automatic-accepted-preview",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromItem(
                frame,
                DefectToolRecipes.Automatic(frame, exporter, out reason)));
        Scenario guided = RunScenario(
            "guided-accepted-preview",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromItem(
                frame,
                DefectToolRecipes.Guided(frame, exporter, out reason)));
        Scenario infrared = RunScenario(
            "infrared-recipe-preview",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromItem(
                infraredFrame,
                DefectToolRecipes.Infrared(
                    infraredFrame,
                    visibleInfraredPath,
                    infraredPath,
                    out reason)));
        Scenario brush = RunScenario(
            "brush-attach",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromItem(
                frame,
                DefectToolRecipes.Brush(frame, out reason)));
        Scenario clone = RunScenario(
            "clone-attach",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromItem(
                frame,
                DefectToolRecipes.Clone(frame, out reason)));

        Scenario brushAppend = RunAppendScenario(
            "brush", frame, iterations, dispatcher, coordinator);
        Scenario cloneAppend = RunAppendScenario(
            "clone", frame, iterations, dispatcher, coordinator);
        Scenario[] scenarios =
            [automatic, guided, infrared, brush, brushAppend, clone, cloneAppend];
        bool passed = scenarios.All(Approved);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            status = passed ? "ok" : "failed",
            operation = "grainmend_device_p95",
            evidenceBoundary = "accepted or applied recipe build to PreviewCoordinator delivery; not initial Auto/Guided/IR response and not WinUI composition",
            adapterEvidence = "same-process [timing] gpu adapter line on stderr at process exit",
            gpuDisabled = string.Equals(
                Environment.GetEnvironmentVariable("NEGA_GPU"), "0", StringComparison.Ordinal),
            source = Path.GetFileName(frame.SourcePath),
            sourcePixels = frame.SourceMetadata is { } sourceMetadata
                ? $"{sourceMetadata.PixelWidth}x{sourceMetadata.PixelHeight}"
                : "unknown",
            infraredSource = Path.GetFileName(visibleInfraredPath),
            infraredPixels = $"{infraredMetadata.Value.PixelWidth}x{infraredMetadata.Value.PixelHeight}",
            iterations,
            percentile = "nearest-rank p95",
            canvasPixels,
            baseWarm,
            infraredWarm,
            scenarios,
        }, new JsonSerializerOptions { WriteIndented = true }));
        return passed ? 0 : 1;
    }

    private static Scenario RunAppendScenario(
        string tool,
        LibraryFrameSnapshot frame,
        int iterations,
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator)
    {
        DefectEditItem? first = tool == "brush"
            ? DefectToolRecipes.Brush(frame, out _)
            : DefectToolRecipes.Clone(frame, out _);
        if (FromItem(frame, first) is not { } prefix)
        {
            return FailedScenario(tool + "-append", iterations, "prefix recipe refused");
        }
        GrainMendPreviewLatency seeded =
            GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, prefix.Frame);
        if (seeded.Failure is not null)
        {
            return FailedScenario(tool + "-append", iterations, seeded.Failure);
        }

        return RunScenario(
            tool + "-append",
            null,
            iterations,
            dispatcher,
            coordinator,
            (out string reason) => FromRecipe(
                prefix.Frame,
                DefectToolRecipes.AppendManual(prefix.Frame, tool, out reason)));
    }

    private static Scenario RunScenario(
        string tool,
        double? targetMilliseconds,
        int iterations,
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        RecipeBuilder builder)
    {
        Sample warmup = Measure(dispatcher, coordinator, builder);
        List<Sample> samples = new(iterations);
        for (int index = 0; index < iterations; ++index)
        {
            samples.Add(Measure(dispatcher, coordinator, builder));
        }

        bool succeeded = warmup.Failure is null && samples.All(sample => sample.Failure is null);
        bool qualityStable = Stable(
            warmup.QualitySha256,
            samples.Select(sample => sample.QualitySha256));
        bool previewStable = Stable(
                warmup.InteractivePixelSha256,
                samples.Select(sample => sample.InteractivePixelSha256)) &&
            Stable(
                warmup.SettledPixelSha256,
                samples.Select(sample => sample.SettledPixelSha256));
        GrainMendLatencySummary build = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.BuildMilliseconds));
        GrainMendLatencySummary interactive = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.InteractiveMilliseconds).OfType<double>());
        GrainMendLatencySummary settled = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.SettledMilliseconds).OfType<double>());
        GrainMendLatencySummary input = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.InputToInteractiveMilliseconds).OfType<double>());
        return new Scenario(
            tool,
            targetMilliseconds,
            warmup,
            samples.Select(sample => Math.Round(sample.BuildMilliseconds, 1)).ToArray(),
            samples.Select(sample => Round(sample.InteractiveMilliseconds)).ToArray(),
            samples.Select(sample => Round(sample.SettledMilliseconds)).ToArray(),
            samples.Select(sample => Round(sample.InputToInteractiveMilliseconds)).ToArray(),
            warmup.QualitySha256,
            warmup.InteractivePixelSha256,
            warmup.SettledPixelSha256,
            build,
            interactive,
            settled,
            input,
            succeeded,
            qualityStable,
            previewStable,
            targetMilliseconds is { } target ? input.P95Milliseconds <= target : null);
    }

    private static Sample Measure(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        RecipeBuilder builder)
    {
        Stopwatch clock = Stopwatch.StartNew();
        BuiltRecipe? built;
        string reason;
        try
        {
            built = builder(out reason);
        }
        catch (Exception error)
        {
            clock.Stop();
            return FailedSample(clock.Elapsed.TotalMilliseconds, error.GetType().Name);
        }
        clock.Stop();
        if (built is null)
        {
            return FailedSample(clock.Elapsed.TotalMilliseconds, reason);
        }

        GrainMendPreviewLatency preview =
            GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, built.Frame);
        return new Sample(
            clock.Elapsed.TotalMilliseconds,
            preview.InteractiveMilliseconds,
            preview.SettledMilliseconds,
            preview.InteractiveMilliseconds is { } interactive
                ? clock.Elapsed.TotalMilliseconds + interactive
                : null,
            built.QualitySha256,
            preview.InteractivePixelSha256,
            preview.SettledPixelSha256,
            preview.Failure);
    }

    private static BuiltRecipe? FromItem(
        LibraryFrameSnapshot frame,
        DefectEditItem? item) =>
        item is null ? null : FromRecipe(frame, DefectToolRecipes.Wrap(frame, item));

    private static BuiltRecipe? FromRecipe(
        LibraryFrameSnapshot frame,
        DefectRecipeSnapshot? recipe) =>
        recipe is null
            ? null
            : new BuiltRecipe(
                frame with
                {
                    DefectRecipe = recipe,
                    DefectRecipeRevision = recipe.RecipeRevision,
                    DefectReviewMark = null,
                },
                GrainMendQualitySignature.FromRecipe(recipe));

    private static LibraryFrameSnapshot? SelectFrame(
        LibraryHostService host,
        string selector) =>
        host.Frames.FirstOrDefault(frame =>
            frame.SourcePath.Contains(selector, StringComparison.OrdinalIgnoreCase) &&
            File.Exists(frame.SourcePath));

    private static bool Stable(string? expected, IEnumerable<string?> values) =>
        expected is not null && values.All(value =>
            string.Equals(expected, value, StringComparison.Ordinal));

    private static bool Approved(Scenario scenario) =>
        scenario.AllSucceeded && scenario.QualityStable && scenario.PreviewStable &&
        scenario.MeetsTarget is not false;

    private static Sample FailedSample(double buildMilliseconds, string? failure) =>
        new(buildMilliseconds, null, null, null, null, null, null,
            string.IsNullOrWhiteSpace(failure) ? "recipe refused" : failure);

    private static Scenario FailedScenario(string tool, int iterations, string? failure)
    {
        Sample sample = FailedSample(0.0, failure);
        GrainMendLatencySummary empty = GrainMendPerformanceStatistics.Summarize([]);
        return new Scenario(
            tool, null, sample,
            Enumerable.Repeat(0.0, iterations).ToArray(),
            Enumerable.Repeat<double?>(null, iterations).ToArray(),
            Enumerable.Repeat<double?>(null, iterations).ToArray(),
            Enumerable.Repeat<double?>(null, iterations).ToArray(),
            null, null, null,
            empty, empty, empty, empty, false, false, false, null);
    }

    private static double? Round(double? value) =>
        value is { } measured ? Math.Round(measured, 1) : null;
}
