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
        Func<DefectSourceIdentity, DefectRecipeSnapshot?, DefectRecipeSnapshot?> build)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        ArgumentNullException.ThrowIfNull(build);
        if (document is null ||
            document.Frames.FirstOrDefault(candidate => candidate.Id == frameId) is not { } frame)
        {
            return LibraryFrameError.MissingId;
        }

        if (!DefectSourceIdentityReader.TryRead(frame.SourcePath, out DefectSourceIdentity identity) ||
            build(identity, frame.DefectRecipe) is not { } recipe)
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }

        // ☠️ 되돌리기 칸은 **쓰기 직전**에 담습니다. macOS 는 편집이 성공한 뒤에 담긴
        //    스냅숏을 등록하는데, 여기 되돌리기 더미는 "지금 상태"를 담는 방식이라 순서가
        //    반대입니다. 실패하면 방금 담은 칸을 도로 빼서 결과를 같게 맞춥니다 —
        //    실패한 편집이 Ctrl+Z 한 번을 잡아먹으면 안 됩니다.
        //
        //    되돌리기 스냅숏은 `LibraryUndoCoordinator.Capture` 가 `DefectRecipes` 를 통째로
        //    담으므로 IR 레이어까지 정확히 돌아옵니다. macOS 의 `.preservingInfrared` 모드는
        //    그쪽 IR 이 세션 메모리에만 살아 다시 만들 수 없기 때문에 필요한 것이고,
        //    Windows 는 recipe 에 저장하므로 정확 복원이 곧 macOS `.exact` 와 같습니다.
        document.CaptureUndo(UndoActionName);
        LibraryDefectRecipeWriteResult written = document.WriteDefectRecipe(frameId, recipe);
        if (!written.IsSuccess)
        {
            _ = document.Undo();
            return written.FrameError == LibraryFrameError.None
                ? LibraryFrameError.InvalidDefectRecipe
                : written.FrameError;
        }

        return LibraryFrameError.None;
    }
}
