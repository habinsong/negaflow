using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// **자동 보정이 실원본에서 되풀이해도 같은 값을 내는지**를 잽니다(W34~W38).
/// </summary>
/// <remarks>
/// <para>
/// <c>AutoAdjustInputTests</c> 는 가짜 exporter 로 <b>수명</b>을 잽니다 — 취소·중복 콜백·
/// 버퍼 공유·최신 요청만 게시. 계산 자체는 고정값이라 <b>같은 입력이 같은 답을 내는지</b>는
/// 재지 못합니다. 그 자리는 실원본과 진짜 네이티브 계산이 있어야 합니다.
/// </para>
/// <para>
/// 여기서는 감마·배율·자동 옵션을 갈아 끼운 열여섯 조합에서 자동 Tone 과 자동 WB 를
/// <b>각각 두 번</b> 돌려, 두 번의 결과가 한 자리도 다르지 않은지 봅니다. 아울러 자동
/// 보정이 입력 해석(감마·배율)과 옵션을 건드리지 않는지, 결과에 NaN 이 없는지도 봅니다 —
/// 앞 판에서 이전 요청의 화소 버퍼가 새 요청으로 새면 여기서 값이 흔들립니다.
/// </para>
/// </remarks>
internal static class AutoAdjustCorpusDiagnostics
{
    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length != 2 || args[0] != "--auto-adjust-check")
        {
            return false;
        }
        exitCode = Run(args[1]).GetAwaiter().GetResult();
        return true;
    }

    private static async Task<int> Run(string sourcePath)
    {
        string source = Path.GetFullPath(sourcePath);
        if (!File.Exists(source))
        {
            Console.Error.WriteLine("source not found: " + source);
            return 2;
        }
        Console.WriteLine($"source: {source}");

        var exporter = new NativeDevelopExporterAdapter();
        var dispatcher = new ImmediateUiDispatcher();
        bool passed = true;
        int combos = 0;

        foreach (double gamma in new[] { 1.0, 2.2 })
        foreach (double scale in new[] { 0.75, 1.25 })
        foreach (bool autoLevels in new[] { false, true })
        foreach (DevelopmentProcess process in new[] { DevelopmentProcess.C41, DevelopmentProcess.E6 })
        {
            ++combos;
            LibraryFrameSnapshot frame = Frame(source, gamma, scale, autoLevels, process);
            foreach (AutoKind kind in new[] { AutoKind.Tone, AutoKind.WhiteBalance })
            {
                // **같은 조합을 두 번** 돕니다. 새 coordinator 로 도는 것이 실기와 같습니다 -
                // 사용자는 단추를 두 번 누릅니다.
                AutoAdjustOutcome? first = await RunOnce(exporter, dispatcher, frame, kind);
                AutoAdjustOutcome? second = await RunOnce(exporter, dispatcher, frame, kind);
                string label = $"g{gamma:F1}_s{scale:F2}_lv{(autoLevels ? 1 : 0)}_{process}_{kind}";

                if (first is null || second is null ||
                    first.Kind != DevelopExportOutcomeKind.Completed ||
                    second.Kind != DevelopExportOutcomeKind.Completed)
                {
                    Console.WriteLine($"  {label}: FAILED first={Describe(first)} second={Describe(second)}");
                    passed = false;
                    continue;
                }

                bool same = SameSettings(first.Settings, second.Settings);
                bool keptInput = first.Frame is { } produced &&
                    produced.InputGamma == frame.InputGamma &&
                    produced.Base.Scale == frame.Base.Scale &&
                    produced.AutoLevels == frame.AutoLevels &&
                    produced.Route.DevelopmentProcess == frame.Route.DevelopmentProcess;
                bool finite = IsFinite(first.Settings);

                if (!same || !keptInput || !finite)
                {
                    Console.WriteLine($"  {label}: repeat={same} keptInput={keptInput} finite={finite}");
                    passed = false;
                }
            }
        }

        Console.WriteLine($"combos={combos} (x2 operations x2 runs)");
        Console.WriteLine(passed ? "auto-adjust-check: ok" : "auto-adjust-check: FAILED");
        return passed ? 0 : 1;
    }

    private enum AutoKind { Tone, WhiteBalance }

    private static async Task<AutoAdjustOutcome?> RunOnce(
        IDevelopExporter exporter,
        IUiDispatcher dispatcher,
        LibraryFrameSnapshot frame,
        AutoKind kind)
    {
        var coordinator = new AutoAdjustCoordinator(exporter, dispatcher);
        AutoAdjustOutcome? outcome = null;
        if (kind == AutoKind.Tone)
        {
            await coordinator.RunToneAsync(frame, value => outcome = value);
        }
        else
        {
            await coordinator.RunWhiteBalanceAsync(frame, value => outcome = value);
        }
        return outcome;
    }

    private static string Describe(AutoAdjustOutcome? outcome) => outcome is null
        ? "none"
        : $"{outcome.Kind}/{outcome.Refusal}/{outcome.FaultMessage ?? "-"}";

    private static bool IsFinite(AutoAdjustSettings? settings)
    {
        if (settings is null)
        {
            return false;
        }
        foreach (double value in Values(settings))
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>
    /// <see cref="AutoAdjustSettings"/> 는 값 운반자이지만 <c>class</c> 라 기본 같음이
    /// 참조 비교입니다. 두 번 돌린 결과는 서로 다른 객체이므로 값을 하나씩 봅니다.
    /// </summary>
    private static bool SameSettings(AutoAdjustSettings? first, AutoAdjustSettings? second)
    {
        if (first is null || second is null)
        {
            return false;
        }
        return Values(first).SequenceEqual(Values(second));
    }

    private static IEnumerable<double> Values(AutoAdjustSettings settings)
    {
        yield return settings.Exposure;
        yield return settings.Contrast;
        yield return settings.Highlights;
        yield return settings.Shadows;
        yield return settings.Whites;
        yield return settings.Blacks;
        yield return settings.Density;
        yield return settings.Vibrance;
        yield return settings.Warmth;
        yield return settings.Tint;
    }

    private static LibraryFrameSnapshot Frame(
        string source,
        double gamma,
        double scale,
        bool autoLevels,
        DevelopmentProcess process) =>
        new(
            Guid.NewGuid().ToString("D"),
            source,
            "auto-corpus",
            new DevelopRouteSnapshot(
                FrameSourceTransport.Imported,
                SourceSignalKind.FilmNegativeScan,
                process,
                FilmType.ColorNegative,
                FilmEmulation.None,
                0.5,
                UsedLegacySourceSignal: false,
                UsedLegacyIntensityDefault: false),
            null,
            ToneAdjustment.Neutral)
        {
            InputGamma = InputGammaInterpretation.Power(gamma),
            Base = BaseRecipe.Auto with { Scale = scale },
            AutoLevels = autoLevels,
        };
}
