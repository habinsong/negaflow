using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>편집·되돌리기·자동 IR 몫입니다.</summary>
public sealed partial class LibraryHostService
{
    public bool CanUndo => document?.CanUndo == true;

    public bool CanRedo => document?.CanRedo == true;

    public string? UndoActionName => document?.UndoActionName;

    public string? RedoActionName => document?.RedoActionName;

    /// <summary>한 단계 되돌리고 저장합니다. 되돌린 동작의 이름을 돌려줍니다.</summary>
    public string? Undo()
    {
        frameEdits.Clear();
        string? name = document?.Undo();
        if (name is not null)
        {
            _ = SaveIfDirty();
        }
        return name;
    }

    public string? Redo()
    {
        frameEdits.Clear();
        string? name = document?.Redo();
        if (name is not null)
        {
            _ = SaveIfDirty();
        }
        return name;
    }

    private readonly FrameEditHistory frameEdits = new();
    private readonly HashSet<string> infraredCleanAttempted = new(StringComparer.Ordinal);

    /// <summary>macOS <c>runInfraredCleanIfNeeded</c>.</summary>
    public InfraredDefectApplyResult? TryInfraredCleanIfNeeded(string? frameId)
    {
        if (document is null || frameId is null)
        {
            return null;
        }

        LibraryFrameSnapshot? frame = Frames.FirstOrDefault(candidate =>
            string.Equals(candidate.Id, frameId, StringComparison.Ordinal));
        bool attempted = infraredCleanAttempted.Contains(frameId);
        if (!InfraredCleanPolicy.ShouldRun(frame, attempted) || frame is null)
        {
            return null;
        }

        infraredCleanAttempted.Add(frameId);
        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity) ||
            frame.InfraredPath is not { } infraredPath)
        {
            if (InfraredCleanPolicy.ShouldRearm(InfraredDefectApplyStatus.DetectionFailed))
            {
                infraredCleanAttempted.Remove(frameId);
            }

            return new InfraredDefectApplyResult(
                InfraredDefectApplyStatus.DetectionFailed,
                null,
                null,
                DefectSidecarError.None,
                CatalogStoreError.None);
        }

        InfraredDefectApplyResult result = InfraredDefectRecipeCoordinator.RunFiles(
            document,
            frame,
            identity,
            frame.SourcePath,
            infraredPath);
        if (InfraredCleanPolicy.ShouldRearm(result.Status))
        {
            infraredCleanAttempted.Remove(frameId);
        }

        return result;
    }

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
            _ = open.Undo();
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
            _ = open.Undo();
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
