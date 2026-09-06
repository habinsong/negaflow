using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;
using static Negaflow.Shell.UnitTests.DevelopTestResults;

namespace Negaflow.Shell.UnitTests;

internal static class ThumbnailCacheRegressionTests
{
    internal static void Run() => VerifyAsync().GetAwaiter().GetResult();
    private static async Task VerifyAsync()
    {
        string root = Path.Combine(Path.GetTempPath(), "negaflow-thumb-cache-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var frame = Frame(null, sourcePath: Path.Combine(root, "source.tif"));
            int calls = 0;
            var normal = new Renderer((request, _, pixels) =>
            {
                Interlocked.Increment(ref calls);
                pixels[0] = request.DevelopTarget == DevelopTargetMode.Main ? (byte)1 : (byte)2;
                return OkResult();
            });
            await using (var service = New(normal, root)) { await service.RerenderAsync(frame); }
            await using (var service = New(normal, root))
            {
                service.TryGetOrLoad(frame);
                await service.WaitUntilIdleAsync();
                Check(calls == 1 && service.TryGet(frame.Id)?[0] == 1, "thumbnail_restart_reuses_matching_recipe");
                var changed = frame with { DevelopTarget = DevelopTarget.Hr };
                service.TryGetOrLoad(changed);
                await service.WaitUntilIdleAsync();
                Check(calls == 2 && service.TryGet(frame.Id)?[0] == 2, "thumbnail_restart_mismatch_renders_current_target");
            }
            using var started = new ManualResetEventSlim();
            using var release = new ManualResetEventSlim();
            calls = 0;
            var delayed = new Renderer((request, _, pixels) =>
            {
                Interlocked.Increment(ref calls);
                pixels[0] = request.DevelopTarget == DevelopTargetMode.Main ? (byte)1 : (byte)2;
                if (pixels[0] == 1) { started.Set(); if (!release.Wait(5000)) { throw new TimeoutException(); } }
                return OkResult();
            });
            await using (var service = New(delayed, Path.Combine(root, "dedup")))
            {
                Parallel.For(0, 24, _ => service.Request(frame));
                Check(started.Wait(5000), "thumbnail_single_flight_started");
                Check(calls == 1, "thumbnail_same_request_starts_once");
                var second = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                service.ThumbnailReady += id => { if (service.TryGet(id)?[0] == 2) { second.TrySetResult(); } };
                service.Request(frame with { DevelopTarget = DevelopTarget.Hr });
                await second.Task.WaitAsync(TimeSpan.FromSeconds(5));
                release.Set();
                await service.WaitUntilIdleAsync();
                Check(calls == 2 && service.TryGet(frame.Id)?[0] == 2, "thumbnail_new_request_is_not_lost_behind_old_work");
            }
            started.Reset(); release.Reset();
            await using (var service = New(delayed, Path.Combine(root, "cancel")))
            {
                using var cancel = new CancellationTokenSource();
                Task rendering = service.RerenderAsync(frame, cancel.Token);
                Check(started.Wait(5000), "thumbnail_cancel_started");
                cancel.Cancel(); release.Set();
                try { await rendering; } catch (OperationCanceledException) { }
                Check(service.TryGet(frame.Id) is null, "thumbnail_cancelled_render_is_not_published");
            }
            string legacyRoot = Path.Combine(root, "legacy");
            Directory.CreateDirectory(Path.Combine(legacyRoot, "fr"));
            File.WriteAllBytes(Path.Combine(legacyRoot, "fr", frame.Id + ".jpg"), [8]);
            await using (var service = New(new Renderer((_, _, _) => FailedResult("offline")), legacyRoot))
            {
                Check(service.TryGetOrLoad(frame)?[0] == 8, "thumbnail_offline_legacy_cache_remains_visible");
                await service.WaitUntilIdleAsync();
                Check(service.TryGet(frame.Id)?[0] == 8, "thumbnail_failed_refresh_preserves_visible_fallback");
            }
            await VerifyProofAsync(frame, root);
            await VerifyLateProofAsync(frame, root);
            await VerifyInvalidDimensionsAsync(frame, root);
            await using (var disk = new ThumbnailDiskCache())
            {
                await disk.DisposeAsync();
                await disk.WaitUntilIdleAsync().WaitAsync(TimeSpan.FromSeconds(2));
                await disk.ClearAsync(Path.Combine(root, "closed")).WaitAsync(TimeSpan.FromSeconds(2));
                Check(true, "thumbnail_closed_disk_queue_never_strands_waiters");
            }
            VerifyPayload();
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task VerifyProofAsync(LibraryFrameSnapshot frame, string root)
    {
        var proof = new SoftProofSettings(true, SoftProofSimulation.PaperAndBlackInk, SoftProofRgb.White, SoftProofRgb.Black);
        var renderer = new Renderer((_, requested, pixels) => { pixels[0] = requested?.IsEnabled == true ? (byte)9 : (byte)3; return OkResult(); });
        await using var service = New(renderer, Path.Combine(root, "proof"));
        service.SetPrintProof(proof);
        service.RequestDeveloped(frame, 128);
        await service.WaitUntilIdleAsync();
        Check(service.TryGetForProof(frame.Id, proof, out var printed) && printed.Pixels[0] == 9,
            "print_proof_preview_is_available_to_print");
        Check(!service.TryGetDeveloped(frame.Id, out _), "print_proof_pixels_never_become_normal_preview");
        service.PublishFromDeveloped(frame.Id);
        await service.WaitUntilIdleAsync();
        Check(service.TryGet(frame.Id) is null, "print_proof_pixels_never_become_library_thumbnail");
        service.SetPrintProof(null);
        service.RequestDeveloped(frame, 128);
        await service.WaitUntilIdleAsync();
        Check(service.TryGetDeveloped(frame.Id, out var normal) && normal.Pixels[0] == 3,
            "normal_preview_recovers_after_proof_disabled");
    }

    private static async Task VerifyLateProofAsync(LibraryFrameSnapshot frame, string root)
    {
        using var started = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var renderer = new Renderer((_, proof, pixels) =>
        {
            pixels[0] = proof?.IsEnabled == true ? (byte)9 : (byte)3;
            if (pixels[0] == 9) { started.Set(); if (!release.Wait(5000)) { throw new TimeoutException(); } }
            return OkResult();
        });
        await using var service = New(renderer, Path.Combine(root, "late-proof"));
        var finished = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        service.ThumbnailReady += id => { if (service.TryGetDeveloped(id, out var current) && current.Pixels[0] == 3) { finished.TrySetResult(); } };
        service.SetPrintProof(new SoftProofSettings(true, SoftProofSimulation.ProfileOnly, SoftProofRgb.White, SoftProofRgb.Black));
        service.RequestDeveloped(frame, 128);
        Check(started.Wait(5000), "print_old_proof_request_started");
        service.SetPrintProof(null);
        service.RequestDeveloped(frame, 128);
        await finished.Task.WaitAsync(TimeSpan.FromSeconds(5));
        release.Set();
        await service.WaitUntilIdleAsync();
        Check(service.TryGetDeveloped(frame.Id, out var actual) && actual.Pixels[0] == 3,
            "print_old_proof_cannot_publish_after_profile_switch");
    }

    private static async Task VerifyInvalidDimensionsAsync(LibraryFrameSnapshot frame, string root)
    {
        var renderer = new Renderer((_, _, _) => new DevelopExportResult(
            true, DevelopExportStage.None, "bad dimensions", 0, 0, 1000, 1000,
            FilmLookRoute.Identity, false, false, 0, 0, 0, 0));
        await using var service = New(renderer, Path.Combine(root, "bounds"));
        bool rendered = await service.RerenderAsync(frame);
        Check(!rendered, "thumbnail_failed_render_does_not_report_success");
        service.RequestDeveloped(frame, 128);
        await service.WaitUntilIdleAsync();
        Check(service.TryGet(frame.Id) is null && service.DevelopedResidentCount == 0,
            "thumbnail_rejects_native_dimensions_larger_than_buffers");
    }

    private static void VerifyPayload()
    {
        var identity = new ThumbnailCacheIdentity("recipe", "source");
        byte[] encoded = ThumbnailCachePayload.Encode([3, 4, 5], identity);
        var decoded = ThumbnailCachePayload.Decode(encoded);
        Check(decoded?.Identity == identity && decoded.Jpeg.SequenceEqual(new byte[] { 3, 4, 5 }), "thumbnail_cache_payload_roundtrip");
        Check(ThumbnailCachePayload.Decode(encoded[..10]) is null, "thumbnail_truncated_header_is_not_an_image");
        Check(new ThumbnailCacheIdentity("other", "source").Accepts(identity) == false, "thumbnail_recipe_mismatch_is_not_current");
        Check(new ThumbnailCacheIdentity("recipe", "changed").Accepts(identity) == false, "thumbnail_source_stamp_mismatch_is_not_current");
    }

    private static ThumbnailService New(IDevelopExporter renderer, string root) =>
        new(renderer, new ThumbnailLifecycleTests.PixelCodec(), new FakeDispatcher(true), root);

    private sealed class Renderer(Func<DevelopExportRequest, SoftProofSettings?, byte[], DevelopExportResult> action) : IDevelopExporter
    {
        public DevelopExportResult Preview(DevelopExportRequest request, uint maximumWidth, uint maximumHeight,
            byte[] pixels, DevelopRun? run = null, SoftProofSettings? softProof = null, bool clippingOverlay = false) => action(request, softProof, pixels);
        public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) => throw new NotSupportedException();
        public GrainMendDetectionResult DetectGrainMend(DevelopExportRequest request, DefectRect rawRoi,
            GrainMendDetectionOptions options, DevelopRun? run = null) => throw new NotSupportedException();
    }
}
