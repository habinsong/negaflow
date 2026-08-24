using Negaflow.Catalog;

namespace Negaflow.Shell;

internal static class LibraryDefectEditor
{
    /// <summary>
    /// 결함 편집 한 칸의 되돌리기 이름입니다. macOS 는
    /// <c>AppModel+DefectHistory.recordDefectHistory</c> 가 편집마다 <c>UndoManager</c> 에
    /// 한 칸을 남깁니다 — 브러시 한 획, 복제 한 획, 가이드 한 번, 레이어 켜기·강도·삭제가
    /// 전부 ⌘Z 로 되돌아갑니다.
    /// </summary>
    internal const string UndoActionName = "developDefectEdit";

    internal static LibraryFrameError AppendStroke(
        LibraryDocument? document,
        string frameId,
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, DefectRecipeSnapshot?> build,
        LibraryDefectHistoryMode historyMode = LibraryDefectHistoryMode.PreservingInfrared) =>
        AppendStroke(
            document,
            frameId,
            (identity, existing, _) => build(identity, existing),
            historyMode);

    internal static LibraryFrameError AppendStroke(
        LibraryDocument? document,
        string frameId,
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, ulong, DefectRecipeSnapshot?> build,
        LibraryDefectHistoryMode historyMode = LibraryDefectHistoryMode.PreservingInfrared)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(build);
        if (document is null ||
            document.Frames.FirstOrDefault(candidate => candidate.Id == frameId) is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity) ||
            frame.DefectRecipeRevision == ulong.MaxValue ||
            build(
                identity,
                frame.DefectRecipe,
                frame.DefectRecipeRevision + 1UL) is not { } recipe)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }

        LibraryUndoSnapshot pendingUndo = document.CapturePendingDefectUndo(
            frameId,
            historyMode);
        LibraryDefectRecipeWriteResult written = document.WriteDefectRecipe(frameId, recipe);
        if (!written.IsSuccess)
        {
            return written.FrameError == LibraryFrameError.None
                ? LibraryFrameError.InvalidDefectRecipe
                : written.FrameError;
        }

        document.CommitPendingUndo(pendingUndo);
        return LibraryFrameError.None;
    }
}
