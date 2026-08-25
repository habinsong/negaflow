using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 가상 스캔 수백~수천 장으로 메모리 누수를 잡고, 프로세스가 자동 상한 안에 있는지 봅니다.
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
/// 판정은 <b>둘 다</b> 봅니다.
///
/// <list type="number">
/// <item>
/// <b>마지막 한 바퀴</b>의 뷰당 증가. 첫 바퀴 뒤라도 캐시는 아직 예산까지 차오르는
/// 중일 수 있고 그 차오름은 설계입니다 - 다 찬 뒤에도 늘면 그때가 누수입니다.
/// </item>
/// <item>
/// <b>프로세스 전체가 자동 상한 안</b>인지. 작업 관리자에서 사용자가 보는 값입니다.
/// 캐시가 저마다 자기 예산 안이어도 코드·런타임·WinUI·D3D11 스테이징까지 합치면
/// 넘을 수 있습니다 - 실제로 그래서 넘었습니다(§24).
/// </item>
/// </list>
///
/// 기본은 <b>가상 스캔</b>입니다 - 사용자의 사진을 쓰지 않습니다. 가상본이 통과한 뒤
/// 실제 카탈로그로 확인할 때는 <c>--memory-stress-folder</c> 를 씁니다. 그쪽도 여기와
/// <b>같은 경로·같은 판정</b>을 지나며, 소스 파일은 읽기만 합니다.
/// </remarks>
internal static partial class MemoryStressDiagnostics
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
        // 다른 프로세스(설치 앱)의 커밋 영역을 크기별로 셉니다. 총량만 봐서는 "무엇이
        // 들고 있는가" 를 못 가립니다 - 화상 버퍼는 크기가 딱 떨어지므로 히스토그램이
        // 바로 답을 줍니다.
        if (args.Length >= 2 && args[0] == "--process-map" &&
            int.TryParse(args[1], out int mapPid))
        {
            Console.WriteLine(ProcessRegionMap.Report(mapPid));
            return true;
        }
        // 지금 이 프로세스의 메모리 내역을 그대로 냅니다. 예산이 프로세스 전체를 상한 안에
        // 두는지 판정하는 자리입니다.
        if (args.Length >= 1 && args[0] == "--memory-report")
        {
            Console.WriteLine(MemoryReportText());
            return true;
        }
        // 실제 카탈로그 폴더로 같은 시험을 돕니다. 합성본과 **같은** `RunSize` 를 지나므로
        // 판정선도 같습니다 - 두 벌로 나누면 어느 한쪽만 고치게 됩니다.
        if (args.Length >= 2 && args[0] == "--memory-stress-folder")
        {
            string folder = Path.GetFullPath(args[1]);
            if (!Directory.Exists(folder))
            {
                Console.Error.WriteLine("folder not found: " + folder);
                exitCode = 2;
                return true;
            }
            int folderPasses =
                args.Length > 2 && int.TryParse(args[2], out int folderLoops) ? folderLoops : 3;
            string folderPaths = args.Length > 3 ? args[3] : "tdprn";
            exitCode = RunFolder(folder, folderPasses, folderPaths);
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
        // 마지막 한 바퀴의 뷰당 시간입니다. 예산이 줄면 캐시 적중이 줄어 다시 그리는 일이
        // 늘어납니다 - 상한을 지키면서 느려지지 않았는지 보는 자리입니다.
        double MillisecondsPerViewInLastPass,
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

    /// <summary>
    /// 실제 카탈로그 폴더로 돕니다. 소스는 <b>읽기만</b> 합니다 - 이 진단은 어떤 굽기도
    /// 하지 않으며, 카탈로그와 캐시는 임시 폴더에 만들고 끝나면 지웁니다.
    /// </summary>
    private static int RunFolder(string folder, int passes, string paths)
    {
        string root = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-stress-folder-{Guid.NewGuid():N}");
        List<Sample> samples = [];
        try
        {
            SizeResult result = RunSize(root, 0, 0, passes, samples, paths, folder);
            Console.Error.WriteLine(MemoryReportText());
            Console.Error.WriteLine(ProcessRegionMap.Report());
            Console.WriteLine(JsonSerializer.Serialize(
                new
                {
                    status = "ok",
                    operation = "memory_stress_folder",
                    folder,
                    passed = result.Passed,
                    results = new[] { result },
                    samples,
                },
                new JsonSerializerOptions { WriteIndented = true }));
            return result.Passed ? 0 : 1;
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
        string paths,
        string? existingFolder = null)
    {
        (int width, int baseHeight) = megapixels > 0
            ? SyntheticScanWriter.ExtentForMegapixels(megapixels)
            : (0, 0);
        string sourceFolder = existingFolder ?? Path.Combine(root, $"src-{megapixels}mp");
        string storageRoot = Path.Combine(root, $"store-{megapixels}mp");
        if (existingFolder is null)
        {
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
        System.Diagnostics.Stopwatch lastPassClock = new();
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
                host.Frames.Count == 0 ||
                (existingFolder is null && host.Frames.Count != framesPerSize))
            {
                throw new InvalidOperationException(
                    $"folder import refused: frames={host.Frames.Count} expected={framesPerSize}");
            }
            // 실제 폴더는 몇 장인지 모른 채 들어옵니다. 판정에 쓰는 장수를 실제 값으로 맞춥니다.
            framesPerSize = host.Frames.Count;

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
                if (pass == passes)
                {
                    lastPassClock.Restart();
                }
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
                if (pass == passes)
                {
                    lastPassClock.Stop();
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
        double millisecondsPerView = framesPerSize > 0
            ? lastPassClock.Elapsed.TotalMilliseconds / framesPerSize
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
            millisecondsPerView,
            ceiling,
            overCeiling,
            overCeiling <= 0L,
            // 합격은 **둘 다** 입니다 - 다 찬 뒤 안 늘어야 하고(누수), 프로세스 총량이 자동
            // 상한 안이어야 합니다(작업 관리자에서 사용자가 보는 값).
            perViewLastPass <= AllowedGrowthPerViewBytes && overCeiling <= 0L);
    }
}
