using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 같은 사진을 현상 타깃마다 실제 프리뷰 경로로 그려 서로 얼마나 다른지 잽니다. 사진은 명령줄로만 받습니다.
/// <c>--target-compare &lt;사진&gt; [process]</c>
/// </summary>
internal static class TargetCompareDiagnostics
{
    private static readonly DevelopTarget[] Targets =
        [DevelopTarget.Main, DevelopTarget.Noritsu, DevelopTarget.Sp3000, DevelopTarget.F135, DevelopTarget.Hr];

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--target-compare")
        {
            return false;
        }
        if (args.Length < 2 || !File.Exists(args[1]))
        {
            Console.Error.WriteLine("usage: --target-compare <source> [c41|digital]");
            exitCode = 2;
            return true;
        }
        bool digital = args.Length > 2 && args[2] == "digital";
        using PumpDispatcher dispatcher = new();
        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator preview = new(exporter, dispatcher, () => 1024U);
        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(
            digital ? DevelopmentProcess.DigitalColor : DevelopmentProcess.C41);
        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"), args[1], Path.GetFileName(args[1]),
            new DevelopRouteSnapshot(FrameSourceTransport.Imported, selection.SourceSignalKind,
                digital ? DevelopmentProcess.DigitalColor : DevelopmentProcess.C41, selection.FilmType,
                selection.FilmEmulation, selection.FilmEmulationIntensity,
                UsedLegacySourceSignal: false, UsedLegacyIntensityDefault: false),
            null, ToneAdjustment.Neutral)
        {
            Base = BaseRecipe.Auto,
        };
        Dictionary<DevelopTarget, byte[]> images = [];
        foreach (DevelopTarget target in Targets)
        {
            byte[]? pixels = Render(dispatcher, preview, frame with { DevelopTarget = target }, out string detail);
            if (pixels is null)
            {
                Console.WriteLine(JsonSerializer.Serialize(new { target = target.ToString(), failed = detail }));
                exitCode = 1;
                continue;
            }
            images[target] = pixels.ToArray();
            double[] mean = new double[3];
            for (int i = 0; i < pixels.Length; i += 4) { mean[0] += pixels[i + 2]; mean[1] += pixels[i + 1]; mean[2] += pixels[i]; }
            int n = pixels.Length / 4;
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                target = target.ToString(),
                meanRgb = mean.Select(v => Math.Round(v / n, 2)).ToArray(),
            }));
        }
        foreach (DevelopTarget a in images.Keys)
        {
            foreach (DevelopTarget b in images.Keys.Where(b => b > a))
            {
                byte[] x = images[a], y = images[b];
                if (x.Length != y.Length) { continue; }
                long sum = 0; int max = 0;
                for (int i = 0; i < x.Length; i++) { if ((i & 3) == 3) { continue; } int d = Math.Abs(x[i] - y[i]); sum += d; max = Math.Max(max, d); }
                Console.WriteLine(JsonSerializer.Serialize(new
                {
                    pair = $"{a}-{b}",
                    meanAbs = Math.Round(sum / (x.Length * 0.75), 3),
                    max,
                }));
            }
        }
        return true;
    }

    private static byte[]? Render(PumpDispatcher dispatcher, PreviewCoordinator coordinator, LibraryFrameSnapshot frame, out string detail)
    {
        using ManualResetEventSlim delivered = new();
        PreviewOutcome? outcome = null;
        int captured = 0;
        dispatcher.Send(() => _ = coordinator.RequestReplacingAsync(frame, value =>
        {
            if (Interlocked.CompareExchange(ref captured, 1, 0) == 0) { outcome = value; delivered.Set(); }
        }));
        bool arrived = delivered.Wait(TimeSpan.FromSeconds(120));
        DateTime started = DateTime.UtcNow;
        while (coordinator.IsRendering && DateTime.UtcNow - started < TimeSpan.FromSeconds(120)) { Thread.Sleep(1); }
        detail = outcome?.FaultMessage ?? outcome?.Result?.FailureName ?? outcome?.Kind.ToString() ?? "timeout";
        return arrived ? outcome?.Pixels : null;
    }
}
