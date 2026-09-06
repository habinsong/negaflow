using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
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
