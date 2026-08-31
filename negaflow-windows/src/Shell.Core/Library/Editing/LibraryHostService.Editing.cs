using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>편집·되돌리기·자동 IR 몫입니다.</summary>
public sealed partial class LibraryHostService
{
    public bool CanUndo => document?.CanUndo == true;

    public bool CanRedo => document?.CanRedo == true;

    public string? UndoActionName => document?.UndoActionName;

    public string? RedoActionName => document?.RedoActionName;

    public bool CanUndoDefectFrame(string frameId) =>
        document?.CanUndoDefectFrame(frameId) == true;

    /// <summary>문서가 저장까지 완료한 한 단계를 되돌리고 그 동작의 이름을 돌려줍니다.</summary>
    public string? Undo()
    {
        frameEdits.Clear();
        if (document is not { } open)
        {
            return null;
        }
        return ApplyHistoryResult(open.UndoWithResult());
    }

    public string? Redo()
    {
        frameEdits.Clear();
        if (document is not { } open)
        {
            return null;
        }
        return ApplyHistoryResult(open.RedoWithResult());
    }

    internal string? ApplyHistoryResult(
        LibraryHistoryResult result,
        bool publishEdit = true)
    {
        StoreError = result.CatalogError;
        DefectSidecarError = result.SidecarError;
        if (result.RequiresRecovery)
        {
            LibraryDocument? failed = document;
            document = null;
            State = LibraryHostState.Unavailable;
            availability.Reset();
            infraredClean.Reset();
            infraredCleanAttempted.Clear();
            failed?.Dispose();
            selection.Set([], [], null);
            return null;
        }
        if (result.ActionName is not { } name)
        {
            return null;
        }

        if (publishEdit)
        {
            FrameEdited?.Invoke(this, EventArgs.Empty);
        }
        // **사진 목록 자체가 달라지는 단계**는 세 화면을 다시 맞춰야 합니다. `FrameEdited` 는
        // "같은 사진의 값이 바뀌었다" 는 알림이라 필름스트립의 목록을 다시 읽게 하지
        // 않습니다 - 되돌린 "제거" 가 라이브러리 격자에만 돌아오고 필름스트립에는 없던
        // 까닭입니다. 슬라이더 되돌리기도 이 길로 오므로 목록이 바뀌는 동작만 고릅니다.
        if (ChangesFrameList(name))
        {
            LibraryContentChanged?.Invoke(this, new LibraryContentChangedEventArgs([], [], []));
        }
        return name;
    }

    /// <summary>되돌리기 한 단계가 사진 <b>목록</b>을 바꾸는지입니다.</summary>
    private static bool ChangesFrameList(string actionName) => actionName is
        UndoActions.RemoveFrames or UndoActions.VirtualCopy or
        UndoActions.CreateStack or UndoActions.UngroupStack;

    private readonly FrameEditHistory frameEdits = new();

    /// <summary>macOS <c>recordFrameEditIfChanged</c> — <see cref="Edit"/> 길목.</summary>
    private LibraryFrameError AfterCoalescedDevelopEdit(
        string frameId,
        Func<LibraryFrameError> edit)
    {
        if (document is not { } open)
        {
            return LibraryFrameError.MissingId;
        }

        DateTime now = DateTime.UtcNow;
        bool captured = frameEdits.ConsumeCapture(frameId, now);
        if (captured)
        {
            open.CaptureUndo(UndoActions.DevelopAdjustment);
        }

        LibraryFrameError error = edit();
        if (error != LibraryFrameError.None && captured)
        {
            _ = ApplyHistoryResult(open.UndoWithResult(), publishEdit: false);
            return error;
        }

        return AfterEdit(error);
    }

    /// <summary>
    /// 바꾸기 직전 상태를 담고 편집을 돌린 뒤 저장합니다. 편집이 아무것도 바꾸지 않았으면
    /// 담아 둔 상태를 도로 버립니다 — 아무 일도 없었던 편집이 되돌리기 더미를 채우면 Ctrl+Z 가
    /// 헛돕니다.
    /// </summary>
    private T Undoable<T>(string actionName, Func<T> mutate)
    {
        if (document is not { } open)
        {
            return mutate();
        }
        open.CaptureUndo(actionName);
        T result = mutate();
        bool changed = result switch
        {
            bool flag => flag,
            null => false,
            _ => true,
        };
        if (!changed)
        {
            _ = ApplyHistoryResult(open.UndoWithResult(), publishEdit: false);
            return result;
        }
        _ = SaveIfDirty();
        return result;
    }

    private bool SavedAfter(bool changed)
    {
        if (changed)
        {
            _ = SaveIfDirty();
        }
        return changed;
    }

    /// <summary>사이드카가 적을 frame record 의 복사본입니다.</summary>
    public System.Text.Json.Nodes.JsonObject? FrameRecord(string frameId) =>
        document?.FrameRecord(frameId);

    /// <summary>현상 버전을 담거나 되돌리거나, 현상 설정을 붙여넣습니다.</summary>
    public LibraryFrameError EditFrameRecord(
        string frameId,
        Func<System.Text.Json.Nodes.JsonObject, LibraryFrameWriteResult> edit) =>
        AfterEdit(document is null
            ? LibraryFrameError.MissingId
            : document.EditFrameRecord(frameId, edit));

    private LibraryFrameError AfterEdit(LibraryFrameError error)
    {
        if (error == LibraryFrameError.None)
        {
            ScheduleSave();
            FrameEdited?.Invoke(this, EventArgs.Empty);
        }
        return error;
    }

}
