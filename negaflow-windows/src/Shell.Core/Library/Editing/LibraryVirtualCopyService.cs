using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>원본 파일은 그대로 두고 catalog에 같은 원본을 가리키는 가상 사본 행을 만듭니다.</summary>
internal sealed class LibraryVirtualCopyService(LibraryDocumentState state)
{
    public string? Create(string frameId) =>
        Create(frameId, liveDefectItemId: null, liveDefectStrength: null);

    internal string? Create(
        string frameId,
        Guid? liveDefectItemId,
        double? liveDefectStrength)
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

        // 결함 편집은 물려받되 sidecar 는 **각자의 파일**이어야 합니다. 하나를 지우는 것이
        // 다른 하나를 깨뜨리면 안 됩니다. payload 에 hasDefectEdits 가 복제되어 왔으므로,
        // 사본 몫의 sidecar 를 지금 만들지 않으면 투영이 그 사진을 읽지 못해 목록에서
        // 사라집니다.
        if (state.DefectRecipes.TryGetValue(frameId, out DefectRecipeSnapshot? recipe) &&
            Guid.TryParseExact(copyId, "D", out Guid copyGuid))
        {
            if (FlushDirtyCatalog() != CatalogStoreError.None)
            {
                return null;
            }

            DefectRecipeSnapshot copied;
            try
            {
                copied = DefectRecipeSnapshot.Create(
                    copyGuid,
                    recipe.RecipeRevision,
                    recipe.SourceIdentity,
                    ItemsForCopy(recipe, liveDefectItemId, liveDefectStrength));
            }
            catch (Exception error) when (error is ArgumentException or OverflowException)
            {
                return null;
            }

            List<CatalogEntityRow> candidateRows = state.FrameRows();
            candidateRows.Insert(lastFamilyIndex + 1, new CatalogEntityRow(copyId, copy));
            DefectRecipeCatalogWriteResult committed =
                state.Session.WriteDefectRecipeAndCatalog(
                    copied,
                    state.CreateSnapshot(candidateRows));
            if (!committed.IsSuccess || committed.Snapshot is not { } stored)
            {
                return null;
            }

            state.Payloads.Insert(lastFamilyIndex + 1, copy);
            state.RowIds.Insert(lastFamilyIndex + 1, copyId);
            state.DefectRecipes[copyId] = stored;
            state.DefectRevisions.Observe(copyId, stored.RecipeRevision);
            state.ProjectFrames();
            state.IsDirty = false;
            return copyId;
        }

        state.Payloads.Insert(lastFamilyIndex + 1, copy);
        state.RowIds.Insert(lastFamilyIndex + 1, copyId);
        state.ProjectFrames();
        return copyId;
    }

    private CatalogStoreError FlushDirtyCatalog()
    {
        if (!state.IsDirty)
        {
            return CatalogStoreError.None;
        }

        CatalogStoreError error = state.Session.Write(
            state.CreateSnapshot(state.FrameRows())).Error;
        if (error == CatalogStoreError.None)
        {
            state.IsDirty = false;
        }
        return error;
    }

    private static IReadOnlyList<DefectEditItem> ItemsForCopy(
        DefectRecipeSnapshot recipe,
        Guid? liveDefectItemId,
        double? liveDefectStrength)
    {
        if (liveDefectItemId is not { } itemId ||
            liveDefectStrength is not { } strength ||
            !double.IsFinite(strength) ||
            strength is < 0.0 or > 1.0)
        {
            return recipe.Items;
        }

        DefectEditItem[] items = [.. recipe.Items];
        for (int index = 0; index < items.Length; ++index)
        {
            if (items[index].Id != itemId)
            {
                continue;
            }
            items[index] = items[index] with { Strength = strength };
            return items;
        }
        return recipe.Items;
    }
}
