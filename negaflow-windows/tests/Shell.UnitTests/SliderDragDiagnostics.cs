using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 슬라이더를 실제로 끄는 동안 <b>화면이 몇 번 바뀌는지</b>를 잽니다.
/// </summary>
/// <remarks>
/// <para>
/// 지금까지의 계측은 "틱 한 장이 몇 ms"였습니다. 그런데 사용자가 느끼는 것은 그것이 아니라
/// <b>끄는 동안 배달된 장 수</b>입니다. 렌더가 아무리 빨라도 배달되지 않으면 화면은 그대로이고,
/// 손을 멈춰야 한 장 나옵니다.
/// </para>
/// <para>
/// 그래서 실제 카탈로그 프레임을 열고, WinUI 와 같은 규칙(전용 UI 스레드 + 큐)의 디스패처로
/// <see cref="PreviewCoordinator"/> 를 돌린 뒤, 진짜 슬라이더처럼 몇 ms 간격으로 값을 바꿉니다.
/// 세는 것은 배달 시각입니다.
/// </para>
/// </remarks>
internal static class SliderDragDiagnostics
{
    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length < 2 || args[0] != "--slider-drag")
        {
            return false;
        }
        exitCode = Run(
            args[1],
            Argument(args, 2, "frame_12"),
            double.Parse(Argument(args, 3, "1500")),
            int.Parse(Argument(args, 4, "60")),
            int.Parse(Argument(args, 5, "8")),
            Argument(args, 6, "none"));
        return true;
    }

    private static string Argument(string[] args, int index, string fallback) =>
        args.Length > index ? args[index] : fallback;

    /// <summary>배달 한 건입니다. 화면이 한 번 바뀐 시각입니다.</summary>
    private readonly record struct Delivery(
        double AtMs,
        int Revision,
        uint Width,
        uint Height,
        bool Settled,
        string Kind);

    private readonly record struct DefectAttachLatency(
        double? InteractiveMilliseconds,
        double? SettledMilliseconds);

    private static int Run(
        string storageRoot,
        string frameSelector,
        double canvasPixels,
        int ticks,
        int tickIntervalMs,
        string defectTool)
    {
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        using PumpDispatcher dispatcher = new();
        using LibraryHostService host = new(dispatcher);
        LibraryHostState state = host.Open(roots);
        if (state != LibraryHostState.Open)
        {
            Console.Error.WriteLine("library open failed: " + state);
            return 2;
        }
        if (SelectFrame(host, frameSelector) is not { } frame)
        {
            Console.Error.WriteLine("frame not found: " + frameSelector);
            return 2;
        }
        LibraryFrameSnapshot warmFrame = defectTool == "none"
            ? frame
            : frame with { DefectRecipe = null };
        if (!TryAttachDefect(frame, defectTool, out frame, out string reason))
        {
            Console.Error.WriteLine("defect recipe refused: " + reason);
            return 2;
        }
        LibraryFrameSnapshot appendedFrame = frame;
        if (defectTool != "none")
        {
            if (DefectToolRecipes.AppendManual(frame, defectTool, out reason) is not { } appended)
            {
                Console.Error.WriteLine("second defect recipe refused: " + reason);
                return 2;
            }
            appendedFrame = frame with { DefectRecipe = appended };
        }

        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, () => canvasPixels);

        long traceMark = TraceLength();
        Stopwatch clock = Stopwatch.StartNew();
        ConcurrentQueue<Delivery> deliveries = new();
        void Record(PreviewOutcome outcome) => deliveries.Enqueue(new Delivery(
            clock.Elapsed.TotalMilliseconds,
            outcome.Revision,
            outcome.Width,
            outcome.Height,
            outcome.Settled,
            outcome.Kind.ToString()));

        // 실제 앱은 사진을 열고 정착까지 간 상태에서 슬라이더를 잡습니다. 프록시가 식은 채로
        // 재면 첫 디코드 비용이 드래그 비용에 섞입니다.
        double warmMs = Warm(dispatcher, coordinator, warmFrame, Record);
        deliveries.Clear();
        DefectAttachLatency attach = defectTool == "none"
            ? default
            : MeasureDefectAttach(dispatcher, coordinator, frame, Record);
        DefectAttachLatency append = defectTool == "none"
            ? default
            : MeasureDefectAttach(dispatcher, coordinator, appendedFrame, Record);
        frame = appendedFrame;
        deliveries.Clear();
        long dragMark = TraceLength();

        double dragStart = clock.Elapsed.TotalMilliseconds;
        DriveDrag(dispatcher, coordinator, frame, Record, ticks, tickIntervalMs);
        double lastRequestAt = clock.Elapsed.TotalMilliseconds;

        // 손을 뗀 뒤 마지막 값이 화면에 올라오는 시각까지 봅니다. 사용자가 "맨 마지막 위치의
        // 값으로만 보인다"고 한 것이 이 구간입니다.
        WaitForFinalDelivery(deliveries);
        double totalMs = clock.Elapsed.TotalMilliseconds;

        Report(
            frame,
            canvasPixels,
            ticks,
            tickIntervalMs,
            defectTool,
            warmMs,
            attach,
            append,
            dragStart,
            lastRequestAt,
            totalMs,
            deliveries,
            TraceSince(dragMark),
            traceMark);
        return 0;
    }

    private static bool TryAttachDefect(
        LibraryFrameSnapshot frame,
        string tool,
        out LibraryFrameSnapshot prepared,
        out string reason)
    {
        prepared = frame;
        reason = string.Empty;
        if (tool == "none")
        {
            return true;
        }
        DefectEditItem? item = tool switch
        {
            "brush" => DefectToolRecipes.Brush(frame, out reason),
            "clone" => DefectToolRecipes.Clone(frame, out reason),
            _ => null,
        };
        DefectRecipeSnapshot? recipe = item is null ? null : DefectToolRecipes.Wrap(frame, item);
        if (recipe is null)
        {
            reason = reason.Length > 0 ? reason : "expected brush or clone";
            return false;
        }
        prepared = frame with { DefectRecipe = recipe };
        return true;
    }

    private static LibraryFrameSnapshot? SelectFrame(
        LibraryHostService host,
        string selector)
    {
        foreach (LibraryFrameSnapshot candidate in host.Frames)
        {
            if (candidate.SourcePath.Contains(selector, StringComparison.OrdinalIgnoreCase) &&
                File.Exists(candidate.SourcePath))
            {
                return candidate;
            }
        }
        return null;
    }

    /// <summary>사진을 연 직후처럼 인터랙티브 + 정착까지 한 번 돌려 프록시를 채웁니다.</summary>
    private static double Warm(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        LibraryFrameSnapshot frame,
        Action<PreviewOutcome> record)
    {
        Stopwatch clock = Stopwatch.StartNew();
        using ManualResetEventSlim settled = new();
        dispatcher.Send(() => _ = coordinator.RequestAsync(frame, outcome =>
        {
            record(outcome);
            if (outcome.Settled)
            {
                settled.Set();
            }
        }));
        settled.Wait(TimeSpan.FromSeconds(120));
        return clock.Elapsed.TotalMilliseconds;
    }

    private static DefectAttachLatency MeasureDefectAttach(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        LibraryFrameSnapshot frame,
        Action<PreviewOutcome> record)
    {
        Stopwatch clock = Stopwatch.StartNew();
        using ManualResetEventSlim interactive = new();
        using ManualResetEventSlim settled = new();
        double? interactiveMilliseconds = null;
        double? settledMilliseconds = null;
        dispatcher.Send(() => _ = coordinator.RequestAsync(frame, outcome =>
        {
            record(outcome);
            if (outcome.Kind == DevelopExportOutcomeKind.Completed && !outcome.Settled)
            {
                interactiveMilliseconds ??= clock.Elapsed.TotalMilliseconds;
                interactive.Set();
            }
            if (outcome.Kind == DevelopExportOutcomeKind.Completed && outcome.Settled)
            {
                settledMilliseconds = clock.Elapsed.TotalMilliseconds;
                settled.Set();
            }
        }));
        interactive.Wait(TimeSpan.FromSeconds(120));
        settled.Wait(TimeSpan.FromSeconds(120));
        return new DefectAttachLatency(interactiveMilliseconds, settledMilliseconds);
    }

    /// <summary>슬라이더 한 번 끌기입니다. 값은 매 틱 바뀝니다.</summary>
    private static void DriveDrag(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        LibraryFrameSnapshot frame,
        Action<PreviewOutcome> record,
        int ticks,
        int tickIntervalMs)
    {
        Stopwatch pace = Stopwatch.StartNew();
        for (int tick = 0; tick < ticks; ++tick)
        {
            // 노출 슬라이더 한 칸씩입니다. 값이 매번 달라야 캐시가 아니라 파이프라인을 잽니다.
            double exposure = frame.Tone.Exposure + ((tick + 1) * 0.01);
            LibraryFrameSnapshot edited = frame with
            {
                Tone = frame.Tone with { Exposure = exposure },
            };
            dispatcher.Send(() => _ = coordinator.RequestAsync(edited, record));
            double due = (tick + 1) * (double)tickIntervalMs;
            while (pace.Elapsed.TotalMilliseconds < due)
            {
                Thread.Sleep(0);
            }
        }
    }

    private static void WaitForFinalDelivery(ConcurrentQueue<Delivery> deliveries)
    {
        Stopwatch wait = Stopwatch.StartNew();
        while (wait.Elapsed < TimeSpan.FromSeconds(60))
        {
            if (deliveries.Any(delivery => delivery.Settled))
            {
                return;
            }
            Thread.Sleep(5);
        }
    }

    private static void Report(
        LibraryFrameSnapshot frame,
        double canvasPixels,
        int ticks,
        int tickIntervalMs,
        string defectTool,
        double warmMs,
        DefectAttachLatency attach,
        DefectAttachLatency append,
        double dragStart,
        double lastRequestAt,
        double totalMs,
        ConcurrentQueue<Delivery> deliveries,
        TraceCounts trace,
        long traceMark)
    {
        Delivery[] all = [.. deliveries];
        Delivery[] duringDrag = [.. all
            .Where(delivery => delivery.AtMs <= lastRequestAt && !delivery.Settled)];
        double dragSpanMs = lastRequestAt - dragStart;
        double[] gaps = Gaps(duringDrag, dragStart);
        Delivery? afterHand = all
            .Where(delivery => delivery.AtMs > lastRequestAt)
            .Cast<Delivery?>()
            .FirstOrDefault();

        var report = new
        {
            status = "ok",
            operation = "slider_drag",
            source = Path.GetFileName(frame.SourcePath),
            defectTool,
            // 어떤 단계가 켜져 있는지입니다. 프레임마다 틱 비용이 4배씩 갈리므로, 무엇이
            // 그 차이를 만드는지 숫자 옆에 같이 적혀 있어야 합니다.
            recipe = Recipe(frame),
            canvasPixels,
            interactiveEdge = DevelopPreviewProxy.BufferEdge(
                DevelopPreviewProxy.InteractiveProxyDimension(canvasPixels)),
            warmMs = Math.Round(warmMs, 1),
            defectAttachInteractiveMs = attach.InteractiveMilliseconds is { } interactive
                ? Math.Round(interactive, 1)
                : (double?)null,
            defectAttachSettledMs = attach.SettledMilliseconds is { } settled
                ? Math.Round(settled, 1)
                : (double?)null,
            defectAppendInteractiveMs = append.InteractiveMilliseconds is { } appendInteractive
                ? Math.Round(appendInteractive, 1)
                : (double?)null,
            defectAppendSettledMs = append.SettledMilliseconds is { } appendSettled
                ? Math.Round(appendSettled, 1)
                : (double?)null,
            ticks,
            tickIntervalMs,
            dragSpanMs = Math.Round(dragSpanMs, 1),
            // 사용자가 보는 것: 끄는 동안 화면이 몇 번 바뀌었는가.
            framesDuringDrag = duringDrag.Length,
            fpsDuringDrag = dragSpanMs > 0
                ? Math.Round(duringDrag.Length * 1000.0 / dragSpanMs, 2)
                : 0,
            meanGapMs = gaps.Length > 0 ? Math.Round(gaps.Average(), 1) : 0,
            worstGapMs = gaps.Length > 0 ? Math.Round(gaps.Max(), 1) : 0,
            // 손을 뗀 뒤 마지막 값이 올라오기까지.
            tailLatencyMs = afterHand is { } tail
                ? Math.Round(tail.AtMs - lastRequestAt, 1)
                : (double?)null,
            totalMs = Math.Round(totalMs, 1),
            rendersStarted = trace.Started,
            rendersCompleted = trace.Completed,
            // 다 그려 놓고 버린 장입니다. 이만큼이 통째로 낭비된 시간입니다.
            rendersDropped = trace.SkippedStale,
            traceMark,
            deliveries = all.Select(delivery => new
            {
                atMs = Math.Round(delivery.AtMs, 1),
                delivery.Revision,
                delivery.Width,
                delivery.Height,
                delivery.Settled,
                delivery.Kind,
            }),
        };
        Console.WriteLine(JsonSerializer.Serialize(
            report,
            new JsonSerializerOptions { WriteIndented = true }));
    }

    /// <summary>이 프레임에서 항등이 아닌 단계만 적습니다.</summary>
    private static object Recipe(LibraryFrameSnapshot frame) => new
    {
        pixels = frame.SourceMetadata is { } meta
            ? meta.PixelWidth + "x" + meta.PixelHeight
            : "unknown",
        defectLayers = frame.DefectRecipe?.Items.Count ?? 0,
        defectSha = frame.DefectRecipe?.RecipeSha256 is { Length: > 0 },
        defectRemoval = frame.DefectRemovalStrength,
        infrared = frame.InfraredPath is { Length: > 0 },
        localDodgeBurn = frame.LocalDodgeBurn.Count,
        noiseReduction = frame.NoiseReduction != NoiseReductionRecipe.Identity,
        texture = frame.Texture != TextureRecipe.Identity,
        colorMixer = frame.ColorMixer != ColorMixerRecipe.Identity,
        colorGrading = frame.ColorGrading != ColorGradingRecipe.Identity,
        pointCurves = frame.PointCurves != PointCurveRecipe.Identity,
        colorModel = frame.ColorModel != ColorModelRecipe.Identity,
        imageTransform = frame.ImageTransform != ImageTransformRecipe.Identity,
        lookPreset = frame.LookPresetId,
        emulation = frame.Route.FilmEmulation.ToString(),
        autoLevels = frame.AutoLevels,
        autoNeutralBalance = frame.AutoNeutralBalance,
        baseMode = frame.Base.Mode.ToString(),
    };

    private static double[] Gaps(Delivery[] deliveries, double from)
    {
        if (deliveries.Length == 0)
        {
            return [];
        }
        double[] gaps = new double[deliveries.Length];
        double previous = from;
        for (int index = 0; index < deliveries.Length; ++index)
        {
            gaps[index] = deliveries[index].AtMs - previous;
            previous = deliveries[index].AtMs;
        }
        return gaps;
    }

    private readonly record struct TraceCounts(int Started, int Completed, int SkippedStale);

    private static string TracePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Negaflow",
        "Logs",
        "preview-trace.txt");

    private static long TraceLength()
    {
        try
        {
            FileInfo info = new(TracePath);
            return info.Exists ? info.Length : 0;
        }
        catch
        {
            return 0;
        }
    }

    private static TraceCounts TraceSince(long mark)
    {
        try
        {
            using FileStream stream = new(
                TracePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            stream.Seek(Math.Min(mark, stream.Length), SeekOrigin.Begin);
            using StreamReader reader = new(stream);
            int started = 0;
            int completed = 0;
            int skipped = 0;
            while (reader.ReadLine() is { } line)
            {
                if (line.Contains("RenderAsync start", StringComparison.Ordinal))
                {
                    ++started;
                }
                else if (line.Contains("PreviewOnce end ok=True", StringComparison.Ordinal))
                {
                    ++completed;
                }
                else if (line.Contains("skip stale pending", StringComparison.Ordinal))
                {
                    ++skipped;
                }
            }
            return new TraceCounts(started, completed, skipped);
        }
        catch
        {
            return new TraceCounts(0, 0, 0);
        }
    }

}
