using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// macOS <c>AppModel+LocalAdjustments</c> 의 카탈로그 쓰기 자리입니다.
/// </summary>
public sealed partial class DevelopPanelState
{
    /// <summary>
    /// 부분 보정 목록을 통째로 갈아 끼웁니다. macOS <c>replaceLocalAdjustments</c> 처럼
    /// 값이 그대로면 아무 것도 하지 않고, 바뀌었으면 되돌릴 수 있게 적습니다.
    /// </summary>
    public LibraryFrameError EditLocalDodgeBurn(
        string frameId,
        IReadOnlyList<LocalDodgeBurnAdjustment> adjustments)
    {
        ArgumentException.ThrowIfNullOrEmpty(frameId);
        ArgumentNullException.ThrowIfNull(adjustments);
        if (SelectedFrame is not { } frame ||
            !string.Equals(frame.Id, frameId, StringComparison.Ordinal))
        {
            return LibraryFrameError.MissingId;
        }
        if (frame.LocalDodgeBurn.SequenceEqual(adjustments))
        {
            return LibraryFrameError.None;
        }

        LibraryFrameError error = host.EditUndoable(
            frame.Id,
            LibraryHostService.UndoActions.DevelopAdjustment,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                LocalDodgeBurn: adjustments));
        return RefreshAfterEdit(new DevelopEditResult(error, error == LibraryFrameError.None));
    }
}
