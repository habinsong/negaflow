using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 변환(원근)을 건 사진을 포맷마다 실제 프리뷰·내보내기 경로로 돌려 봅니다. 사진 파일은 명령줄로만
/// 받습니다 — 저장소의 시험은 합성 픽스처만 씁니다.
/// <c>--transform-sweep &lt;목록 파일&gt; &lt;내보내기 폴더&gt;</c>
/// </summary>
internal static class TransformFormatSweepDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--transform-sweep")
        {
            return false;
        }
        if (args.Length != 3 || !File.Exists(args[1]))
        {
            Console.Error.WriteLine("usage: --transform-sweep <list-file> <export-folder>");
            exitCode = 2;
            return true;
        }
        Directory.CreateDirectory(args[2]);
        exitCode = Run(File.ReadAllLines(args[1]).Where(line => line.Trim().Length > 0).ToArray(), args[2]);
        return true;
    }

    private static int Run(string[] sources, string exportFolder)
    {
        using PumpDispatcher dispatcher = new();
        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator preview = new(exporter, dispatcher, () => 2048U);
        int failures = 0;
        foreach (string source in sources)
        {
            bool negative = source.Contains("Negative_RAW", StringComparison.OrdinalIgnoreCase) ||
                source.Contains("nlp-", StringComparison.OrdinalIgnoreCase) ||
                source.Contains("negativ", StringComparison.OrdinalIgnoreCase) ||
                source.EndsWith(".tif", StringComparison.OrdinalIgnoreCase) ||
                source.EndsWith(".tiff", StringComparison.OrdinalIgnoreCase);
            LibraryFrameSnapshot frame = Frame(source, negative);
            ImageTransformRecipe a = ImageTransformRecipe.Identity with
            {
                Perspective = PerspectiveRecipe.Identity with { Vertical = 22 },
            };
            ImageTransformRecipe b = a with
            {
                StraightenAngle = -0.2,
                Crop = new ImageCropRect(0.2, 0.0, 0.6, 1.0),
            };
            foreach ((string label, ImageTransformRecipe transform) in new[] { ("A", a), ("B", b) })
            {
                Dictionary<string, object?> row = Measure(dispatcher, preview, frame with { ImageTransform = transform }, label);
                row["file"] = Path.GetFileName(source);
                row["negative"] = negative;
                if (label == "A")
                {
                    row["export"] = Export(frame with { ImageTransform = transform }, exportFolder, source);
                }
                bool ok = row["problems"] is List<string> { Count: 0 } &&
                    (label != "A" || row["export"] is string path && path.EndsWith(".jpg", StringComparison.Ordinal));
                failures += ok ? 0 : 1;
                row["ok"] = ok;
                Console.WriteLine(JsonSerializer.Serialize(row));
            }
        }
        Console.WriteLine(JsonSerializer.Serialize(new { status = failures == 0 ? "ok" : "failed", files = sources.Length, failures }));
        return failures == 0 ? 0 : 1;
    }

    private static Dictionary<string, object?> Measure(
        PumpDispatcher dispatcher, PreviewCoordinator coordinator, LibraryFrameSnapshot frame, string label)
    {
        using ManualResetEventSlim delivered = new();
        PreviewOutcome? outcome = null;
        int captured = 0;
        DateTime started = DateTime.UtcNow;
        dispatcher.Send(() => _ = coordinator.RequestReplacingAsync(frame, value =>
        {
            if (Interlocked.CompareExchange(ref captured, 1, 0) == 0)
            {
                outcome = value;
                delivered.Set();
            }
        }));
        bool arrived = delivered.Wait(TimeSpan.FromSeconds(180));
        while (coordinator.IsRendering && DateTime.UtcNow - started < TimeSpan.FromSeconds(180))
        {
            Thread.Sleep(1);
        }
        List<string> problems = [];
        Dictionary<string, object?> row = new()
        {
            ["case"] = label,
            ["ms"] = (int)(DateTime.UtcNow - started).TotalMilliseconds,
            ["problems"] = problems,
        };
        if (!arrived || outcome?.Pixels is not { } pixels || outcome.Width == 0U)
        {
            problems.Add("preview failed: " + (outcome?.Kind.ToString() ?? "timeout") + " " +
                (outcome?.FaultMessage ?? outcome?.Result?.FailureName ?? outcome?.Refusal.ToString()));
            return row;
        }
        int width = (int)outcome.Width, height = (int)outcome.Height;
        row["size"] = $"{width}x{height}";
        int Alpha(int x, int y) => pixels[((y * width) + x) * 4 + 3];
        int centerAlpha = Alpha(width / 2, height / 2);
        int cornerAlpha = Alpha(0, height - 1);
        int cornerIndex = ((height - 1) * width) * 4;
        long covered = 0, white = 0;
        for (int i = 0; i < pixels.Length; i += 4)
        {
            if (pixels[i + 3] == 0) { continue; }
            covered++;
            if (pixels[i] >= 250 && pixels[i + 1] >= 250 && pixels[i + 2] >= 250) { white++; }
        }
        double whiteFraction = covered == 0 ? 1.0 : (double)white / covered;
        DevelopHistogramBins? bins = DevelopHistogramSampler.SampleBgra8(pixels, width, height);
        row["centerAlpha"] = centerAlpha;
        row["cornerAlpha"] = cornerAlpha;
        row["cornerBgr"] = $"{pixels[cornerIndex]},{pixels[cornerIndex + 1]},{pixels[cornerIndex + 2]}";
        row["white"] = Math.Round(whiteFraction, 4);
        row["histogramPixels"] = bins?.TotalPixels;
        if (centerAlpha != 255) { problems.Add("center not covered"); }
        if (whiteFraction > 0.9) { problems.Add("white sheet"); }
        if (label == "A" && cornerAlpha != 0) { problems.Add("uncovered corner carries coverage"); }
        if (label == "A" && row["cornerBgr"] is not "255,255,255") { problems.Add("uncovered corner is not white"); }
        return row;
    }

    private static string Export(LibraryFrameSnapshot frame, string folder, string source)
    {
        string destination = Path.Combine(folder, Path.GetFileNameWithoutExtension(source) + "-A.jpg");
        DevelopRequestResult built = DevelopRequestFactory.Create(frame, destination, DevelopExportFormat.Jpeg8, null);
        if (built.Request is not { } request)
        {
            return "refused " + built.Refusal;
        }
        DevelopExportResult result = new NativeDevelopExporterAdapter().Run(request);
        return File.Exists(destination) ? destination : "failed " + result.FailureName;
    }

    private static LibraryFrameSnapshot Frame(string source, bool negative)
    {
        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(
            negative ? DevelopmentProcess.C41 : DevelopmentProcess.DigitalColor);
        return new LibraryFrameSnapshot(
            Guid.NewGuid().ToString("D"),
            source,
            Path.GetFileName(source),
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                selection.SourceSignalKind,
                negative ? DevelopmentProcess.C41 : DevelopmentProcess.DigitalColor,
                selection.FilmType,
                selection.FilmEmulation,
                selection.FilmEmulationIntensity,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            new ManualBaseRgb(0.2, 0.2, 0.2),
            ToneAdjustment.Neutral);
    }
}
