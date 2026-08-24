using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>라이브러리에서 frame을 빼고 롤·컬렉션·스택 소속을 함께 정리합니다.</summary>
internal sealed class LibraryFrameRemovalService(LibraryDocumentState state)
{
    public LibraryFrameRemoval Remove(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        var removing = new HashSet<string>(state.KnownFrameIds(frameIds), StringComparer.Ordinal);
        if (removing.Count == 0)
        {
            return new LibraryFrameRemoval([], []);
        }

        var sidecars = new List<(Guid FrameId, ulong Revision)>();
        for (int index = state.Payloads.Count - 1; index >= 0; index--)
        {
            if (!removing.Contains(state.RowIds[index]))
            {
                continue;
            }
            if (state.DefectRecipes.Remove(state.RowIds[index], out DefectRecipeSnapshot? recipe) &&
                Guid.TryParseExact(state.RowIds[index], "D", out Guid sidecarId))
            {
                sidecars.Add((sidecarId, recipe.RecipeRevision));
            }
            state.DefectRevisions.Remove(state.RowIds[index]);
            state.Payloads.RemoveAt(index);
            state.RowIds.RemoveAt(index);
        }

        DropMembership(CatalogEntityTable.Rolls, removing);
        DropMembership(CatalogEntityTable.ManualCollections, removing);
        DropMembership(CatalogEntityTable.Stacks, removing);
        // 한 장만 남은 묶음은 접어도 아무것도 감추지 않으면서 배지만 남깁니다. 없앱니다.
        state.RetainedRows[CatalogEntityTable.Stacks] =
            [.. state.RetainedRows[CatalogEntityTable.Stacks].Where(row =>
                LibraryStackRecord.TryRead(row, out _))];
        state.ProjectRolls();
        state.ProjectCollections();
        state.ProjectStacks();
        state.ProjectFrames();
        return new LibraryFrameRemoval([.. removing], sidecars);
    }

    private void DropMembership(CatalogEntityTable table, HashSet<string> removing)
    {
        List<CatalogEntityRow> rows = [.. state.RetainedRows[table]];
        bool changed = false;
        for (int index = 0; index < rows.Count; index++)
        {
            if (rows[index].Payload["frameIDs"] is not JsonArray members)
            {
                continue;
            }
            var kept = new JsonArray();
            bool dropped = false;
            foreach (JsonNode? member in members)
            {
                if (member?.GetValue<string>() is { } frameId && removing.Contains(frameId))
                {
                    dropped = true;
                    continue;
                }
                kept.Add(member?.DeepClone());
            }
            if (!dropped)
            {
                continue;
            }
            JsonObject payload = (JsonObject)rows[index].Payload.DeepClone();
            payload["frameIDs"] = kept;
            rows[index] = new CatalogEntityRow(rows[index].Id, payload);
            changed = true;
        }
        if (changed)
        {
            state.RetainedRows[table] = rows;
        }
    }
}
