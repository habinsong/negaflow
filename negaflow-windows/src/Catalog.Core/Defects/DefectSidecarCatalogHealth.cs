namespace Negaflow.Catalog;

internal sealed record DefectSidecarCatalogEntry(
    string CatalogFrameId,
    Guid FrameId,
    string Path,
    DefectRecipeSnapshot Snapshot);

internal readonly record struct DefectCatalogHealthResult(
    IReadOnlyList<DefectSidecarCatalogEntry>? Entries,
    DefectSidecarError Error)
{
    public bool IsHealthy => Error == DefectSidecarError.None && Entries is not null;

    public static DefectCatalogHealthResult Healthy(
        IReadOnlyList<DefectSidecarCatalogEntry> entries) =>
        new(entries, DefectSidecarError.None);

    public static DefectCatalogHealthResult Failure(DefectSidecarError error) =>
        new(null, error);
}

/// <summary>
/// catalog 가 선언한 defect sidecar 가 실제로 있고 읽히는지 확인합니다. 하나라도
/// 어긋나면 목록을 내지 않습니다 - 반쪽짜리 목록으로 복구를 시작하면 더 나빠집니다.
/// </summary>
internal static class DefectSidecarCatalogHealth
{
    public static DefectCatalogHealthResult ValidateCatalogDeclarations(
        StorageRootSet roots,
        CatalogSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(roots);
        ArgumentNullException.ThrowIfNull(snapshot);
        lock (DefectSidecarStore.Gate)
        {
            if (!DefectSidecarFile.HasValidRoots(roots))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.InvalidStorageRoots);
            }
            if (File.Exists(roots.DefectRecipeRoot) ||
                StoragePathPolicy.IsExistingReparsePoint(roots.DefectRecipeRoot))
            {
                return DefectCatalogHealthResult.Failure(
                    DefectSidecarError.ReparsePointNotAllowed);
            }

            List<DefectSidecarCatalogEntry> entries = [];
            HashSet<Guid> frameIds = [];
            foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
            {
                if (!frame.Payload.TryGetPropertyValue(
                        "hasDefectEdits",
                        out System.Text.Json.Nodes.JsonNode? node) ||
                    node is null)
                {
                    continue;
                }
                if (node is not System.Text.Json.Nodes.JsonValue value ||
                    !value.TryGetValue(out bool hasEdits))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidContent);
                }
                if (!hasEdits)
                {
                    continue;
                }
                if (!Guid.TryParseExact(frame.Id, "D", out Guid frameId) ||
                    frameId == Guid.Empty ||
                    !frameIds.Add(frameId))
                {
                    return DefectCatalogHealthResult.Failure(
                        DefectSidecarError.InvalidFrameId);
                }

                string path = DefectSidecarStore.PathFor(roots, frameId);
                DefectSidecarReadResult read = DefectSidecarFile.ReadFile(path, frameId);
                if (read.Snapshot is not { } recipe)
                {
                    return DefectCatalogHealthResult.Failure(read.Error);
                }
                entries.Add(new DefectSidecarCatalogEntry(
                    frame.Id,
                    frameId,
                    path,
                    recipe));
            }
            entries.Sort((left, right) => StringComparer.Ordinal.Compare(
                left.CatalogFrameId,
                right.CatalogFrameId));
            return DefectCatalogHealthResult.Healthy(entries);
        }
    }
}
