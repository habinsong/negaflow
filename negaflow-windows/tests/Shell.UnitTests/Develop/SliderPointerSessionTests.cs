using Negaflow.Catalog;
using Negaflow.Interop;
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

        VerifyPlainSyncKeepsTheDraft();
        VerifySourceInspectionKeepsSupportWhileRechecking();
    }

    /// <summary>
    /// **손잡이가 스프링처럼 튀던 자리입니다.** 같은 사진·같은 원본을 그대로 다시 그리는
    /// 단순 Sync 는 <b>잡고 있는 draft 를 건드리면 안 됩니다.</b>
    /// </summary>
    /// <remarks>
    /// 카드는 값이 바뀔 때마다 <c>Synchronize()</c> 로 화면을 다시 그리고, 그 안에서
    /// <see cref="SliderPointerSession.Validate"/> 를 부릅니다. 주인도 원본도 그대로인데
    /// 여기서 취소되면 draft 가 사라지고 손잡이가 모델 값(2.2)으로 되돌아갑니다 — 사용자가
    /// "슬라이더가 스프링처럼 튄다 / 계속 2.2 로 되돌아간다" 로 보고한 것이 이 모양입니다.
    ///
    /// 끌고 있는 동안 여러 번 다시 그려도 draft 가 살아 있어야 하고, 놓으면 그때 commit
    /// 되어야 합니다.
    /// </remarks>
    private static void VerifyPlainSyncKeepsTheDraft()
    {
        var state = new SliderPointerSession();
        state.Begin("frame-1", "frame-1.tif");
        for (int redraw = 0; redraw < 20; ++redraw)
        {
            state.Validate("frame-1", "frame-1.tif", true);
            Check(state.HasDraft, $"slider_plain_sync_keeps_draft_{redraw}");
        }
        Check(
            state.End("frame-1", "frame-1.tif", true),
            "slider_plain_sync_still_commits_on_release");
    }

    /// <summary>
    /// **끌던 손잡이가 튕기던 자리입니다.** 원본 metadata 가 한 번 바뀌면
    /// <see cref="InputGammaSourceInspection.Begin"/> 이 직전 판정을 비웠고, 그 사이
    /// <c>supported</c> 가 거짓이 되어 카드가 <c>Validate(..., canEdit: false)</c> 로 포인터
    /// 세션을 취소했습니다. 그러면 draft 가 사라지고 슬라이더가 모델 값으로 되돌아갑니다.
    /// 70MB TIFF 실측에서 그 창이 약 10초였고, 같은 이유로 수동 캡슐도 그 동안 죽었습니다.
    /// 같은 파일을 다시 확인하는 동안에는 직전 판정을 들고 있어야 합니다.
    /// </summary>
    private static void VerifySourceInspectionKeepsSupportWhileRechecking()
    {
        var inspection = new InputGammaSourceInspection();
        Check(inspection.Begin("a.tif", null) is { } first &&
              inspection.Complete(first, new InputGammaSource.Info(
                  true, InputGammaSource.CurveKind.EmbeddedPower, 2.19921875)),
            "input_gamma_inspection_completes_for_a_new_source");
        Check(inspection.Info.Supported, "input_gamma_inspection_reports_support");

        // 같은 파일인데 metadata 만 바뀌어 다시 확인에 들어갑니다.
        Check(inspection.Begin("a.tif", TestSourceMetadata) is not null,
            "input_gamma_inspection_rechecks_when_metadata_changes");
        Check(inspection.Info.Supported,
            "input_gamma_inspection_keeps_the_previous_support_while_rechecking");

        // 진행 중 세션은 살아 있어야 합니다 - 이것이 손잡이가 튕기지 않는 조건입니다.
        var drag = new SliderPointerSession();
        drag.Begin("frame", "a.tif");
        drag.Validate("frame", "a.tif", inspection.Info.Supported);
        Check(drag.HasDraft, "input_gamma_recheck_does_not_cancel_a_live_drag");

        // 파일 자체가 바뀌면 그때는 비웁니다.
        Check(inspection.Begin("b.tif", null) is not null,
            "input_gamma_inspection_rechecks_for_a_different_source");
        Check(!inspection.Info.Supported,
            "input_gamma_inspection_drops_support_for_a_different_source");
    }

    private static LibrarySourceMetadata TestSourceMetadata { get; } =
        new(70546662UL, 5959U, 3692U, 3, 8, 1, 1);
}
