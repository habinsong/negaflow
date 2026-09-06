using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class PreviewRouteDeliveryTests
{
    internal static void Run() => VerifyAsync().GetAwaiter().GetResult();
    private static async Task VerifyAsync()
    {
        var frame = Frame(null, sourcePath: Path.Combine(Path.GetTempPath(), "preview-route.tif"));
        var changes = new LibraryFrameSnapshot[]
        {
            frame with { DevelopTarget = DevelopTarget.Hr },
            frame with { InputGamma = InputGammaInterpretation.Power(1.8) },
            frame with { Route = frame.Route with { FilmType = FilmType.BlackAndWhiteNegative } },
            frame with { SourcePath = Path.Combine(Path.GetTempPath(), "relinked.tif") },
            frame with { Id = "different" },
            frame with { Base = frame.Base with { Mode = BaseEstimationMode.Manual } },
        };
        foreach (var changed in changes.Append(frame with { Tone = frame.Tone with { Exposure = 0.5 } }))
        {
            int calls = 0;
            var dispatcher = new QueuedDispatcher();
            var exporter = new ThumbnailLifecycleTests.PixelExporter((_, pixels) => pixels[0] = (byte)Interlocked.Increment(ref calls));
            var preview = new PreviewCoordinator(exporter, dispatcher, 128, 128);
            List<byte> shown = [];
            void Show(PreviewOutcome result) { if (result.Pixels is { } pixels) { shown.Add(pixels[0]); } }
            await preview.RequestAsync(frame, Show);
            await preview.RequestAsync(changed, Show);
            dispatcher.Drain();
            bool discrete = PreviewCoordinator.PreviewRouteChanged(frame, changed);
            Check(shown.SequenceEqual(discrete ? new byte[] { 2 } : new byte[] { 1, 2 }),
                discrete ? "preview_discrete_route_rejects_queued_old_result" : "preview_tone_drag_keeps_interactive_progress");
            Check(!preview.IsRendering, "preview_route_transition_releases_run_state");
        }
        Check(!ThumbnailService.MatchesRecipe(frame, frame with { DevelopTarget = DevelopTarget.Hr }), "preview_current_recipe_rejects_old_target");
        Check(ThumbnailService.MatchesRecipe(frame, frame with { Rating = 3 }), "preview_mark_only_update_keeps_recipe");
        await VerifyInputGammaDraftAsync(frame);
    }

    private static async Task VerifyInputGammaDraftAsync(LibraryFrameSnapshot original)
    {
        var frame = original with { InputGamma = InputGammaInterpretation.Power(1.8), Base = original.Base with { Scale = 0.75 } };
        var dispatcher = new QueuedDispatcher();
        int calls = 0;
        var exporter = new ThumbnailLifecycleTests.PixelExporter((_, pixels) => pixels[0] = (byte)Interlocked.Increment(ref calls));
        var preview = new PreviewCoordinator(exporter, dispatcher, 128, 128);
        List<byte> shown = [];
        void Show(PreviewOutcome result)
        {
            Check(!result.Settled && result.CacheIdentity is null, "gamma_draft_is_not_a_committed_cache_result");
            if (result.Pixels is { } pixels) { shown.Add(pixels[0]); }
        }
        var first = DevelopInputEditor.Preview(frame, InputGammaInterpretation.Power(2.2));
        var second = DevelopInputEditor.Preview(frame, InputGammaInterpretation.Power(2.4));
        await preview.RequestInputGammaPreviewAsync(first, Show);
        await preview.RequestInputGammaPreviewAsync(second, Show);
        dispatcher.Drain();
        Check(shown.SequenceEqual(new byte[] { 1, 2 }), "gamma_drag_delivers_intermediate_frames");
        Check(frame.InputGamma.Value == 1.8 && frame.Base.Scale == 0.75, "gamma_draft_does_not_modify_stored_snapshot");
        Check(second.InputGamma.Value == 2.4 && second.Base.Scale == 0.75 && second.AppliedBase is null,
            "gamma_draft_preserves_scale_and_invalidates_old_measurement");
        var scanPreview = frame with { IsPreviewScan = true };
        Check(DevelopInputEditor.Preview(scanPreview, InputGammaInterpretation.Power(2.4)) == scanPreview,
            "scanner_preview_cannot_start_gamma_draft");
        shown.Clear();
        await preview.RequestInputGammaPreviewAsync(first, result => { if (result.Pixels is { } pixels) { shown.Add(pixels[0]); } });
        await preview.RequestAsync(frame, result => { if (result.Pixels is { } pixels) { shown.Add(pixels[0]); } });
        dispatcher.Drain();
        Check(shown.SequenceEqual(new byte[] { 4 }), "gamma_cancel_rejects_queued_draft_pixels");
    }
    private sealed class QueuedDispatcher : IUiDispatcher
    {
        private readonly Queue<Action> callbacks = new();
        public bool HasThreadAccess => false;
        public bool TryEnqueue(Action callback) { lock (callbacks) { callbacks.Enqueue(callback); } return true; }
        internal void Drain()
        {
            while (true)
            {
                Action? callback;
                lock (callbacks) { if (!callbacks.TryDequeue(out callback)) { return; } }
                callback();
            }
        }
    }
}
