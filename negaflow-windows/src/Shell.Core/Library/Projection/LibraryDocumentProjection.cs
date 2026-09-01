using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

internal sealed class LibraryDocumentProjection
{
    private readonly CatalogSession session;
    private readonly List<string> rowIds;
    private readonly List<JsonObject> payloads;
    private readonly Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows;
    private readonly Dictionary<string, DefectRecipeSnapshot> defectRecipes;
    private readonly LibraryDefectRevisionTracker defectRevisions;
    private readonly Action markDirty;

    internal LibraryDocumentProjection(
        CatalogSession session,
        List<string> rowIds,
        List<JsonObject> payloads,
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> retainedRows,
        Dictionary<string, DefectRecipeSnapshot> defectRecipes,
        LibraryDefectRevisionTracker defectRevisions,
        Action markDirty)
    {
        this.session = session;
        this.rowIds = rowIds;
        this.payloads = payloads;
        this.retainedRows = retainedRows;
        this.defectRecipes = defectRecipes;
        this.defectRevisions = defectRevisions;
        this.markDirty = markDirty;
    }

    internal List<LibraryFolderSnapshot> Folders { get; } = [];
    internal List<LibraryCollectionSnapshot> Collections { get; } = [];
    internal List<LibraryStackSnapshot> Stacks { get; } = [];
    internal List<LibraryRollSnapshot> Rolls { get; } = [];
    internal List<LibraryStoredSearchSnapshot> StoredSearches { get; } = [];
    internal List<LibraryFrameSnapshot> Frames { get; } = [];
    internal List<LibraryFrameIssue> Issues { get; } = [];

    /// <summary>
    /// 되돌려서 살린 사진의 수리 코드입니다. 사진은 목록에 그대로 있고, 무엇을 되돌렸는지만
    /// 진단에 남습니다.
    /// </summary>
    internal List<string> Repairs { get; } = [];
    internal Dictionary<string, int> IndexById { get; } = new(StringComparer.Ordinal);

    internal void ProjectFrames()
    {
        markDirty();
        Frames.Clear();
        Issues.Clear();
        IndexById.Clear();
        Repairs.Clear();
        for (int index = 0; index < payloads.Count; index++)
        {
            using JsonDocument document = JsonDocument.Parse(
                CatalogJson.SerializeCanonical(payloads[index]));
            LibraryFrameReadResult read = LibraryFrameReader.Read(document.RootElement);
            // 필드 하나가 규격을 벗어났다고 사진이 목록에서 사라져서는 안 됩니다. macOS 처럼
            // 그 필드만 되돌리고 다시 읽습니다 - 되돌린 값은 payload 에 남아 다음 저장에
            // 그대로 실립니다.
            if (read.Frame is null &&
                LibraryFrameRepair.TryRepair(payloads[index], read.Error, out string action))
            {
                using JsonDocument repaired = JsonDocument.Parse(
                    CatalogJson.SerializeCanonical(payloads[index]));
                LibraryFrameReadResult second = LibraryFrameReader.Read(repaired.RootElement);
                if (second.Frame is not null)
                {
                    Repairs.Add(action);
                    read = second;
                }
            }
            if (read.Frame is { } frame)
            {
                if (DeclaresDefectEdits(payloads[index]))
                {
                    if (!defectRecipes.TryGetValue(rowIds[index], out DefectRecipeSnapshot? recipe))
                    {
                        if (!Guid.TryParseExact(rowIds[index], "D", out Guid frameId) ||
                            session.ReadDefectRecipe(frameId).Snapshot is not { } loadedRecipe)
                        {
                            Issues.Add(new LibraryFrameIssue(
                                index,
                                rowIds[index],
                                LibraryFrameError.InvalidDefectRecipe,
                                DevelopRouteError.None));
                            continue;
                        }
                        recipe = loadedRecipe;
                        defectRecipes[rowIds[index]] = recipe;
                    }
                    defectRevisions.Observe(rowIds[index], recipe.RecipeRevision);
                    frame = frame with { DefectRecipe = recipe };
                }
                else
                {
                    defectRecipes.Remove(rowIds[index]);
                }
                frame = frame with
                {
                    DefectRecipeRevision = defectRevisions.Current(rowIds[index]),
                };
                Frames.Add(frame);
                IndexById[frame.Id] = index;
                continue;
            }
            Issues.Add(new LibraryFrameIssue(index, rowIds[index], read.Error, read.RouteError));
        }
    }

    internal void ProjectStoredSearches()
    {
        markDirty();
        StoredSearches.Clear();
        foreach ((CatalogEntityTable table, LibraryStoredSearchKind kind) in new[]
        {
            (CatalogEntityTable.SmartCollections, LibraryStoredSearchKind.SmartCollection),
            (CatalogEntityTable.SavedSearches, LibraryStoredSearchKind.SavedSearch),
        })
        {
            foreach (CatalogEntityRow row in retainedRows[table])
            {
                if (LibraryStoredSearchRecord.TryRead(row, kind, out LibraryStoredSearchSnapshot search))
                {
                    StoredSearches.Add(search);
                }
            }
        }
    }

    internal void ProjectRolls()
    {
        markDirty();
        Rolls.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Rolls])
        {
            if (LibraryRollRecordCodec.TryRead(row, out LibraryRollSnapshot roll))
            {
                Rolls.Add(roll);
            }
        }
    }

    internal void ProjectStacks()
    {
        markDirty();
        Stacks.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Stacks])
        {
            if (LibraryStackRecord.TryRead(row, out LibraryStackSnapshot stack))
            {
                Stacks.Add(stack);
            }
        }
    }

    internal void ProjectCollections()
    {
        markDirty();
        Collections.Clear();
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.ManualCollections])
        {
            if (LibraryCollectionRecord.TryRead(row, out LibraryCollectionSnapshot collection))
            {
                Collections.Add(collection);
            }
        }
    }

    internal void ProjectFolders()
    {
        markDirty();
        Folders.Clear();
        HashSet<string> seenPaths = new(StringComparer.OrdinalIgnoreCase);
        foreach (CatalogEntityRow row in retainedRows[CatalogEntityTable.Folders])
        {
            if (LibraryFolderRecord.TryRead(row, out LibraryFolderSnapshot folder) &&
                seenPaths.Add(folder.SourcePath))
            {
                Folders.Add(folder);
            }
        }
    }

    private static bool DeclaresDefectEdits(JsonObject payload) =>
        payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) &&
        node is JsonValue value && value.TryGetValue(out bool declared) && declared;
}
