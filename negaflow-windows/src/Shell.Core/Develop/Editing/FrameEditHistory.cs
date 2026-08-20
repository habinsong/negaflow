namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>AppModel+FrameEditHistory</c> — 드래그 한 줄을 undo 한 칸.</summary>
public sealed class FrameEditHistory
{
    /// <summary>macOS <c>frameEditCoalesceInterval</c>.</summary>
    public const double CoalesceSeconds = 0.7;

    private string? gestureFrameId;
    private DateTime gestureUntilUtc;

    /// <summary>
    /// 이번 편집이 새 제스처면 true — 호출측이 CaptureUndo 한다.
    /// 같은 제스처의 연속 변경이면 false 이고 창만 0.7초 연장한다.
    /// </summary>
    public bool ConsumeCapture(string frameId, DateTime utcNow)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        if (string.Equals(gestureFrameId, frameId, StringComparison.Ordinal) &&
            utcNow < gestureUntilUtc)
        {
            gestureUntilUtc = utcNow.AddSeconds(CoalesceSeconds);
            return false;
        }

        gestureFrameId = frameId;
        gestureUntilUtc = utcNow.AddSeconds(CoalesceSeconds);
        return true;
    }

    public void Clear()
    {
        gestureFrameId = null;
        gestureUntilUtc = default;
    }

    public void Clear(string frameId)
    {
        if (string.Equals(gestureFrameId, frameId, StringComparison.Ordinal))
        {
            Clear();
        }
    }
}
