using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 결함 recipe 변경과 그 revision을 처음 소비한 preview 사이의 잠금입니다.
/// 검출은 recipe를 바꾸지 않으므로 이 상태에 포함하지 않습니다.
/// </summary>
public sealed class GrainMendPreviewBuildState
{
    private string? frameId;
    private ulong recipeRevision;

    public bool IsBusy => frameId is not null;

    public void Begin(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        frameId = frame.Id;
        recipeRevision = frame.DefectRecipeRevision;
    }

    public bool Complete(LibraryFrameSnapshot renderedFrame)
    {
        ArgumentNullException.ThrowIfNull(renderedFrame);
        if (!string.Equals(frameId, renderedFrame.Id, StringComparison.Ordinal) ||
            recipeRevision != renderedFrame.DefectRecipeRevision)
        {
            return false;
        }

        Reset();
        return true;
    }

    public void Reset()
    {
        frameId = null;
        recipeRevision = 0UL;
    }
}
