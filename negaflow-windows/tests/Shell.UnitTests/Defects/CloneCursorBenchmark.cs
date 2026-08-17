using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 복제 도장 커서를 한 번 그리는 데 걸리는 시간입니다. 요구는 "복제는 <b>즉시</b>" 이고,
/// 이 덮개는 포인터가 움직일 <b>때마다</b> 새로 그려지므로 한 번이 한 프레임 예산(60Hz 에서
/// 16.7ms) 안에 들어와야 합니다.
/// </summary>
/// <remarks>
/// <code>
/// Negaflow.Shell.UnitTests.exe --clone-cursor-bench [width] [height] [diameterPx]
/// </code>
/// 기본값은 앱이 쓰는 미리보기 상한(<c>DevelopWorkspaceView</c> 의 1600×1200)과 macOS 기본
/// 지름 48px 이 그 크기에서 갖는 화면 지름입니다.
/// </remarks>
internal static class CloneCursorBenchmark
{
    private const int Warmup = 5;

    private const int Iterations = 30;

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length is < 1 or > 4 || args[0] != "--clone-cursor-bench")
        {
            return false;
        }
        int width = args.Length > 1 ? int.Parse(args[1]) : 1600;
        int height = args.Length > 2 ? int.Parse(args[2]) : 1200;
        double diameter = args.Length > 3 ? double.Parse(args[3]) : 48.0;
        exitCode = Run(width, height, diameter);
        return true;
    }

    private static int Run(int width, int height, double diameter)
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            SourceMetadata = new LibrarySourceMetadata(1024UL, 5088U, 3401U, 3, 16, 1, 1),
        };
        byte[] reference = new byte[checked(width * height * 4)];
        Random random = new(7);
        random.NextBytes(reference);

        // macOS `screenDiameter` — 원본 화소 지름을 표시 배율로 옮긴 것입니다.
        double screenDiameter = CloneStampCursorRenderer.ScreenDiameter(diameter, width, 5088U);
        DefectPoint cursor = new(0.5, 0.5);
        DefectPoint source = new(0.35, 0.45);

        // 실제로 가장 무거운 경우: 화면을 가로지르는 긴 획입니다.
        List<DefectPoint> stroke = [];
        for (int step = 0; step <= 200; ++step)
        {
            double t = step / 200.0;
            stroke.Add(new DefectPoint(0.1 + (0.8 * t), 0.3 + (0.4 * t)));
        }

        Report("hover", Measure(frame, width, height, reference, cursor, [], source,
            screenDiameter), width, height, screenDiameter, 0);
        Report("stroke", Measure(frame, width, height, reference, stroke[^1], stroke, source,
            screenDiameter), width, height, screenDiameter, stroke.Count);
        return 0;
    }

    private static double Measure(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        byte[] reference,
        DefectPoint cursor,
        IReadOnlyList<DefectPoint> stroke,
        DefectPoint source,
        double screenDiameter)
    {
        for (int run = 0; run < Warmup; ++run)
        {
            _ = CloneStampCursorRenderer.Render(
                frame, width, height, reference, cursor, stroke, source, null,
                screenDiameter, false);
        }
        Stopwatch clock = Stopwatch.StartNew();
        for (int run = 0; run < Iterations; ++run)
        {
            _ = CloneStampCursorRenderer.Render(
                frame, width, height, reference, cursor, stroke, source, null,
                screenDiameter, false);
        }
        clock.Stop();
        return clock.Elapsed.TotalMilliseconds / Iterations;
    }

    private static void Report(
        string stage,
        double milliseconds,
        int width,
        int height,
        double screenDiameter,
        int strokePoints)
    {
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            operation = "clone_cursor_bench",
            stage,
            width,
            height,
            screenDiameter = Math.Round(screenDiameter, 2),
            strokePoints,
            milliseconds = Math.Round(milliseconds, 3),
        }));
    }
}
