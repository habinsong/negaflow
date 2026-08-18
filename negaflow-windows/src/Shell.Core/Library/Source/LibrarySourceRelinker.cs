using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>원본 파일 검증, frame 경로 교체, 등록 폴더 재기준화를 한 작업으로 수행합니다.</summary>
internal sealed class LibrarySourceRelinker(
    LibraryDocumentState state,
    LibraryCatalogPersistence persistence)
{
    public LibrarySourceRelinkResult Relink(
        SourceRelinkPlan plan,
        Func<string, LibrarySourceMetadata?>? sourceMetadataReader = null)
    {
        ArgumentNullException.ThrowIfNull(plan);
        Dictionary<string, string> mappings = new(StringComparer.OrdinalIgnoreCase);
        foreach (SourceRelinkMapping mapping in plan.Mappings)
        {
            if (!TryNormalizePath(mapping.OldSourcePath, out string oldPath) ||
                !TryNormalizePath(mapping.NewSourcePath, out string newPath) ||
                !File.Exists(newPath) ||
                !mappings.TryAdd(oldPath, newPath))
            {
                continue;
            }
        }
        List<JsonObject> previousPayloads = state.Payloads.ToList();
        IReadOnlyList<CatalogEntityRow> previousFolderRows = LibraryDocumentState.CloneRows(
            state.RetainedRows[CatalogEntityTable.Folders]);
        int requestedSourceCount = mappings.Count;
        int updatedFrames = 0;
        int updatedSources = 0;
        int rejectedSources = 0;
        HashSet<string> processed = new(StringComparer.OrdinalIgnoreCase);
        foreach (LibraryFrameSnapshot frame in state.Frames)
        {
            if (!TryNormalizePath(frame.SourcePath, out string oldPath) ||
                !mappings.TryGetValue(oldPath, out string? newPath) ||
                newPath is null ||
                !CanReadFile(newPath))
            {
                continue;
            }
            if (processed.Add(oldPath))
            {
                LibrarySourceMetadata? actualMetadata = null;
                foreach (LibraryFrameSnapshot familyFrame in state.Frames)
                {
                    if (!TryNormalizePath(familyFrame.SourcePath, out string familyPath) ||
                        !string.Equals(familyPath, oldPath, StringComparison.OrdinalIgnoreCase) ||
                        familyFrame.SourceMetadata is not { } expectedMetadata)
                    {
                        continue;
                    }
                    actualMetadata ??= sourceMetadataReader?.Invoke(newPath);
                    if (actualMetadata is null ||
                        !expectedMetadata.IsCompatibleWith(actualMetadata.Value))
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                }
                if (!mappings.ContainsKey(oldPath))
                {
                    continue;
                }
                DefectSourceIdentity? actual = null;
                foreach (LibraryFrameSnapshot familyFrame in state.Frames)
                {
                    if (!TryNormalizePath(familyFrame.SourcePath, out string familyPath) ||
                        !string.Equals(familyPath, oldPath, StringComparison.OrdinalIgnoreCase) ||
                        familyFrame.DefectRecipe?.SourceIdentity is not { } identity)
                    {
                        continue;
                    }
                    if (actual is null &&
                        (!TryReadSourceIdentity(newPath, out DefectSourceIdentity measured) ||
                         measured != identity))
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                    actual ??= identity;
                    if (actual != identity)
                    {
                        mappings.Remove(oldPath);
                        ++rejectedSources;
                        break;
                    }
                }
                if (!mappings.ContainsKey(oldPath))
                {
                    continue;
                }
                ++updatedSources;
            }
            if (!mappings.ContainsKey(oldPath) ||
                !state.IndexById.TryGetValue(frame.Id, out int index))
            {
                continue;
            }

            string? infrared = SourceRelinkPlanner.RelocateCompanion(frame.InfraredPath, plan);
            if (infrared is not null && PathsEqual(newPath, infrared))
            {
                ++rejectedSources;
                continue;
            }
            JsonObject updated = (JsonObject)state.Payloads[index].DeepClone();
            updated[LibraryFrameReader.SourcePathName] = newPath;
            // macOS `frame.baseRGB = nil` — 다른 원본의 실측 Dmin 을 새 파일에 남기지 않습니다.
            updated.Remove(LibraryFrameReader.BaseRgbName);
            if (infrared is not null)
            {
                updated[LibraryFrameReader.InfraredPathName] = infrared;
            }
            state.Payloads[index] = updated;
            ++updatedFrames;
        }
        rejectedSources += plan.Mappings.Count - updatedSources - rejectedSources;
        bool updatedFolder = RebaseRegisteredFolder(
            plan,
            allMappingsApplied: updatedSources == requestedSourceCount);
        if (updatedFrames == 0 && !updatedFolder)
        {
            return new(0, 0, Math.Max(0, rejectedSources), CatalogStoreError.None);
        }

        state.ProjectFolders();
        state.ProjectFrames();
        CatalogStoreError saved = persistence.Save();
        if (saved == CatalogStoreError.None)
        {
            return new(updatedFrames, updatedSources, Math.Max(0, rejectedSources), saved);
        }
        state.Payloads.Clear();
        state.Payloads.AddRange(previousPayloads);
        state.RetainedRows[CatalogEntityTable.Folders] = previousFolderRows;
        state.ProjectFolders();
        state.ProjectFrames();
        return new(0, 0, Math.Max(0, rejectedSources), saved);
    }

    private bool RebaseRegisteredFolder(SourceRelinkPlan plan, bool allMappingsApplied)
    {
        if (!plan.IsComplete ||
            !allMappingsApplied ||
            !LibraryFolderRecord.TryNormalizePath(plan.OldFolderPath, out string oldRoot) ||
            !LibraryFolderRecord.TryNormalizePath(plan.NewFolderPath, out string newRoot))
        {
            return false;
        }

        List<CatalogEntityRow> updatedRows = [];
        bool changed = false;
        foreach (CatalogEntityRow row in state.RetainedRows[CatalogEntityTable.Folders])
        {
            if (LibraryFolderRecord.TryRead(row, out LibraryFolderSnapshot folder) &&
                string.Equals(folder.SourcePath, oldRoot, StringComparison.OrdinalIgnoreCase))
            {
                updatedRows.Add(LibraryFolderRecord.Write(folder with { SourcePath = newRoot }));
                changed = true;
            }
            else
            {
                updatedRows.Add(new CatalogEntityRow(
                    row.Id,
                    (JsonObject)row.Payload.DeepClone()));
            }
        }

        if (changed)
        {
            state.RetainedRows[CatalogEntityTable.Folders] = updatedRows;
        }
        return changed;
    }

    private static bool TryReadSourceIdentity(string path, out DefectSourceIdentity identity)
    {
        identity = default;
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 128 * 1024,
                FileOptions.SequentialScan);
            if (stream.Length <= 0)
            {
                return false;
            }
            identity = new DefectSourceIdentity(
                checked((ulong)stream.Length),
                Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant());
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException or OverflowException)
        {
            return false;
        }
    }

    private static bool CanReadFile(string path)
    {
        try
        {
            using FileStream stream = new(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 1,
                FileOptions.SequentialScan);
            return stream.Length > 0;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or
            NotSupportedException or ArgumentException or PathTooLongException)
        {
            return false;
        }
    }

    private static bool TryNormalizePath(string path, out string normalized)
    {
        normalized = string.Empty;
        if (string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path))
        {
            return false;
        }
        try
        {
            normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
            return true;
        }
        catch (Exception error) when (error is ArgumentException or NotSupportedException or
            PathTooLongException)
        {
            return false;
        }
    }

    private static bool PathsEqual(string left, string right) =>
        TryNormalizePath(left, out string normalizedLeft) &&
        TryNormalizePath(right, out string normalizedRight) &&
        string.Equals(normalizedLeft, normalizedRight, StringComparison.OrdinalIgnoreCase);
}
