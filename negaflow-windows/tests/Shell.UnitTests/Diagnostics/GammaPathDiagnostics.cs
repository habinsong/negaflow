using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// **입력 감마가 모든 경로에서 같은 화소를 내는지**를 실제 스캔 원본으로 잽니다(W42).
/// </summary>
/// <remarks>
/// <para>
/// <c>InputWorkflowRouteTests</c> 는 <b>요청</b> 수준의 일치를 재고 게이트에서 늘 돕니다 —
/// 각 entry point 가 만든 <c>DevelopExportRequest</c> 가 같은 gamma/scale 을 들고 있는지.
/// 그러나 요청이 같아도 <b>화소</b>가 갈릴 수 있습니다: 줄여 푸는 길(proxy·streamed)과
/// 통째로 푸는 길이 서로 다른 디코더를 지나고, 그 중 한 곳이 감마를 두 번 걸면 요청은
/// 멀쩡한데 그림만 어두워집니다.
/// </para>
/// <para>
/// 그래서 여기서는 <b>같은 감마로 여러 길을 실제로 렌더해</b> 화소 평균을 견줍니다.
/// 한 길이 감마를 두 번 걸면 그 길만 평균이 크게 떨어지므로 바로 드러납니다.
/// 하드웨어가 아니라 원본 파일이 필요하므로 게이트가 아닌 진단으로 둡니다 —
/// <c>--gamma-path-check &lt;원본&gt;</c>.
/// </para>
/// </remarks>
internal static class GammaPathDiagnostics
{
    private const uint Box = 512U;

    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length != 2 || args[0] != "--gamma-path-check")
        {
            return false;
        }
        exitCode = Run(args[1]);
        return true;
    }

    private static int Run(string sourcePath)
    {
        string source = Path.GetFullPath(sourcePath);
        if (!File.Exists(source))
        {
            Console.Error.WriteLine("source not found: " + source);
            return 2;
        }
        Console.WriteLine($"source: {source}");
        Console.WriteLine($"probe: {NativeTiffSourceProbe.TryRead(source, out TiffSourceMetadata probe)} " +
            $"{probe.PixelWidth}x{probe.PixelHeight} bits={probe.BitsPerSample}");

        bool passed = true;
        double[] meansByGamma = new double[3];
        double[] gammas = [1.0, 2.2, 3.0];
        for (int index = 0; index < gammas.Length; ++index)
        {
            double gamma = gammas[index];
            // 같은 감마를 여러 길로 렌더합니다. 이름은 그 길이 실기에서 불리는 자리입니다.
            (string Name, double? Mean)[] routes =
            [
                ("preview-full", Render(source, gamma, DevelopExportFormat.Png16, proxy: 0U, raw: false)),
                ("preview-proxy", Render(source, gamma, DevelopExportFormat.Png16, proxy: 640U, raw: false)),
                ("export-tiff16", Render(source, gamma, DevelopExportFormat.Tiff16, proxy: 0U, raw: false)),
                ("export-jpeg8", Render(source, gamma, DevelopExportFormat.Jpeg8, proxy: 0U, raw: false)),
            ];
            foreach ((string name, double? mean) in routes)
            {
                Console.WriteLine($"  gamma={gamma:F1} {name,-14} mean={(mean is { } value ? value.ToString("F4") : "FAILED")}");
            }
            if (routes.Any(route => route.Mean is null))
            {
                Console.WriteLine($"  gamma={gamma:F1} -> a route failed to render");
                passed = false;
                continue;
            }

            double first = routes[0].Mean!.Value;
            meansByGamma[index] = first;
            foreach ((string name, double? mean) in routes.Skip(1))
            {
                // 줄여 푼 길은 표본이 달라 완전히 같을 수 없습니다. 감마를 두 번 걸면
                // 평균이 수십 % 움직이므로, 그보다 훨씬 좁은 문턱으로 충분히 갈립니다.
                double delta = Math.Abs(mean!.Value - first);
                bool ok = delta <= 0.02;
                Console.WriteLine($"  gamma={gamma:F1} {name} vs preview-full delta={delta:F4} {(ok ? "ok" : "MISMATCH")}");
                passed &= ok;
            }
        }

        // 감마가 실제로 그림을 바꿔야 합니다 - 조용히 무시되면 위의 비교는 전부 통과합니다.
        double spread = Math.Abs(meansByGamma[2] - meansByGamma[0]);
        bool moved = spread > 0.02;
        Console.WriteLine($"  gamma 1.0 vs 3.0 spread={spread:F4} {(moved ? "ok" : "NOT APPLIED")}");
        passed &= moved;

        Console.WriteLine(passed ? "gamma-path-check: ok" : "gamma-path-check: FAILED");
        return passed ? 0 : 1;
    }

    /// <summary>한 길로 렌더해 화소 평균을 냅니다. 실패하면 <see langword="null"/> 입니다.</summary>
    private static double? Render(
        string source,
        double gamma,
        DevelopExportFormat format,
        uint proxy,
        bool raw)
    {
        LibraryFrameSnapshot frame = new(
            Guid.NewGuid().ToString("D"),
            source,
            "gamma-path",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                DevelopmentProcess.C41,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral)
        {
            InputGamma = InputGammaInterpretation.Power(gamma),
        };
        DevelopRequestResult built = DevelopRequestFactory.Create(
            frame,
            Path.Combine(Path.GetTempPath(), $"gamma-path-{Guid.NewGuid():N}.tmp"),
            format,
            uninvertedSource: raw,
            proxyInputLongEdge: proxy);
        if (built.Request is not { } request)
        {
            Console.WriteLine($"    request refused: {built.Refusal}");
            return null;
        }

        byte[] pixels = new byte[Box * Box * 4];
        DevelopExportResult result = new NativeDevelopExporterAdapter()
            .Preview(request, Box, Box, pixels);
        if (!result.Succeeded)
        {
            Console.WriteLine($"    preview failed stage={result.FailedStage} name={result.FailureName} " +
                $"native=0x{result.NativeErrorCode:X8}");
            return null;
        }

        long count = (long)result.ImageWidth * result.ImageHeight;
        if (count <= 0)
        {
            return null;
        }
        double total = 0.0;
        for (long i = 0; i < count; ++i)
        {
            long at = i * 4;
            // BGRA8. 알파는 빼고 세 채널만 봅니다.
            total += (pixels[at] + pixels[at + 1] + pixels[at + 2]) / (3.0 * 255.0);
        }
        return total / count;
    }
}
