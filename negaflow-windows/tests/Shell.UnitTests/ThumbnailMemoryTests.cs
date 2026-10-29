using Negaflow.Shell.Library;
using Negaflow.Catalog;
using Negaflow.Interop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class ThumbnailMemoryTests
{
    internal static void Run()
    {
        var cache = new ThumbnailMemoryCache();
        cache.SetLimit(8);
        var first = new ThumbnailCacheEntry(new byte[4], null);
        var second = new ThumbnailCacheEntry(new byte[4], null);
        cache.Store("a", first); cache.Store("b", second);
        Check(cache.TryGetValue("a", out _), "thumbnail_recent_access_is_recorded");
        cache.Store("c", new(new byte[4], null));
        Check(!cache.TryGetValue("b", out _) && cache.TryGetValue("a", out _), "thumbnail_evicts_least_recent_bytes");
        cache.SetLimit(0);
        Check(cache.Count == 0 && cache.ResidentBytes == 0, "critical_pressure_releases_all_idle_jpeg_bytes");
        cache.BeginDelivery("a", first);
        try
        {
            cache.Store("b", second);
            Check(cache.TryGetValue("a", out var shown) && ReferenceEquals(shown, first),
                "queued_thumbnail_ready_can_read_its_evicted_jpeg_during_delivery");
        }
        finally { cache.EndDelivery("a"); }
        Check(cache.ResidentBytes == 0, "thumbnail_delivery_releases_its_temporary_pin");
        cache.SetLimit(64);
        Parallel.For(0, 2_000, index => cache.Store(index.ToString(), new(new byte[8], null)));
        Check(cache.ResidentBytes <= 64 && cache.Count <= 8, "parallel_thumbnail_production_stays_bounded");
        cache.Clear();
        Check(cache.Count == 0 && cache.ResidentBytes == 0, "thumbnail_cache_clear_releases_residents");
        VerifyServiceAsync().GetAwaiter().GetResult();
        VerifyQueuedDeliveryAsync().GetAwaiter().GetResult();
    }

    private sealed class QueuedDispatcher : IUiDispatcher
    {
        private readonly System.Collections.Concurrent.ConcurrentQueue<Action> queue = new();
        public bool HasThreadAccess => false;
        public bool TryEnqueue(Action callback) { queue.Enqueue(callback); return true; }
        internal void Drain() { while (queue.TryDequeue(out var action)) { action(); } }
    }

    private static async Task VerifyQueuedDeliveryAsync()
    {
        string root = Path.Combine(Path.GetTempPath(), "negaflow-thumbnail-delivery-" + Guid.NewGuid().ToString("N"));
        try
        {
            var dispatcher = new QueuedDispatcher();
            var exporter = new ThumbnailLifecycleTests.PixelExporter((request, pixels) =>
                pixels[0] = request.DevelopTarget == DevelopTargetMode.Main ? (byte)1 : (byte)2);
            await using var service = new ThumbnailService(exporter,
                new ThumbnailLifecycleTests.PixelCodec(), dispatcher, root);
            var frame = TestFrameFactory.Frame(null, sourcePath: Path.Combine(root, "source.tif"));
            int deliveries = 0;
            service.ThumbnailReady += id =>
            {
                deliveries++;
                Check(service.TryGet(id)?[0] == 2, "queued_delivery_exposes_current_jpeg_under_zero_budget");
            };
            await service.RerenderAsync(frame);
            await service.RerenderAsync(frame with { DevelopTarget = DevelopTarget.Hr });
            service.ApplyMemoryPressure(FrameCachePressureLevel.Critical);
            Check(service.ThumbnailResidentBytes == 0, "pressure_evicts_jpeg_before_queued_delivery");
            dispatcher.Drain();
            Check(deliveries == 1 && service.ThumbnailResidentBytes == 0,
                "stale_ui_delivery_cannot_refill_cache_or_replace_new_recipe");
        }
        finally { if (Directory.Exists(root)) { Directory.Delete(root, true); } }
    }

    private static async Task VerifyServiceAsync()
    {
        string root = Path.Combine(Path.GetTempPath(), "negaflow-thumbnail-memory-" + Guid.NewGuid().ToString("N"));
        try
        {
            await using var service = new ThumbnailService(
                new ThumbnailLifecycleTests.PixelExporter((_, _) => { }),
                new ThumbnailLifecycleTests.PixelCodec(), new FakeDispatcher(true), root);
            service.ApplyResidencySettings(new() { Mode = FrameCacheResidencyMode.Manual, ManualCleanedRaw = 2, ManualDeveloped = 3 });
            long budget = FrameCacheBudget.DevelopedDisplayBudgetBytes(new(2, 3));
            byte[] pixels = new byte[4];
            for (int i = 0; i < 20; i++) { service.RememberDeveloped(i.ToString(), pixels, 1, 1, true); }
            service.ApplyMemoryPressure(FrameCachePressureLevel.Critical);
            Check(service.DevelopedLimits().Frames == 1 && service.ThumbnailResidentBytes == 0,
                "service_pressure_trims_bgra_and_jpeg");
            service.ApplyResidencySettings(new() { Mode = FrameCacheResidencyMode.Manual, ManualCleanedRaw = 2, ManualDeveloped = 3 });
            Check(service.DevelopedLimits().Frames == 1, "service_settings_keep_pressure_clamp");
            service.ApplyMemoryPressure(FrameCachePressureLevel.Normal);
            Check(service.DevelopedLimits().Frames == 3 && service.DevelopedLimits().Bytes <= budget,
                "service_pressure_recovery_restores_manual_budget");
        }
        finally { if (Directory.Exists(root)) { Directory.Delete(root, true); } }
    }
}
