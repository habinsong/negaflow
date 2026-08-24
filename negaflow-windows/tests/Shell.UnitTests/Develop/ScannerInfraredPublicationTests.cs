using System.Collections.Concurrent;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class ScannerInfraredPublicationTests
{
    public static void Run()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "scanner-infrared-publication-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string visiblePath = Path.Combine(isolatedBase, "visible.tif");
        string infraredPath = Path.Combine(isolatedBase, "infrared.tif");
        const int width = 128;
        const int height = 96;
        try
        {
            Directory.CreateDirectory(isolatedBase);
            SyntheticNegativeTiff.WriteLuminance(
                visiblePath,
                Enumerable.Repeat(0.7F, width * height).ToArray(),
                width,
                height,
                16);
            SyntheticNegativeTiff.WriteLuminance(
                infraredPath,
                Enumerable.Repeat(0.8F, width * height).ToArray(),
                width,
                height,
                16);

            var dispatcher = new QueuedUiDispatcher();
            var selectionDelay = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            LibrarySourceMetadata? Metadata(string path) => new(
                (ulong)new FileInfo(path).Length,
                width,
                height,
                3,
                16,
                1,
                1);
            using var host = new LibraryHostService(
                dispatcher,
                new FakeExporter(_ => OkResult()),
                Metadata,
                _ => selectionDelay.Task);
            Check(host.Open(roots) == LibraryHostState.Open,
                "scanner_ir_attempt_library_open");

            var statuses = new List<InfraredCleanMessage>();
            host.InfraredCleanStatusChanged += (_, status) => statuses.Add(status.Message);
            ScannerFramePublishResult published = host.PublishScannerFrame(
                new ScannerFrameImport(
                    visiblePath,
                    infraredPath,
                    DevelopmentProcess.C41),
                new InfraredDetectorParameters { AlignmentSearchRadius = 0 });

            Check(
                published.Infrared?.Status == InfraredDefectApplyStatus.NoDefects &&
                statuses.SequenceEqual(
                    [InfraredCleanMessage.Detecting, InfraredCleanMessage.NoDefects]),
                "scanner_ir_attempt_runs_immediately_once");

            selectionDelay.SetResult();
            Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
                "scanner_ir_attempt_selection_delay_reaches_guard");
            dispatcher.Drain();
            Check(
                statuses.SequenceEqual(
                    [InfraredCleanMessage.Detecting, InfraredCleanMessage.NoDefects]),
                "scanner_ir_attempt_blocks_delayed_duplicate_after_no_defects");

            statuses.Clear();
            string failedVisiblePath = Path.Combine(isolatedBase, "visible-failed.tif");
            string failedInfraredPath = Path.Combine(isolatedBase, "infrared-failed.tif");
            SyntheticNegativeTiff.WriteLuminance(
                failedVisiblePath,
                Enumerable.Repeat(0.7F, width * height).ToArray(),
                width,
                height,
                16);
            File.WriteAllBytes(failedInfraredPath, [1, 2, 3, 4]);
            ScannerFramePublishResult failed = host.PublishScannerFrame(
                new ScannerFrameImport(
                    failedVisiblePath,
                    failedInfraredPath,
                    DevelopmentProcess.C41),
                new InfraredDetectorParameters { AlignmentSearchRadius = 0 });
            Check(
                failed.Infrared?.Status == InfraredDefectApplyStatus.DetectionFailed &&
                failed.Frame is not null &&
                statuses.SequenceEqual(
                    [InfraredCleanMessage.Detecting, InfraredCleanMessage.Failed]),
                "scanner_ir_confirmed_failure_runs_once");
            Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
                "scanner_ir_failure_pending_selection_reaches_guard");
            dispatcher.Drain();
            Check(
                statuses.SequenceEqual(
                    [InfraredCleanMessage.Detecting, InfraredCleanMessage.Failed]),
                "scanner_ir_failure_blocks_pending_duplicate");

            host.SetSelection([failed.Frame!.Id], failed.Frame.Id);
            Check(
                dispatcher.Count == 0 && statuses.SequenceEqual(
                    [InfraredCleanMessage.Detecting, InfraredCleanMessage.Failed]),
                "scanner_ir_failure_blocks_explicit_reselection_duplicate");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                try
                {
                    Directory.Delete(isolatedBase, true);
                }
                catch (IOException)
                {
                    // 시험 뒤처리 실패는 제품 결과가 아닙니다.
                }
            }
        }
    }

    private sealed class QueuedUiDispatcher : IUiDispatcher
    {
        private readonly ConcurrentQueue<Action> callbacks = new();

        public bool HasThreadAccess => true;

        public int Count => callbacks.Count;

        public bool TryEnqueue(Action callback)
        {
            callbacks.Enqueue(callback);
            return true;
        }

        public void Drain()
        {
            while (callbacks.TryDequeue(out Action? callback))
            {
                callback();
            }
        }
    }
}
