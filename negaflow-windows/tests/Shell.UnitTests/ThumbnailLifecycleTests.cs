using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;
using static Negaflow.Shell.UnitTests.DevelopTestResults;

namespace Negaflow.Shell.UnitTests;

internal static class ThumbnailLifecycleTests
{
    internal static void Run() => VerifyAsync().GetAwaiter().GetResult();
    private static async Task VerifyAsync()
    {
        string root = Path.Combine(Path.GetTempPath(), "negaflow-thumbnail-review-" + Guid.NewGuid().ToString("N"));
        try
        {
            var frame = Frame(null, sourcePath: Path.Combine(root, "source.tif"));
            using var started = new ManualResetEventSlim();
            using var release = new ManualResetEventSlim();
            var exporter = new PixelExporter((request, pixels) =>
            {
                pixels[0] = request.DevelopTarget == DevelopTargetMode.Main ? (byte)1 : (byte)2;
                if (pixels[0] == 1) { started.Set(); if (!release.Wait(5000)) { throw new TimeoutException(); } }
            });
            await using (var service = new ThumbnailService(exporter, new PixelCodec(), new FakeDispatcher(true), root))
            {
                Task old = service.RerenderAsync(frame);
                Check(started.Wait(5000), "thumbnail_old_target_started");
                await service.RerenderAsync(frame with { DevelopTarget = DevelopTarget.Hr });
                release.Set();
                await old;
                Check(service.TryGet(frame.Id)?[0] == 2, "thumbnail_old_target_never_overwrites_new_target");
            }
            using var encoding = new ManualResetEventSlim();
            using var encodeRelease = new ManualResetEventSlim();
            var delayedCodec = new PixelCodec(() => { encoding.Set(); if (!encodeRelease.Wait(5000)) { throw new TimeoutException(); } });
            await using (var service = new ThumbnailService(exporter, delayedCodec, new FakeDispatcher(true), root))
            {
                service.Publish(frame.Id, new byte[] { 7, 0, 0, 255 }, 1, 1);
                Check(encoding.Wait(5000), "thumbnail_encoding_started");
                service.Invalidate(frame.Id);
                encodeRelease.Set();
                await Task.Delay(100);
                await service.WaitUntilIdleAsync();
                Check(service.TryGet(frame.Id) is null, "thumbnail_invalidated_encoding_cannot_reappear");
            }
            started.Reset(); release.Reset();
            var pendingService = new ThumbnailService(exporter, new PixelCodec(), new FakeDispatcher(true), root);
            Task pending = pendingService.RerenderAsync(frame);
            Check(started.Wait(5000), "thumbnail_dispose_render_started");
            Task disposed = pendingService.DisposeAsync().AsTask();
            await Task.Delay(30);
            Check(!disposed.IsCompleted, "thumbnail_dispose_waits_for_active_render");
            release.Set();
            bool disposeRace = false;
            try { await pending; } catch (ObjectDisposedException) { disposeRace = true; }
            await disposed;
            Check(!disposeRace, "thumbnail_dispose_never_releases_disposed_semaphore");
        }
        finally { if (Directory.Exists(root)) { Directory.Delete(root, true); } }
    }

    internal sealed class PixelCodec(Action? before = null) : IThumbnailCodec
    {
        public byte[] EncodeJpeg(byte[] pixels, int width, int height) { before?.Invoke(); return [pixels[0]]; }
    }
    internal sealed class PixelExporter(Action<DevelopExportRequest, byte[]> render) : IDevelopExporter
    {
        public DevelopExportResult Preview(DevelopExportRequest request, uint maximumWidth, uint maximumHeight,
            byte[] pixels, DevelopRun? run = null, SoftProofSettings? softProof = null, bool clippingOverlay = false)
        { render(request, pixels); return OkResult(); }
        public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) => throw new NotSupportedException();
        public GrainMendDetectionResult DetectGrainMend(DevelopExportRequest request, DefectRect rawRoi,
            GrainMendDetectionOptions options, DevelopRun? run = null) => throw new NotSupportedException();
    }
}
