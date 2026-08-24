using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 사진이 이미 화면에 올라온 뒤 프로세스·타깃·자동 보정의 첫 반응과 warm 반응을 잽니다.
/// 각 기능의 cold 표본은 이 실행 파일을 기능마다 새로 시작해 수집합니다.
/// </summary>
internal static class FirstActionLatencyDiagnostics
{
    private static readonly string[] Actions =
    [
        "process",
        "target",
        "auto-color",
        "auto-levels",
        "auto-tone",
        "auto-white-balance",
    ];

    private readonly record struct Sample(
        double ComputeMilliseconds,
        double PreviewMilliseconds,
        double TotalMilliseconds,
        string Outcome,
        uint Width,
        uint Height,
        string? Detail);

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--first-action-latency")
        {
            return false;
        }
        if (args.Length is < 3 or > 5 || !Actions.Contains(args[2], StringComparer.Ordinal) ||
            (args.Length >= 4 && !uint.TryParse(args[3], out _)) ||
            (args.Length >= 5 && !int.TryParse(args[4], out _)))
        {
            Console.Error.WriteLine(
                "usage: --first-action-latency <source> " +
                "<process|target|auto-color|auto-levels|auto-tone|auto-white-balance> " +
                "[edge=2048] [iterations=5]");
            exitCode = 2;
            return true;
        }

        uint edge = args.Length >= 4 ? uint.Parse(args[3]) : 2048U;
        int iterations = args.Length >= 5 ? int.Parse(args[4]) : 5;
        if (edge is 0U or > 3600U || iterations is < 2 or > 20)
        {
            Console.Error.WriteLine("edge must be 1..3600 and iterations must be 2..20");
            exitCode = 2;
            return true;
        }
        exitCode = Run(Path.GetFullPath(args[1]), args[2], edge, iterations);
        return true;
    }

    private static int Run(string source, string action, uint edge, int iterations)
    {
        if (!File.Exists(source))
        {
            Console.Error.WriteLine("source not found");
            return 2;
        }

        LibraryFrameSnapshot frame = Frame(source);
        using PumpDispatcher dispatcher = new();
        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator preview = new(exporter, dispatcher, () => edge);
        AutoAdjustCoordinator autoAdjust = new(exporter, dispatcher);

        Sample warmup = Preview(dispatcher, preview, frame);
        if (warmup.Outcome != DevelopExportOutcomeKind.Completed.ToString())
        {
            Console.Error.WriteLine(
                $"baseline preview failed: {warmup.Outcome} {warmup.Detail}");
            return 1;
        }

        List<Sample> samples = new(iterations);
        for (int index = 0; index < iterations; ++index)
        {
            samples.Add(MeasureAction(
                dispatcher,
                preview,
                autoAdjust,
                frame,
                action));
        }

        bool succeeded = samples.All(sample =>
            sample.Outcome == DevelopExportOutcomeKind.Completed.ToString());
        double[] warm = samples.Skip(1).Select(sample => sample.TotalMilliseconds).ToArray();
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            status = succeeded ? "ok" : "failed",
            operation = "first_action_latency",
            action,
            source = Path.GetFileName(source),
            edge,
            iterations,
            baselineWarmupMilliseconds = Round(warmup.TotalMilliseconds),
            first = Report(samples[0]),
            warm = new
            {
                medianMilliseconds = Round(Percentile(warm, 0.5)),
                p95Milliseconds = Round(Percentile(warm, 0.95)),
                maximumMilliseconds = Round(warm.Max()),
            },
            samples = samples.Select(Report),
        }));
        return succeeded ? 0 : 1;
    }

    private static Sample MeasureAction(
        PumpDispatcher dispatcher,
        PreviewCoordinator preview,
        AutoAdjustCoordinator autoAdjust,
        LibraryFrameSnapshot frame,
        string action)
    {
        if (action is "auto-tone" or "auto-white-balance")
        {
            return MeasureComputedAction(dispatcher, preview, autoAdjust, frame, action);
        }

        LibraryFrameSnapshot edited = action switch
        {
            "process" => WithProcess(frame, DevelopmentProcess.E6),
            "target" => frame with { DevelopTarget = DevelopTarget.Sp3000 },
            "auto-color" => frame with { AutoNeutralBalance = true },
            "auto-levels" => frame with { AutoLevels = true },
            _ => throw new ArgumentOutOfRangeException(nameof(action)),
        };
        return Preview(dispatcher, preview, edited);
    }

    private static Sample MeasureComputedAction(
        PumpDispatcher dispatcher,
        PreviewCoordinator preview,
        AutoAdjustCoordinator autoAdjust,
        LibraryFrameSnapshot frame,
        string action)
    {
        using ManualResetEventSlim computed = new();
        AutoAdjustOutcome? outcome = null;
        Stopwatch total = Stopwatch.StartNew();
        dispatcher.Send(() =>
        {
            Task<bool> task = action == "auto-tone"
                ? autoAdjust.RunToneAsync(frame, Complete)
                : autoAdjust.RunWhiteBalanceAsync(frame, Complete);
            _ = task;
        });
        if (!computed.Wait(TimeSpan.FromSeconds(120)) || outcome?.Frame is not { } edited)
        {
            return new Sample(
                total.Elapsed.TotalMilliseconds,
                0.0,
                total.Elapsed.TotalMilliseconds,
                outcome?.Kind.ToString() ?? "timeout",
                0U,
                0U,
                outcome?.FaultMessage);
        }

        double computeMilliseconds = total.Elapsed.TotalMilliseconds;
        Sample rendered = Preview(dispatcher, preview, edited);
        return rendered with
        {
            ComputeMilliseconds = computeMilliseconds,
            TotalMilliseconds = computeMilliseconds + rendered.TotalMilliseconds,
        };

        void Complete(AutoAdjustOutcome value)
        {
            outcome = value;
            computed.Set();
        }
    }

    private static Sample Preview(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        LibraryFrameSnapshot frame)
    {
        using ManualResetEventSlim delivered = new();
        PreviewOutcome? outcome = null;
        double deliveredMilliseconds = 0.0;
        int captured = 0;
        Stopwatch clock = Stopwatch.StartNew();
        dispatcher.Send(() => _ = coordinator.RequestReplacingAsync(frame, value =>
        {
            if (Interlocked.CompareExchange(ref captured, 1, 0) == 0)
            {
                outcome = value;
                deliveredMilliseconds = clock.Elapsed.TotalMilliseconds;
                delivered.Set();
            }
        }));
        if (!delivered.Wait(TimeSpan.FromSeconds(120)) || outcome is null)
        {
            return new Sample(
                0.0,
                clock.Elapsed.TotalMilliseconds,
                clock.Elapsed.TotalMilliseconds,
                "timeout",
                0U,
                0U,
                null);
        }
        Stopwatch idle = Stopwatch.StartNew();
        while (coordinator.IsRendering && idle.Elapsed < TimeSpan.FromSeconds(120))
        {
            Thread.Sleep(1);
        }
        return new Sample(
            0.0,
            deliveredMilliseconds,
            deliveredMilliseconds,
            outcome.Kind.ToString(),
            outcome.Width,
            outcome.Height,
            outcome.FaultMessage ?? outcome.Result?.FailureName);
    }

    private static LibraryFrameSnapshot Frame(string source) => new(
        Guid.NewGuid().ToString("D"),
        source,
        Path.GetFileName(source),
        new DevelopRouteSnapshot(
            FrameSourceTransport.Imported,
            SourceSignalKind.FilmNegativeScan,
            DevelopmentProcess.C41,
            FilmType.ColorNegative,
            FilmEmulation.None,
            DevelopRouteSelection.NewRecipeDefaultFilmEmulationIntensity,
            UsedLegacySourceSignal: false,
            UsedLegacyIntensityDefault: false),
        new ManualBaseRgb(0.2, 0.2, 0.2),
        ToneAdjustment.Neutral)
    {
        Base = new BaseRecipe(BaseEstimationMode.Manual, null, null, null),
    };

    private static LibraryFrameSnapshot WithProcess(
        LibraryFrameSnapshot frame,
        DevelopmentProcess process)
    {
        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(process);
        return frame with
        {
            Route = frame.Route with
            {
                SourceSignalKind = selection.SourceSignalKind,
                DevelopmentProcess = process,
                FilmType = selection.FilmType,
                FilmEmulation = selection.FilmEmulation,
                FilmEmulationIntensity = selection.FilmEmulationIntensity,
            },
        };
    }

    private static object Report(Sample sample) => new
    {
        computeMilliseconds = Round(sample.ComputeMilliseconds),
        previewMilliseconds = Round(sample.PreviewMilliseconds),
        totalMilliseconds = Round(sample.TotalMilliseconds),
        outcome = sample.Outcome,
        detail = sample.Detail,
        sample.Width,
        sample.Height,
    };

    private static double Percentile(double[] values, double percentile)
    {
        double[] sorted = [.. values.Order()];
        int index = Math.Clamp(
            (int)Math.Ceiling(sorted.Length * percentile) - 1,
            0,
            sorted.Length - 1);
        return sorted[index];
    }

    private static double Round(double value) => Math.Round(value, 1);
}
