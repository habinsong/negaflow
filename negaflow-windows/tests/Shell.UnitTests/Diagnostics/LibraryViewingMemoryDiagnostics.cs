using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Storage;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// "사진을 많이 볼수록 메모리가 늘어나는가" 를 결정적으로 잽니다.
/// </summary>
/// <remarks>
/// 설치 앱에서 본 14GB 는 <b>사진을 많이 본 뒤</b>의 값이고, 갓 띄운 값 8.6GB 와는 상황이
/// 달라 나란히 놓을 수 없습니다. 여기서는 같은 프로세스에서 사진을 한 장씩 늘려 가며 재고,
/// <b>상주 캐시 한도에 도달한 뒤에도 계속 오르는지</b>를 봅니다.
///
/// 한도까지 오르는 것은 설계입니다(<c>FrameCacheBudget</c>). 한도를 넘어 계속 오르면
/// 그것이 누수입니다. 표에는 장 수와 그때의 private bytes 를 그대로 남겨 어느 쪽인지
/// 사람이 직접 볼 수 있게 합니다.
/// </remarks>
internal static class LibraryViewingMemoryDiagnostics
{
    internal static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length is not (2 or 3) || args[0] != "--library-viewing-memory")
        {
            return false;
        }
        int passes = 1;
        if (args.Length == 3 && (!int.TryParse(args[2], out passes) || passes is < 1 or > 20))
        {
            Console.Error.WriteLine("passes must be 1..20");
            return true;
        }
        exitCode = Run(args[1], passes);
        return true;
    }

    private sealed record Sample(int Index, int Pass, string FrameId, long PrivateBytes);

    private static int Run(string folder, int passes)
    {
        string full = Path.GetFullPath(folder);
        if (!Directory.Exists(full))
        {
            Console.Error.WriteLine("folder not found: " + full);
            return 2;
        }

        string storageRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-view-memory-{Guid.NewGuid():N}");
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        List<Sample> samples = [];
        long before = PrivateBytes();
        long peak = before;
        try
        {
            using PumpDispatcher dispatcher = new();
            using LibraryHostService host = new(
                dispatcher,
                new NativeDevelopExporterAdapter(),
                sourceMetadataReader: null,
                token => Task.Delay(Timeout.Infinite, token));
            if (host.Open(roots) != LibraryHostState.Open)
            {
                Console.Error.WriteLine("catalog open refused");
                return 2;
            }
            if (host.ImportFolders([full], DevelopmentProcess.C41) is not { } imported ||
                imported.CatalogError != CatalogStoreError.None ||
                host.Frames.Count == 0)
            {
                Console.Error.WriteLine("folder import refused");
                return 2;
            }

            // 사진 한 장을 "본다" = 현상 캔버스가 그 장의 미리보기를 만들어 받는다.
            // 캔버스 크기는 실제 창과 같은 자리에서 재도록 2048x2048 로 둔다.
            var exporter = new NativeDevelopExporterAdapter();
            PreviewCoordinator coordinator = new(
                exporter, dispatcher, () => (2048L * 2048L));
            int index = 0;
            for (int pass = 1; pass <= passes; ++pass)
            {
                foreach (LibraryFrameSnapshot frame in host.Frames.ToArray())
                {
                    GrainMendPreviewLatency latency =
                        GrainMendPreviewLatencyProbe.Measure(dispatcher, coordinator, frame);
                    if (latency.Failure is { Length: > 0 } failure)
                    {
                        Console.Error.WriteLine($"preview refused {frame.Id}: {failure}");
                    }
                    long now = PrivateBytes();
                    peak = Math.Max(peak, now);
                    samples.Add(new Sample(++index, pass, frame.Id, now));
                }
            }

            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            long after = PrivateBytes();

            long firstPassEnd = samples
                .Where(sample => sample.Pass == 1)
                .Select(sample => sample.PrivateBytes)
                .DefaultIfEmpty(before)
                .Last();
            long lastPassEnd = samples
                .Select(sample => sample.PrivateBytes)
                .DefaultIfEmpty(before)
                .Last();

            Console.WriteLine(JsonSerializer.Serialize(
                new
                {
                    status = "ok",
                    operation = "library_viewing_memory",
                    frames = host.Frames.Count,
                    passes,
                    views = samples.Count,
                    privateBytes = new
                    {
                        before,
                        afterFirstPass = firstPassEnd,
                        afterLastPass = lastPassEnd,
                        peak,
                        afterCollect = after,
                        // 첫 바퀴 뒤로도 계속 오르면 그것이 판정선입니다.
                        growthAfterFirstPass = lastPassEnd - firstPassEnd,
                    },
                    samples,
                },
                new JsonSerializerOptions { WriteIndented = true }));
            return 0;
        }
        finally
        {
            TryDeleteTree(storageRoot);
        }
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
