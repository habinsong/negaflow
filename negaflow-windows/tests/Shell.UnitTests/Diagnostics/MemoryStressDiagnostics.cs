using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 가상 스캔 수백~수천 장으로 메모리 누수를 잡습니다. <b>사용자의 사진은 쓰지 않습니다.</b>
/// </summary>
/// <remarks>
/// 한 화면만 재면 아무 것도 못 잡습니다 - 미리보기만 재던 앞 판은 평탄하다고 나왔는데 설치
/// 앱은 계속 올랐습니다. 그래서 한 프레임마다 <b>여섯 경로를 전부</b> 지납니다.
///
/// <list type="number">
/// <item>카탈로그 - 가져오기와 다시 열기</item>
/// <item>라이브러리뷰 썸네일 - <c>ThumbnailService.Request</c></item>
/// <item>현상뷰 프리뷰 - <c>PreviewCoordinator</c> 정착 배달</item>
/// <item>현상뷰·인화뷰 developed 프록시 - <c>RequestDeveloped</c></item>
/// <item>인화뷰 투영 - <c>PrintSourceSelection</c></item>
/// <item>현상 프로세스와 현상 타깃 전환</item>
/// </list>
///
/// 판정선은 <b>첫 바퀴 뒤의 증가</b>입니다. 상주 한도까지 차오르는 것은 설계이고
/// (`FrameCacheBudget` = 결함 제거 원본 장수 + 현상 결과 장수), 다 찬 뒤에도 계속 오르면
/// 그것이 누수입니다.
/// </remarks>
internal static class MemoryStressDiagnostics
{
    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        // 합성 스캔 한 장만 만들어 다른 진단으로 들여다볼 때 씁니다.
        if (args.Length == 3 && args[0] == "--synthetic-scan")
        {
            int mp = int.TryParse(args[2], out int value) ? value : 8;
            (int w, int h) = SyntheticScanWriter.ExtentForMegapixels(mp);
            SyntheticScanWriter.Write(Path.GetFullPath(args[1]), w, h, 1);
            Console.WriteLine($"wrote {args[1]} {w}x{h} ({mp}MP)");
            return true;
        }
        // 지금 이 프로세스의 메모리 내역을 그대로 냅니다. 예산이 프로세스 전체를 상한 안에
        // 두는지 판정하는 자리입니다.
        if (args.Length >= 1 && args[0] == "--memory-report")
        {
            Console.WriteLine(MemoryReportText());
            return true;
        }
        if (args.Length is < 1 || args[0] != "--memory-stress")
        {
            return false;
        }
        // --memory-stress <megapixelList> <framesPerSize> <passes>
        string sizes = args.Length > 1 ? args[1] : "8,12,24,48";
        int framesPerSize = args.Length > 2 && int.TryParse(args[2], out int parsed) ? parsed : 50;
        int passes = args.Length > 3 && int.TryParse(args[3], out int loops) ? loops : 2;
        if (framesPerSize is < 1 or > 5000 || passes is < 1 or > 50)
        {
            Console.Error.WriteLine("framesPerSize 1..5000, passes 1..50");
            exitCode = 2;
            return true;
        }
        int[] megapixels = [.. sizes
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(text => int.TryParse(text, out int value) ? value : 0)
            .Where(value => value is > 0 and <= 200)];
        if (megapixels.Length == 0)
        {
            Console.Error.WriteLine("megapixel list is empty");
            exitCode = 2;
            return true;
        }
        // 다섯째 인자는 켤 경로입니다. 하나씩 꺼 보며 어느 경로가 새는지 가릅니다.
        //   t=라이브러리 썸네일  d=developed 프록시  p=현상 프리뷰
        //   r=현상 프로세스·타깃  n=인화뷰 투영
        string paths = args.Length > 4 ? args[4].ToLowerInvariant() : "tdprn";
        exitCode = Run(megapixels, framesPerSize, passes, paths);
        return true;
    }

    private sealed record Sample(
        int Index,
        int Pass,
        int Megapixels,
        long PrivateBytes,
        long ManagedBytes);

    private sealed record SizeResult(
        int Megapixels,
        int Width,
        int Height,
        int Frames,
        int Passes,
        long BeforeBytes,
        long AfterFirstPassBytes,
        long AfterLastPassBytes,
        long PeakBytes,
        long AfterCollectBytes,
        long GrowthAfterFirstPass,
        double GrowthPerViewAfterFirstPass,
        long ManagedAfterFirstPassBytes,
        long ManagedAfterLastPassBytes,
        long ManagedGrowthAfterFirstPass,
        int ThumbnailsCachedAfterFirstPass,
        int DevelopedCachedAfterFirstPass,
        int DevelopedFrameLimit,
        long DevelopedByteLimit,
        int DevelopedResidentCount,
        long DevelopedResidentBytes,
        // 마지막 한 바퀴만 본 뷰당 증가입니다. 첫 바퀴 뒤라도 캐시는 아직 예산까지
        // 차오르는 중일 수 있습니다 - 그 차오름은 설계이고 누수가 아닙니다. 다 찬 뒤인
        // **마지막 바퀴**에서도 늘면 그때가 누수입니다.
        double GrowthPerViewInLastPass,
        long AutomaticCeilingBytes,
        long OverCeilingBytes,
        bool StayedUnderCeiling,
        bool Passed);

    // 첫 바퀴 뒤 뷰당 증가가 이 값을 넘으면 누수로 봅니다. 상주 캐시는 이미 다 찬 뒤이므로
    // 여기서는 0 에 가까워야 합니다. 측정 잡음(GC 타이밍, 드라이버 예비분)을 감안한 자리입니다.
    private const double AllowedGrowthPerViewBytes = 2.0 * 1024.0 * 1024.0;

    private static int Run(int[] megapixels, int framesPerSize, int passes, string paths)
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-stress-{Guid.NewGuid():N}");
        List<SizeResult> results = [];
        List<Sample> samples = [];
        try
        {
            foreach (int size in megapixels)
            {
                results.Add(RunSize(root, size, framesPerSize, passes, samples, paths));
                // 어느 캐시가 늘었는지는 총량만 봐서는 못 가릅니다. 한 치수를 끝낼 때마다
                // 엔진이 보는 내역을 그대로 남깁니다.
                Console.Error.WriteLine($"[{size}MP 끝]");
                Console.Error.WriteLine(MemoryReportText());
                Console.Error.WriteLine(ProcessRegionMap.Report());
            }
            bool passed = results.All(result => result.Passed);
            Console.WriteLine(JsonSerializer.Serialize(
                new
                {
                    status = passed ? "ok" : "failed",
                    operation = "memory_stress",
                    framesPerSize,
                    passes,
                    paths,
                    allowedGrowthPerViewBytes = AllowedGrowthPerViewBytes,
                    results,
                },
                new JsonSerializerOptions { WriteIndented = true }));
            return passed ? 0 : 1;
        }
        finally
        {
            TryDeleteTree(root);
        }
    }

    private static SizeResult RunSize(
        string root,
        int megapixels,
        int framesPerSize,
        int passes,
        List<Sample> samples,
        string paths)
    {
        (int width, int baseHeight) = SyntheticScanWriter.ExtentForMegapixels(megapixels);
        string sourceFolder = Path.Combine(root, $"src-{megapixels}mp");
        string storageRoot = Path.Combine(root, $"store-{megapixels}mp");
        Directory.CreateDirectory(sourceFolder);
        for (int index = 0; index < framesPerSize; ++index)
        {
            // 실기 스캔처럼 세로를 흔듭니다. GPU 풀이 사진마다 새로 잡는 조건입니다.
            int height = baseHeight + (index % 37) * 2;
            SyntheticScanWriter.Write(
                Path.Combine(sourceFolder, $"synthetic-{megapixels}mp-{index:D5}.tiff"),
                width,
                height,
                index);
        }

        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            throw new InvalidOperationException("storage root refused");
        }

        long before = PrivateBytes();
        long peak = before;
        long afterFirstPass = before;
        long afterLastPass = before;
        long managedAfterFirstPass = 0L;
        long managedAfterLastPass = 0L;
        int thumbnailsCached = -1;
        int developedCached = -1;
        int developedFrameLimit = -1;
        long developedByteLimit = -1L;
        int developedResidentCount = -1;
        long developedResidentBytes = -1L;
        // 프로세스 전체가 이 안에 있어야 합니다 - 작업 관리자에서 사용자가 보는 값입니다.
        long ceiling = 0L;
        long overCeiling = 0L;
        long beforeLastPass = 0L;
        int viewsAfterFirstPass = 0;

        using (PumpDispatcher dispatcher = new())
        using (LibraryHostService host = new(
            dispatcher,
            new NativeDevelopExporterAdapter(),
            sourceMetadataReader: null,
            token => Task.Delay(Timeout.Infinite, token)))
        {
            if (host.Open(roots) != LibraryHostState.Open)
            {
                throw new InvalidOperationException("catalog open refused");
            }
            if (host.ImportFolders([sourceFolder], DevelopmentProcess.C41) is not { } imported ||
                imported.CatalogError != CatalogStoreError.None ||
                host.Frames.Count != framesPerSize)
            {
                throw new InvalidOperationException(
                    $"folder import refused: frames={host.Frames.Count} expected={framesPerSize}");
            }

            ThumbnailService thumbnails = new(
                new NativeDevelopExporterAdapter(),
                new StressThumbnailCodec(),
                dispatcher,
                Path.Combine(storageRoot, "Thumbnails"),
                Path.Combine(storageRoot, "DevelopedPreviews"));
            thumbnails.ApplyResidencySettings(new FrameCacheResidencySettings());
            PreviewCoordinator coordinator = new(
                new NativeDevelopExporterAdapter(),
                dispatcher,
                () => 2048L * 2048L);
            var panel = new DevelopPanelState(host, ToneLimits.Read(), NegativeLimits.Read());

            try
            {
            (developedFrameLimit, developedByteLimit) = thumbnails.DevelopedLimits();
            int index = 0;
            for (int pass = 1; pass <= passes; ++pass)
            {
                foreach (LibraryFrameSnapshot frame in host.Frames.ToArray())
                {
                    ExerciseOneFrame(
                        dispatcher, host, thumbnails, coordinator, panel, frame, index, paths);
                    long now = PrivateBytes();
                    peak = Math.Max(peak, now);
                    if (Negaflow.Interop.MemoryReportBridge.TryRead() is { } report)
                    {
                        ceiling = (long)report.AutomaticProcessCeilingBytes;
                        overCeiling = Math.Max(overCeiling, now - ceiling);
                    }
                    samples.Add(new Sample(++index, pass, megapixels, now, GC.GetTotalMemory(false)));
                    if (pass > 1)
                    {
                        ++viewsAfterFirstPass;
                    }
                    afterLastPass = now;
                    managedAfterLastPass = GC.GetTotalMemory(false);
                }
                if (pass == passes - 1)
                {
                    beforeLastPass = afterLastPass;
                }
                if (pass == 1)
                {
                    afterFirstPass = afterLastPass;
                    managedAfterFirstPass = managedAfterLastPass;
                    // 첫 바퀴가 끝나면 캐시는 다 차 있어야 합니다. 여기서 0 이면 렌더가
                    // 실패한 것이고, 그러면 다음 바퀴가 전부 다시 그립니다 - 누수가 아니라
                    // 시험 입력이 잘못된 것입니다.
                    thumbnailsCached = host.Frames.Count(
                        candidate => thumbnails.TryGet(candidate.Id) is not null);
                    developedCached = host.Frames.Count(
                        candidate => thumbnails.TryGetDeveloped(candidate, out _));
                    (developedFrameLimit, developedByteLimit) = thumbnails.DevelopedLimits();
                    developedResidentCount = thumbnails.DevelopedResidentCount;
                    developedResidentBytes = thumbnails.DevelopedResidentBytes();
                }
            }
            }
            finally
            {
                thumbnails.DisposeAsync().AsTask().GetAwaiter().GetResult();
            }
        }

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();
        long afterCollect = PrivateBytes();
        long growth = afterLastPass - afterFirstPass;
        double perView = viewsAfterFirstPass > 0
            ? (double)growth / viewsAfterFirstPass
            : 0.0;
        double perViewLastPass = passes >= 2 && framesPerSize > 0
            ? (double)(afterLastPass - beforeLastPass) / framesPerSize
            : 0.0;
        return new SizeResult(
            megapixels,
            width,
            baseHeight,
            framesPerSize,
            passes,
            before,
            afterFirstPass,
            afterLastPass,
            peak,
            afterCollect,
            growth,
            perView,
            managedAfterFirstPass,
            managedAfterLastPass,
            managedAfterLastPass - managedAfterFirstPass,
            thumbnailsCached,
            developedCached,
            developedFrameLimit,
            developedByteLimit,
            developedResidentCount,
            developedResidentBytes,
            perViewLastPass,
            ceiling,
            overCeiling,
            overCeiling <= 0L,
            // 합격은 **둘 다** 입니다 - 다 찬 뒤 안 늘어야 하고(누수), 프로세스 총량이 자동
            // 상한 안이어야 합니다(작업 관리자에서 사용자가 보는 값).
            perViewLastPass <= AllowedGrowthPerViewBytes && overCeiling <= 0L);
    }

    /// <summary>한 프레임이 실제 앱에서 지나는 여섯 경로를 그대로 지납니다.</summary>
    private static void ExerciseOneFrame(
        PumpDispatcher dispatcher,
        LibraryHostService host,
        ThumbnailService thumbnails,
        PreviewCoordinator coordinator,
        DevelopPanelState panel,
        LibraryFrameSnapshot frame,
        int index,
        string paths)
    {
        // ② 라이브러리뷰 썸네일
        //
        // **결과가 나올 때까지 기다립니다.** `WaitUntilIdleAsync` 는 디스크 큐만 기다리므로
        // 그것만 믿으면 렌더가 끝나기 전에 다음 장으로 넘어가고, 캐시가 비어 있어 다음
        // 바퀴가 전부 다시 그립니다 - 그러면 제품이 아니라 시험이 새는 것을 재게 됩니다.
        if (paths.Contains('t', StringComparison.Ordinal))
        {
            thumbnails.Request(frame);
            WaitFor("library-thumbnail", frame.Id, () => thumbnails.TryGet(frame.Id) is not null);
        }
        // ④ 현상뷰·인화뷰 developed 프록시
        if (paths.Contains('d', StringComparison.Ordinal))
        {
            thumbnails.RequestDeveloped(frame, 2048);
            WaitFor(
                "developed-proxy", frame.Id, () => thumbnails.TryGetDeveloped(frame, out _));
        }
        // ③ 현상뷰 프리뷰 (정착까지 기다립니다)
        if (paths.Contains('p', StringComparison.Ordinal))
        {
            GrainMendPreviewLatency latency =
                GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, frame);
            if (latency.Failure is { Length: > 0 } failure)
            {
                Console.Error.WriteLine($"preview refused {frame.Id}: {failure}");
            }
        }
        // ⑥ 현상 프로세스와 현상 타깃 - 두 장에 한 번씩 바꿉니다.
        if (paths.Contains('r', StringComparison.Ordinal) && panel.Select(frame.Id))
        {
            _ = panel.SetDevelopmentProcess(
                (index % 2) == 0 ? DevelopmentProcess.C41 : DevelopmentProcess.E6);
            _ = DevelopDefaultsCommands.ApplyTarget(
                host,
                frame,
                (index % 3) switch
                {
                    0 => DevelopTarget.Main,
                    1 => DevelopTarget.Noritsu,
                    _ => DevelopTarget.Sp3000,
                });
        }
        // ⑤ 인화뷰 투영
        if (paths.Contains('n', StringComparison.Ordinal))
        {
            _ = PrintSourceSelection.Eligible(host.Frames).Count;
        }
        thumbnails.WaitUntilIdleAsync().GetAwaiter().GetResult();
    }

    /// <summary>조건이 참이 될 때까지 기다립니다. 시간이 지나면 그대로 진행합니다.</summary>
    /// <summary>엔진이 보는 메모리 내역입니다. 사람이 읽을 줄로 냅니다.</summary>
    internal static string MemoryReportText()
    {
        Negaflow.Interop.MemoryReport? report = Negaflow.Interop.MemoryReportBridge.TryRead();
        if (report is not { } value)
        {
            return "memory report unavailable";
        }
        Negaflow.Interop.GpuCacheInfo? gpu = Negaflow.Interop.GpuCacheBridge.TryRead();
        static string Mb(ulong bytes) => $"{bytes / (1024.0 * 1024.0):N0} MB";
        System.Text.StringBuilder text = new();
        text.AppendLine($"프로세스 private       {Mb(value.ProcessPrivateBytes)}");
        text.AppendLine($"자동 상한(프로세스)    {Mb(value.AutomaticProcessCeilingBytes)}");
        text.AppendLine(
            $"  디코드 원본          {Mb(value.DecodedSourceResidentBytes)} / " +
            $"{Mb(value.DecodedSourceBudgetBytes)}");
        text.AppendLine(
            $"  프리뷰 프록시        {Mb(value.PreviewProxyResidentBytes)} / " +
            $"{Mb(value.PreviewProxyBudgetBytes)}");
        text.AppendLine(
            $"  GPU 작업 텍스처      {Mb(value.GpuPoolResidentBytes)} / " +
            $"{Mb(value.GpuPoolLimitBytes)}");
        text.AppendLine(
            $"  GPU 스테이징(RAM)    {Mb(value.GpuSystemMemoryBytes)}  " +
            "(아래 '캐시 아닌 몫' 에 포함)");
        text.AppendLine($"  캐시 아닌 몫         {Mb(value.NonCacheOverheadBytes)}");
        if (gpu is { HasGpu: true } info)
        {
            text.AppendLine(
                $"GPU {info.AdapterDescription} " +
                $"{(info.IsIntegrated ? "내장" : "외장")} " +
                $"VRAM {Mb(info.DedicatedVideoMemoryBytes)} " +
                $"DXGI예산 {Mb(info.VideoMemoryBudgetBytes)} " +
                $"자동한도 {Mb(info.AutomaticLimitBytes)}");
        }
        else
        {
            text.AppendLine("GPU 없음");
        }
        return text.ToString().TrimEnd();
    }

    // 기다리다 못 받으면 **어느 경로가** 못 끝냈는지 남깁니다. 앞 판은 조용히 120초를
    // 흘려보내서, 48MP 가 멈춘 것인지 느린 것인지 구별할 수 없었습니다.
    private static void WaitFor(string what, string frameId, Func<bool> ready)
    {
        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        while (!ready() && clock.Elapsed < TimeSpan.FromSeconds(120))
        {
            Thread.Sleep(5);
        }
        if (!ready())
        {
            Console.Error.WriteLine(
                $"[대기 실패] {what} {frameId} {clock.Elapsed.TotalSeconds:N0}초");
        }
    }

    private sealed class StressThumbnailCodec : IThumbnailCodec
    {
        public byte[]? EncodeJpeg(byte[] bgra, int width, int height) => [0xFF, 0xD8];
    }

    private static long PrivateBytes()
    {
        using System.Diagnostics.Process process =
            System.Diagnostics.Process.GetCurrentProcess();
        process.Refresh();
        return process.PrivateMemorySize64;
    }

    private static void TryDeleteTree(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
        }
    }
}
