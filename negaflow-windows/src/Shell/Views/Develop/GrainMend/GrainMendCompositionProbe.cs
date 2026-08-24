using System.Diagnostics;
using Microsoft.UI.Xaml.Media;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views;

/// <summary>한 UI 표면의 제출을 바로 다음 WinUI composition 프레임과 잇습니다.</summary>
internal sealed class GrainMendCompositionProbe
{
    private EventHandler<object>? pending;

    internal void Submit(
        GrainMendPresentationSample sample,
        string target,
        int width,
        int height)
    {
        if (!sample.IsEnabled)
        {
            return;
        }

        Cancel();
        long submittedTimestamp = Stopwatch.GetTimestamp();
        EventHandler<object>? handler = null;
        handler = (_, _) =>
        {
            long completedTimestamp = Stopwatch.GetTimestamp();
            if (handler is not null)
            {
                CompositionTarget.Rendering -= handler;
            }
            if (ReferenceEquals(pending, handler))
            {
                pending = null;
            }
            GrainMendPresentationTrace.Complete(
                sample,
                target,
                submittedTimestamp,
                completedTimestamp,
                width,
                height);
        };
        pending = handler;
        CompositionTarget.Rendering += handler;
    }

    internal void Cancel()
    {
        if (pending is not { } handler)
        {
            return;
        }
        CompositionTarget.Rendering -= handler;
        pending = null;
    }
}
