using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>컬렉션, 롤, 저장된 찾기, 스택의 catalog 행과 활성 롤 상태를 관리합니다.</summary>
internal sealed class LibraryOrganizationService(LibraryDocumentState state)
{
    public LibraryRollSnapshot? RollFor(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        return state.Rolls.FirstOrDefault(roll =>
            roll.FrameIds.Contains(frameId, StringComparer.Ordinal));
    }

    public LibraryStackSnapshot? StackFor(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        LibraryStackSnapshot? found = null;
        foreach (LibraryStackSnapshot stack in state.Stacks)
        {
            if (!stack.FrameIds.Contains(frameId, StringComparer.Ordinal))
            {
                continue;
            }
            if (found is not null)
            {
                return null;
            }
            found = stack;
        }
        return found;
    }

    public string? CreateCollection(string name, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return null;
        }
        LibraryCollectionSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            normalized,
            state.KnownFrameIds(frameIds));
        List<CatalogEntityRow> rows =
            [.. state.RetainedRows[CatalogEntityTable.ManualCollections]];
        rows.Add(LibraryCollectionRecord.Write(created));
        state.RetainedRows[CatalogEntityTable.ManualCollections] = rows;
        state.ProjectCollections();
        return created.Id;
    }

    public bool RenameCollection(string collectionId, string name)
    {
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return false;
        }
        return ReplaceCollection(
            collectionId,
            existing => existing with { Name = normalized });
    }

    public bool SetCollectionFrames(string collectionId, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = state.KnownFrameIds(frameIds);
        return ReplaceCollection(collectionId, existing => existing with { FrameIds = known });
    }

    public bool DeleteCollection(string collectionId)
    {
        ArgumentException.ThrowIfNullOrEmpty(collectionId);
        List<CatalogEntityRow> rows =
            [.. state.RetainedRows[CatalogEntityTable.ManualCollections]];
        int removed = rows.RemoveAll(row =>
            string.Equals(row.Id, collectionId, StringComparison.Ordinal));
        if (removed == 0)
        {
            return false;
        }
        state.RetainedRows[CatalogEntityTable.ManualCollections] = rows;
        state.ProjectCollections();
        return true;
    }

    public string? CreateRoll(string name, FilmType filmType, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        if (AppMetadataOverlay.NormalizeText(name) is not { } normalized)
        {
            return null;
        }
        LibraryRollSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            LibraryRollKind.Physical,
            normalized,
            DateTimeOffset.UtcNow,
            filmType,
            state.KnownFrameIds(frameIds),
            null);
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Rolls]];
        rows.Add(LibraryRollRecordCodec.Write(created));
        state.RetainedRows[CatalogEntityTable.Rolls] = rows;
        state.ProjectRolls();
        return created.Id;
    }

    public bool SetRollRecord(string rollId, RollRecord? record) =>
        ReplaceRoll(rollId, existing => existing with
        {
            Record = record is { } value && !value.Normalized().IsEmpty
                ? value.Normalized()
                : null,
        });

    public bool SetRollFrames(string rollId, IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = state.KnownFrameIds(frameIds);
        return ReplaceRoll(rollId, existing => existing with { FrameIds = known });
    }

    public bool DeleteRoll(string rollId)
    {
        ArgumentException.ThrowIfNullOrEmpty(rollId);
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Rolls]];
        if (rows.RemoveAll(row =>
                string.Equals(row.Id, rollId, StringComparison.Ordinal)) == 0)
        {
            return false;
        }
        state.RetainedRows[CatalogEntityTable.Rolls] = rows;
        if (string.Equals(state.ActiveRollId, rollId, StringComparison.Ordinal))
        {
            state.ActiveRollId = null;
        }
        state.ProjectRolls();
        return true;
    }

    public bool SetActiveRoll(string? rollId)
    {
        if (rollId is not null &&
            !state.Rolls.Any(roll => string.Equals(roll.Id, rollId, StringComparison.Ordinal)))
        {
            return false;
        }
        if (string.Equals(state.ActiveRollId, rollId, StringComparison.Ordinal))
        {
            return true;
        }
        state.ActiveRollId = rollId;
        state.MarkDirty();
        return true;
    }

    public string? CreateStoredSearch(
        string name,
        LibraryStoredSearchKind kind,
        LibraryStoredQuery query)
    {
        ArgumentNullException.ThrowIfNull(query);
        if (LibraryCollectionSnapshot.NormalizeName(name) is not { } normalized)
        {
            return null;
        }
        LibraryStoredSearchSnapshot created = new(
            Guid.NewGuid().ToString("D"),
            normalized,
            kind,
            query);
        if (LibraryStoredSearchRecord.Write(created) is not { } row)
        {
            return null;
        }
        CatalogEntityTable table = kind == LibraryStoredSearchKind.SmartCollection
            ? CatalogEntityTable.SmartCollections
            : CatalogEntityTable.SavedSearches;
        state.RetainedRows[table] = [.. state.RetainedRows[table], row];
        state.ProjectStoredSearches();
        return created.Id;
    }

    public bool DeleteStoredSearch(string searchId)
    {
        ArgumentException.ThrowIfNullOrEmpty(searchId);
        bool removed = false;
        foreach (CatalogEntityTable table in new[]
        {
            CatalogEntityTable.SmartCollections,
            CatalogEntityTable.SavedSearches,
        })
        {
            List<CatalogEntityRow> rows = [.. state.RetainedRows[table]];
            if (rows.RemoveAll(row =>
                    string.Equals(row.Id, searchId, StringComparison.Ordinal)) > 0)
            {
                state.RetainedRows[table] = rows;
                removed = true;
            }
        }
        if (removed)
        {
            state.ProjectStoredSearches();
        }
        return removed;
    }

    public string? CreateStack(IEnumerable<string> frameIds)
    {
        ArgumentNullException.ThrowIfNull(frameIds);
        IReadOnlyList<string> known = state.KnownFrameIds(frameIds);
        if (known.Any(frameId => StackFor(frameId) is not null))
        {
            return null;
        }
        string id = Guid.NewGuid().ToString("D");
        if (LibraryStackSnapshot.TryCreate(id, known, isCollapsed: true) is not { } created)
        {
            return null;
        }
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Stacks]];
        rows.Add(LibraryStackRecord.Write(created));
        state.RetainedRows[CatalogEntityTable.Stacks] = rows;
        state.ProjectStacks();
        return id;
    }

    public bool UngroupStack(string stackId)
    {
        ArgumentException.ThrowIfNullOrEmpty(stackId);
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Stacks]];
        if (rows.RemoveAll(row =>
                string.Equals(row.Id, stackId, StringComparison.Ordinal)) == 0)
        {
            return false;
        }
        state.RetainedRows[CatalogEntityTable.Stacks] = rows;
        state.ProjectStacks();
        return true;
    }

    public bool ToggleStackCollapsed(string stackId)
    {
        ArgumentException.ThrowIfNullOrEmpty(stackId);
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Stacks]];
        for (int index = 0; index < rows.Count; index++)
        {
            if (!string.Equals(rows[index].Id, stackId, StringComparison.Ordinal) ||
                !LibraryStackRecord.TryRead(rows[index], out LibraryStackSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryStackRecord.Write(
                existing with { IsCollapsed = !existing.IsCollapsed });
            state.RetainedRows[CatalogEntityTable.Stacks] = rows;
            state.ProjectStacks();
            return true;
        }
        return false;
    }

    private bool ReplaceCollection(
        string collectionId,
        Func<LibraryCollectionSnapshot, LibraryCollectionSnapshot> update)
    {
        ArgumentException.ThrowIfNullOrEmpty(collectionId);
        List<CatalogEntityRow> rows =
            [.. state.RetainedRows[CatalogEntityTable.ManualCollections]];
        for (int index = 0; index < rows.Count; ++index)
        {
            if (!string.Equals(rows[index].Id, collectionId, StringComparison.Ordinal) ||
                !LibraryCollectionRecord.TryRead(
                    rows[index],
                    out LibraryCollectionSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryCollectionRecord.Write(update(existing));
            state.RetainedRows[CatalogEntityTable.ManualCollections] = rows;
            state.ProjectCollections();
            return true;
        }
        return false;
    }

    private bool ReplaceRoll(
        string rollId,
        Func<LibraryRollSnapshot, LibraryRollSnapshot> update)
    {
        ArgumentException.ThrowIfNullOrEmpty(rollId);
        List<CatalogEntityRow> rows = [.. state.RetainedRows[CatalogEntityTable.Rolls]];
        for (int index = 0; index < rows.Count; ++index)
        {
            if (!string.Equals(rows[index].Id, rollId, StringComparison.Ordinal) ||
                !LibraryRollRecordCodec.TryRead(rows[index], out LibraryRollSnapshot existing))
            {
                continue;
            }
            rows[index] = LibraryRollRecordCodec.Write(update(existing));
            state.RetainedRows[CatalogEntityTable.Rolls] = rows;
            state.ProjectRolls();
            return true;
        }
        return false;
    }
}
