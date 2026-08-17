using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>원본 파일은 그대로 두고 catalog에 같은 원본을 가리키는 가상 사본 행을 만듭니다.</summary>
internal sealed class LibraryVirtualCopyService(LibraryDocumentState state)
{
    public string? Create(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        if (!state.IndexById.TryGetValue(frameId, out int index))
        {
            return null;
        }

        LibraryFrameSnapshot source = state.Frames.First(frame => frame.Id == frameId);
        string rootId = source.RootFrameId;

        int lastFamilyIndex = index;
        int nextNumber = 1;
        for (int candidate = 0; candidate < state.Frames.Count; candidate++)
        {
            if (state.Frames[candidate].RootFrameId != rootId)
            {
                continue;
            }
            lastFamilyIndex = state.IndexById[state.Frames[candidate].Id];
            if (state.Frames[candidate].VirtualCopyNumber is { } number && number >= nextNumber)
            {
                nextNumber = number + 1;
            }
        }

        string copyId = Guid.NewGuid().ToString("D");
        // 사본이 물려받는 것은 **뿌리의 이름**입니다. 원본 이름을 나중에 바꿔도 이미 만든 사본의
        // 이름은 그대로 남습니다 — macOS 도 만들 때 한 번 적습니다.
        JsonObject copy = LibraryFrameWriter.MakeVirtualCopy(
            state.Payloads[index],
            copyId,
            rootId,
            nextNumber,
            LibraryFrameNaming.DisplayName(source));

        state.Payloads.Insert(lastFamilyIndex + 1, copy);
        state.RowIds.Insert(lastFamilyIndex + 1, copyId);

        // 결함 편집은 물려받되 sidecar 는 **각자의 파일**이어야 합니다. 하나를 지우는 것이
        // 다른 하나를 깨뜨리면 안 됩니다. payload 에 hasDefectEdits 가 복제되어 왔으므로,
        // 사본 몫의 sidecar 를 지금 만들지 않으면 투영이 그 사진을 읽지 못해 목록에서
        // 사라집니다.
        if (state.DefectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? recipe) &&
            Guid.TryParseExact(copyId, "D", out Guid copyGuid))
        {
            DefectRecipeSnapshot copied = DefectRecipeSnapshot.Create(
                copyGuid,
                recipe.RecipeRevision,
                recipe.SourceIdentity,
                recipe.Items);
            if (state.Session.WriteDefectRecipe(copied).IsSuccess)
            {
                state.DefectRecipes[copyId] = copied;
            }
            else
            {
                // sidecar 를 못 만들면 사본은 결함 편집 없이 시작합니다. 읽을 수 없는 사진을
                // 목록에 남기는 것보다 낫습니다.
                copy.Remove("hasDefectEdits");
            }
        }

        state.ProjectFrames();
        return copyId;
    }
}
