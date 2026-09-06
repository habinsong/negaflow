using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class SliderPointerSessionTests
{
    public static void Run()
    {
        foreach (bool replaceSource in new[] { false, true })
        {
            var state = new SliderPointerSession();
            state.Begin("first", "first.tif");
            string owner = replaceSource ? "first" : "second";
            string source = replaceSource ? "relinked.tif" : "first.tif";
            state.Validate(owner, source, true);
            state.Validate(owner, source, true);
            Check(state.IsCancelled && !state.HasDraft, "slider_repeated_refresh_keeps_cancellation");
            state.AllowUntrackedChanges(state.Revision);
            Check(state.IsCancelled, "slider_cannot_rearm_while_pointer_down");
            Check(!state.End(owner, source, true), "slider_previous_owner_cannot_commit");
            Check(state.IsCancelled, "slider_late_release_value_is_blocked");
            long oldRevision = state.Revision;
            state.Begin(owner, source);
            state.Cancel();
            state.AllowUntrackedChanges(oldRevision);
            Check(state.IsCancelled, "slider_old_dispatcher_callback_cannot_rearm_new_gesture");
            state.AllowUntrackedChanges(state.Revision);
            Check(state.IsCancelled, "slider_escape_cannot_rearm_while_pointer_down");
            state.End(owner, source, true);
            state.AllowUntrackedChanges(state.Revision);
            Check(!state.IsCancelled && !state.IsActive, "slider_accessibility_available_after_event_drain");
            state.Begin(owner, source);
            Check(state.End(owner, source, true), "slider_next_gesture_commits");
            Check(!state.End(owner, source, true), "slider_release_and_capture_lost_commit_only_once");
        }
        var disabled = new SliderPointerSession();
        disabled.Begin("frame", "source.tif");
        disabled.Validate("frame", "source.tif", false);
        disabled.Validate("frame", "source.tif", true);
        Check(!disabled.End("frame", "source.tif", true), "slider_disable_then_enable_cancels_gesture");
    }
}
