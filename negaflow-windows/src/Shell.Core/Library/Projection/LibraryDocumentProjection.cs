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
    internal Dictionary<string, int> IndexById { get; } = new(StringComparer.Ordinal);

    internal void ProjectFrames()
    {
        markDirty();
        Frames.Clear();
        Issues.Clear();
        IndexById.Clear();
        for (int index = 0; index < payloads.Count; index++)
        {
            using JsonDocument document = JsonDocument.Parse(
                CatalogJson.SerializeCanonical(payloads[index]));
            LibraryFrameReadResult read = LibraryFrameReader.Read(document.RootElement);
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
