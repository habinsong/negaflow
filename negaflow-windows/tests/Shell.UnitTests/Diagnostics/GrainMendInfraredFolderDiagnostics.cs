using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;

namespace Negaflow.Shell.UnitTests;

/// <summary>실제 폴더의 visible/IR 쌍 전체를 import→IR 적용→catalog 재열기까지 검증합니다.</summary>
internal static class GrainMendInfraredFolderDiagnostics
{
    private sealed class PrivateBytesSampler : IDisposable
    {
        private readonly CancellationTokenSource stop = new();
        private readonly Thread thread;
        private long peak;

        public PrivateBytesSampler(long initial)
        {
            peak = initial;
            thread = new Thread(Run)
            {
                IsBackground = true,
                Name = "GrainMend IR memory sampler",
            };
            thread.Start();
        }

        public long Peak => Interlocked.Read(ref peak);

        public void Dispose()
        {
            stop.Cancel();
            thread.Join();
            stop.Dispose();
        }

        private void Run()
        {
            while (!stop.IsCancellationRequested)
            {
                long sample = PrivateBytes();
                long current = Interlocked.Read(ref peak);
                while (sample > current &&
                    Interlocked.CompareExchange(ref peak, sample, current) != current)
                {
                    current = Interlocked.Read(ref peak);
                }
                Thread.Sleep(10);
            }
        }
    }

    private sealed record ApplySample(
        string Visible,
        string Infrared,
        double Milliseconds,
        int DefectCount,
        string Status,
        int InfraredLayerCount,
        string? RecipeSha,
        string? Failure);

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--grainmend-ir-folder-check")
        {
            return false;
        }
        if (args.Length is < 2 or > 3 ||
            !int.TryParse(args.ElementAtOrDefault(2) ?? "22", out int expectedPairs) ||
            expectedPairs is < 1 or > 1_000)
        {
            Console.Error.WriteLine(
                "usage: --grainmend-ir-folder-check <folder> [expectedPairs=22]");
            exitCode = 2;
            return true;
        }
        exitCode = Run(Path.GetFullPath(args[1]), expectedPairs);
        return true;
    }

    private static int Run(string folder, int expectedPairs)
    {
        if (!Directory.Exists(folder))
        {
            Console.Error.WriteLine("infrared folder unavailable");
            return 2;
        }
        if (!FolderImport.TryEnumerateLeafImages(
                folder,
                out IReadOnlyList<string> files,
                out FolderImportRefusal refusal))
        {
            Console.Error.WriteLine($"infrared folder refused: {refusal}");
            return 2;
        }
        InfraredImportPairing.Resolution pairing = InfraredImportPairing.Resolve(files);
        if (pairing.BasePaths.Count != expectedPairs ||
            pairing.PairedInfraredPaths.Count != expectedPairs ||
            files.Count != expectedPairs * 2)
        {
            Console.Error.WriteLine(
                $"pair matrix mismatch: files={files.Count} bases={pairing.BasePaths.Count} " +
                $"infrared={pairing.PairedInfraredPaths.Count}");
            return 2;
        }

        string storageRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-gm-ir-folder-{Guid.NewGuid():N}");
        if (StorageRootResolver.ResolveForTests(storageRoot).Roots is not { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        List<ApplySample> samples = [];
        long privateBefore = PrivateBytes();
        long peakPrivate = privateBefore;
        using PrivateBytesSampler privateSampler = new(privateBefore);
        bool imported = false;
        try
        {
            using (PumpDispatcher seedDispatcher = new())
            using (LibraryHostService seedHost = new(
                seedDispatcher,
                new NativeDevelopExporterAdapter(),
                sourceMetadataReader: null,
                token => Task.Delay(Timeout.Infinite, token)))
            {
                imported = seedHost.Open(roots) == LibraryHostState.Open &&
                    seedHost.ImportFolders([folder], DevelopmentProcess.C41) is { } result &&
                    result.CatalogError == CatalogStoreError.None &&
                    result.AddedFrameCount == expectedPairs &&
                    seedHost.Frames.Count == expectedPairs &&
                    seedHost.Frames.All(frame => frame.InfraredPath is not null) &&
                    seedHost.Frames.All(frame =>
                        InfraredImportPairing.InfraredCoreName(frame.SourcePath) is null);
            }
            if (!imported)
            {
                Console.Error.WriteLine("infrared folder import refused");
                return 1;
            }

            using (PumpDispatcher dispatcher = new())
            using (LibraryHostService host = new(dispatcher))
            {
                if (host.Open(roots) != LibraryHostState.Open || host.Frames.Count != expectedPairs)
                {
                    Console.Error.WriteLine("infrared catalog reopen refused");
                    return 1;
                }
                foreach (LibraryFrameSnapshot frame in host.Frames.ToArray())
                {
                    samples.Add(Apply(dispatcher, host, frame));
                    peakPrivate = Math.Max(peakPrivate, PrivateBytes());
                }
            }

            int restartFrameCount = 0;
            int restartPairedCount = 0;
            int restartLayerCount = 0;
            int libraryProjectionCount = 0;
            int developSelectionCount = 0;
            int printProjectionCount = 0;
            using (PumpDispatcher verifyDispatcher = new())
            using (LibraryHostService verifyHost = new(
                verifyDispatcher,
                new NativeDevelopExporterAdapter(),
                sourceMetadataReader: null,
                token => Task.Delay(Timeout.Infinite, token)))
            {
                if (verifyHost.Open(roots) == LibraryHostState.Open)
                {
                    restartFrameCount = verifyHost.Frames.Count;
                    restartPairedCount = verifyHost.Frames.Count(frame =>
                        frame.InfraredPath is { } infrared && File.Exists(infrared));
                    restartLayerCount = verifyHost.Frames.Count(frame =>
                        frame.DefectRecipe?.Items.Count(item =>
                            item.Kind == DefectEditKind.Infrared) == 1);
                    libraryProjectionCount = LibraryFrameListItems.From(verifyHost.Frames).Count;
                    var panel = new DevelopPanelState(
                        verifyHost,
                        ToneLimits.Read(),
                        NegativeLimits.Read());
                    developSelectionCount = verifyHost.Frames.Count(frame => panel.Select(frame.Id));
                    printProjectionCount = PrintSourceSelection.Eligible(verifyHost.Frames).Count;
                }
            }

            GC.Collect();
            GC.WaitForPendingFinalizers();
            GC.Collect();
            long privateAfter = PrivateBytes();
            GrainMendLatencySummary latency = GrainMendPerformanceStatistics.Summarize(
                samples.Select(sample => sample.Milliseconds));
            bool assetContractPassed = samples.Count == expectedPairs &&
                samples.All(sample => sample.Failure is null &&
                    sample.Status == InfraredCleanMessage.Applied.ToString() &&
                    sample.InfraredLayerCount == 1) &&
                restartFrameCount == expectedPairs &&
                restartPairedCount == expectedPairs &&
                restartLayerCount == expectedPairs &&
                libraryProjectionCount == expectedPairs &&
                developSelectionCount == expectedPairs &&
                printProjectionCount == expectedPairs;
            const long allowedRetainedBytes = 512L * 1024L * 1024L;
            long retainedBytes = Math.Max(0L, privateAfter - privateBefore);
            bool latencyTargetPassed = latency.P95Milliseconds <= 1_000.0;
            bool memoryTargetPassed = retainedBytes <= allowedRetainedBytes;
            bool passed = assetContractPassed && latencyTargetPassed && memoryTargetPassed;
            Console.WriteLine(JsonSerializer.Serialize(new
            {
                status = passed ? "ok" : "failed",
                operation = "grainmend_ir_folder_check",
                evidenceBoundary = "actual files through folder import, LibraryHost IR apply, sidecar/catalog restart, and three managed workspace projections; not installed WinUI composition",
                folder,
                inputFileCount = files.Count,
                visiblePairCount = pairing.BasePaths.Count,
                hiddenInfraredFileCount = pairing.PairedInfraredPaths.Count,
                independentInfraredFrameRows = restartFrameCount - restartPairedCount,
                assetContractPassed,
                latencyTargetPassed,
                memoryTargetPassed,
                restartFrameCount,
                restartPairedCount,
                restartLayerCount,
                libraryProjectionCount,
                developSelectionCount,
                printProjectionCount,
                latency,
                privateBytes = new
                {
                    before = privateBefore,
                    postApplySamplePeak = peakPrivate,
                    highFrequencyPeak = privateSampler.Peak,
                    sampleIntervalMilliseconds = 10,
                    after = privateAfter,
                    retained = retainedBytes,
                    allowedRetained = allowedRetainedBytes,
                },
                samples,
            }, new JsonSerializerOptions { WriteIndented = true }));
            return passed ? 0 : 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(storageRoot))
                {
                    Directory.Delete(storageRoot, recursive: true);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }

    private static ApplySample Apply(
        PumpDispatcher dispatcher,
        LibraryHostService host,
        LibraryFrameSnapshot frame)
    {
        using ManualResetEventSlim completed = new();
        InfraredCleanStatus final = InfraredCleanStatus.Silent;
        string? failure = null;
        void Status(string frameId, InfraredCleanStatus status)
        {
            if (!string.Equals(frameId, frame.Id, StringComparison.Ordinal) ||
                status.Message == InfraredCleanMessage.Detecting)
            {
                return;
            }
            final = status;
            completed.Set();
        }
        host.InfraredCleanStatusChanged += Status;
        Stopwatch clock = Stopwatch.StartNew();
        dispatcher.Send(() => host.SetSelection([frame.Id], frame.Id));
        if (!completed.Wait(TimeSpan.FromSeconds(120)))
        {
            failure = "infrared apply timeout";
        }
        clock.Stop();
        host.InfraredCleanStatusChanged -= Status;

        LibraryFrameSnapshot? updated = host.Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frame.Id, StringComparison.Ordinal));
        int layerCount = updated?.DefectRecipe?.Items.Count(item =>
            item.Kind == DefectEditKind.Infrared) ?? 0;
        string? recipeSha = updated?.DefectRecipe is { } recipe
            ? GrainMendQualitySignature.FromRecipe(recipe)
            : null;
        if (failure is null && (final.Message != InfraredCleanMessage.Applied || layerCount != 1))
        {
            failure = $"final={final.Message} layers={layerCount}";
        }
        return new ApplySample(
            Path.GetFileName(frame.SourcePath),
            Path.GetFileName(frame.InfraredPath ?? string.Empty),
            Math.Round(clock.Elapsed.TotalMilliseconds, 1),
            final.DefectCount,
            final.Message.ToString(),
            layerCount,
            recipeSha,
            failure);
    }

    private static long PrivateBytes()
    {
        using Process process = Process.GetCurrentProcess();
        process.Refresh();
        return process.PrivateMemorySize64;
    }
}
