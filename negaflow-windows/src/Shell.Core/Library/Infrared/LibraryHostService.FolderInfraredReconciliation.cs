using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 등록 폴더를 다시 훑을 때 <b>IR 짝</b>만 맞추는 자리입니다. 폴더 동기화 본체
/// (<c>LibraryHostService.FolderMonitoring.cs</c>) 는 무엇이 늘고 줄었는지를 다루고, 여기는
/// 파일 이름 규칙으로 본 스캔에 붙는 IR 채널이 지금도 맞는지만 다룹니다 — 바뀌는 이유가
/// 다르므로 파일도 나눕니다.
/// </summary>
public sealed partial class LibraryHostService
{
    private bool ReconcileInfraredCompanions(
        LibraryDocument open,
        string folder,
        IReadOnlyList<string> files,
        LibraryFolderChange change,
        HashSet<string> invalidated,
        ref bool retry)
    {
        // 짝짓기와 그 뒤의 프레임 조회가 같은 경로 풀이를 나눠 씁니다. 따로 풀면 폴더
        // 하나를 맞출 때마다 카탈로그 전체 프레임의 경로를 처음부터 다시 따라갑니다.
        InfraredImportPairing.IdentityScope identities = new();
        InfraredImportPairing.Resolution pairing = InfraredImportPairing.Resolve(
            files,
            [.. Frames.Select(frame => frame.SourcePath)],
            identities);
        HashSet<string> changedPaths = changePathsForInfrared(files);
        bool changedAny = false;
        foreach (LibraryFrameSnapshot frame in Frames
            .Where(frame => IsDirectChild(frame.SourcePath, folder))
            .ToArray())
        {
            if (!pairing.InfraredByBaseIdentity.TryGetValue(
                    identities.Identity(frame.SourcePath),
                    out string? expected))
            {
                expected = null;
            }
            bool samePath = string.Equals(
                    NormalizeFilePath(frame.InfraredPath),
                    NormalizeFilePath(expected),
                    StringComparison.OrdinalIgnoreCase);
            bool infraredContentChanged = expected is not null &&
                changedPaths.Contains(NormalizeFilePath(expected) ?? string.Empty);
            if (samePath && !infraredContentChanged)
            {
                continue;
            }

            _ = infraredClean.YieldToManualTool(frame.Id);
            if (!RemoveInfraredDefectItems(open, frame))
            {
                retry = true;
                continue;
            }
            LibraryFrameError edit = samePath
                ? LibraryFrameError.None
                : open.EditFrameRecord(frame.Id, record =>
            {
                JsonObject updated = (JsonObject)record.DeepClone();
                if (expected is null)
                {
                    updated.Remove(LibraryFrameReader.InfraredPathName);
                }
                else
                {
                    updated[LibraryFrameReader.InfraredPathName] = expected;
                }
                return DefectReviewTrackingCodec.Apply(updated, mark: null);
            });
            if (edit != LibraryFrameError.None)
            {
                retry = true;
                continue;
            }
            infraredCleanAttempted.Remove(frame.Id);
            invalidated.Add(frame.Id);
            changedAny = true;
            if (expected is not null)
            {
                OnImportedInfraredAttached(frame.Id);
            }
        }
        return changedAny;

        HashSet<string> changePathsForInfrared(IReadOnlyList<string> currentFiles)
        {
            HashSet<string> paths = change.ChangedPaths
                .Select(NormalizeFilePath)
                .Where(path => path is not null)
                .Select(path => path!)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (!change.RequiresFullReconciliation)
            {
                return paths;
            }
            // overflow/재시작에서는 어떤 파일이 바뀌었는지 알 수 없습니다. 경로 쌍 자체는
            // 유지하고, 실제 OS 이벤트가 있는 경우에만 비싼 IR 재검출을 다시 겁니다.
            paths.IntersectWith(currentFiles.Select(path => NormalizeFilePath(path) ?? string.Empty));
            return paths;
        }
    }

    private static bool RemoveInfraredDefectItems(
        LibraryDocument open,
        LibraryFrameSnapshot frame)
    {
        if (frame.DefectRecipe is not { } recipe ||
            !recipe.Items.Any(item => item.Kind == DefectEditKind.Infrared))
        {
            return true;
        }
        if (recipe.RecipeRevision == ulong.MaxValue)
        {
            return false;
        }
        DefectRecipeSnapshot next = DefectRecipeSnapshot.Create(
            recipe.FrameId,
            recipe.RecipeRevision + 1UL,
            recipe.SourceIdentity,
            [.. recipe.Items.Where(item => item.Kind != DefectEditKind.Infrared)]);
        return open.WriteDefectRecipe(frame.Id, next).IsSuccess;
    }
}
